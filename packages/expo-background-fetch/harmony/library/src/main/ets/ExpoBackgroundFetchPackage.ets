import { workScheduler } from '@kit.BackgroundTasksKit';
import { bundleManager } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import {
  ExpoTaskConsumer,
  ExpoTaskExecutionResult,
  ExpoTaskManagerRegistry,
  ExpoTaskManagerWorkMetadata,
  ExpoTaskRecord,
} from '@expo-harmony/expo-task-manager';

import {
  BACKGROUND_FETCH_STATUS_AVAILABLE,
  BACKGROUND_FETCH_STATUS_RESTRICTED,
  DEFAULT_MINIMUM_INTERVAL_SECONDS,
  MINIMUM_INTERVAL_PARAMETER,
  OWNER_PARAMETER,
  OWNER_PARAMETER_VALUE,
  SCHEDULER_GENERATION_PARAMETER,
  START_ON_BOOT_PARAMETER,
  STOP_ON_TERMINATE_PARAMETER,
  TASK_NAME_PARAMETER,
  TASK_TYPE,
  WORK_ID_MAXIMUM,
  WORK_ID_MINIMUM,
  WORK_SCHEDULER_CAPABILITY,
  WORK_SCHEDULER_EXTENSION_NAME,
  WORK_SCHEDULER_MINIMUM_INTERVAL_MS,
} from './BackgroundFetchConstants';
import { BackgroundFetchRuntime } from './BackgroundFetchRuntime';
import { stableWorkId, workIdentity } from './BackgroundFetchSemantics.ts';

interface OptionsInput {
  minimumInterval?: ESObject;
  stopOnTerminate?: ESObject;
  startOnBoot?: ESObject;
}

class Options {
  minimumInterval?: number;
  stopOnTerminate?: boolean;
  startOnBoot?: boolean;
}

class ExpoBackgroundFetchError extends ExpoModuleError {
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
    this.name = 'ExpoBackgroundFetchError';
  }
}

class BackgroundFetchConsumer implements ExpoTaskConsumer {
  readonly taskType: string = TASK_TYPE;
  readonly consumerId: string = OWNER_PARAMETER_VALUE;
  readonly consumerVersion: number = 1;
  private mutation: Promise<void> = Promise.resolve();
  private readonly contexts: Map<string, ExpoModuleContext> = new Map();
  private readonly tasks: Map<string, ExpoTaskRecord[]> = new Map();
  private readonly pausedOwners: Set<string> = new Set();

  async onTasksChanged(context: ExpoModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
    const owner = ExpoTaskManagerRegistry.ownerKey(context);
    this.contexts.set(owner, context);
    this.tasks.set(owner, tasks.slice());
    await this.serialize(async (): Promise<void> => {
      await this.reconcile(context, tasks);
    });
  }

  async onExecutionFinished(context: ExpoModuleContext, _results: ExpoTaskExecutionResult[], requestId?: string): Promise<void> {
    await BackgroundFetchRuntime.finish(context.uiAbilityContext, requestId);
  }

  async onExecutionExpired(context: ExpoModuleContext, requestId?: string): Promise<void> {
    await BackgroundFetchRuntime.finish(context.uiAbilityContext, requestId);
  }

  stopOnTerminate(context: ExpoModuleContext): void {
    this.serialize(async (): Promise<void> => {
      const works = await readAllWorks();
      const owned = works.filter((work: workScheduler.WorkInfo): boolean => isOwnedWork(context, work) && stopOnTerminateFromWork(work));

      await cancelWorks(owned, context);
    }).catch((error: Object): void => {
      context.logger.warn(`Unable to stop Expo Background Fetch on termination: ${String(error)}`);
    });
  }

  onForeground(context: ExpoModuleContext): void {
    const owner = ExpoTaskManagerRegistry.ownerKey(context);
    this.pausedOwners.add(owner);
    this.serialize(async (): Promise<void> => {
      const works = await readAllWorks();
      await cancelWorks(
        works.filter((work: workScheduler.WorkInfo): boolean => isOwnedWork(context, work)),
        context,
      );
    }).catch((error: Object): void => {
      context.logger.warn(`Unable to pause Expo Background Fetch in the foreground: ${String(error)}`);
    });
  }

  onBackground(context: ExpoModuleContext): void {
    const owner = ExpoTaskManagerRegistry.ownerKey(context);
    this.pausedOwners.delete(owner);
    const tasks = this.tasks.get(owner) ?? [];
    this.serialize(async (): Promise<void> => this.reconcile(context, tasks)).catch((error: Object): void => {
      context.logger.warn(`Unable to resume Expo Background Fetch in the background: ${String(error)}`);
    });
  }

  private async reconcile(context: ExpoModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
    if (!canIUse(WORK_SCHEDULER_CAPABILITY)) {
      if (tasks.length === 0) {
        await BackgroundFetchRuntime.expireAll(context.uiAbilityContext);
        return;
      }

      requireAvailable(context);
    }

    const works = await readAllWorks();
    const owned = works.filter((work: workScheduler.WorkInfo): boolean => isOwnedWork(context, work));

    if (this.pausedOwners.has(ExpoTaskManagerRegistry.ownerKey(context))) {
      await cancelWorks(owned, context);
      return;
    }

    if (tasks.length === 0) {
      await cancelWorks(owned, context);
      await BackgroundFetchRuntime.expireAll(context.uiAbilityContext);
      return;
    }

    requireAvailable(context);
    requireConfigured();

    const reserved = works.slice();
    const desiredNames = new Set<string>();

    for (const task of tasks) {
      const name = task.taskName;
      const options = parseOptions(task.options);
      const matching = owned.filter((work: workScheduler.WorkInfo): boolean => taskNameFromWork(work) === name);
      const current = matching.length > 0 ? matching[0] : undefined;

      desiredNames.add(name);

      if (current !== undefined && workMatchesOptions(current, name, options, ExpoTaskManagerRegistry.ownerKey(context))) {
        await cancelWorks(matching.slice(1), context);
        continue;
      }

      const workId = allocateWorkId(reserved, name, ExpoTaskManagerRegistry.ownerKey(context));
      const next = createWorkInfo(context, workId, name, options);

      try {
        workScheduler.startWork(next);
      } catch (error) {
        throw new ExpoBackgroundFetchError(
          'ERR_BACKGROUND_FETCH_SCHEDULER',
          `Unable to schedule task '${name}' with HarmonyOS WorkScheduler: ${String(error)}`,
        );
      }

      reserved.push(next);
      try {
        await cancelWorks(matching, context);
      } catch (error) {
        cancelWorkBestEffort(next, context);
        throw new ExpoBackgroundFetchError(
          'ERR_BACKGROUND_FETCH_SCHEDULER',
          `Unable to replace the previous HarmonyOS work for '${name}': ${String(error)}`,
        );
      }
    }

    const obsolete = owned.filter((work: workScheduler.WorkInfo): boolean => {
      const name = taskNameFromWork(work);

      return name === undefined || !desiredNames.has(name);
    });
    await cancelWorks(obsolete, context);
  }

  private async serialize(action: () => Promise<void>): Promise<void> {
    const next = this.mutation.catch((): void => {}).then(action);

    this.mutation = next.catch((): void => {});
    await next;
  }
}

const consumer = new BackgroundFetchConsumer();
let consumerRegistered: boolean = false;

const BACKGROUND_FETCH_OPTIONS_TYPE: ExpoValueType<Options> = new ExpoValueType<Options>(
  'BackgroundFetch options object',
  (value: ESObject): Options => parseOptions(value),
  (value: Options): ESObject => value,
);

/** ArkTS author implementation of Expo's deprecated BackgroundFetch module. */
export class ExpoBackgroundFetchModule extends ExpoModule {
  private reloading: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
    registerConsumer();
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoBackgroundFetch')
      .asyncFunction('getStatusAsync', ExpoFunction.typed0(async (): Promise<number> => status(this.context)).returns(ExpoValueTypes.number()))
      .asyncFunction(
        'registerTaskAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), BACKGROUND_FETCH_OPTIONS_TYPE, async (taskName: string, options: Options): Promise<void> => {
          requireConfigured();
          requireAvailable(this.context);
          await ExpoTaskManagerRegistry.registerTask(this.context, requireTaskName(taskName), TASK_TYPE, options);
        }),
      )
      .asyncFunction(
        'unregisterTaskAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (taskName: string): Promise<void> => {
          await ExpoTaskManagerRegistry.unregisterTaskForConsumer(this.context, requireTaskName(taskName), TASK_TYPE);
        }),
      )
      .onPrepareForReload(async (): Promise<void> => {
        this.reloading = true;
      })
      .onForeground((): void => consumer.onForeground(this.context))
      .onBackground((): void => consumer.onBackground(this.context))
      .onDestroy((): void => {
        if (!this.reloading) consumer.stopOnTerminate(this.context);
      });
  }
}

function status(context: ExpoModuleContext): number {
  return hasWorkSchedulerExtension() && ExpoTaskManagerRegistry.canEnsureRuntimeForContext(context)
    ? BACKGROUND_FETCH_STATUS_AVAILABLE
    : BACKGROUND_FETCH_STATUS_RESTRICTED;
}

function hasWorkSchedulerExtension(): boolean {
  if (!canIUse(WORK_SCHEDULER_CAPABILITY)) return false;

  try {
    const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE | bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_EXTENSION_ABILITY;
    const info = bundleManager.getBundleInfoForSelfSync(flags);

    return info.hapModulesInfo.some((module: bundleManager.HapModuleInfo): boolean => {
      return module.extensionAbilitiesInfo.some(
        (ability: bundleManager.ExtensionAbilityInfo): boolean =>
          ability.name === WORK_SCHEDULER_EXTENSION_NAME &&
          ability.extensionAbilityType === bundleManager.ExtensionAbilityType.WORK_SCHEDULER &&
          ability.enabled,
      );
    });
  } catch (_) {
    return false;
  }
}

function requireAvailable(context: ExpoModuleContext): void {
  if (status(context) !== BACKGROUND_FETCH_STATUS_AVAILABLE) {
    throw new ExpoBackgroundFetchError(
      'ERR_BACKGROUND_FETCH_UNAVAILABLE',
      'HarmonyOS WorkScheduler or a TaskManager cold-start runtime loader is unavailable.',
    );
  }
}

function requireConfigured(): void {
  if (!hasWorkSchedulerExtension()) {
    throw new ExpoBackgroundFetchError(
      'ERR_BACKGROUND_FETCH_NOT_CONFIGURED',
      `WorkScheduler extension '${WORK_SCHEDULER_EXTENSION_NAME}' is missing. ` +
        'Run Expo prebuild with the @expo-harmony/expo-background-fetch config plugin.',
    );
  }
}

function requireTaskName(value: ESObject): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_TASK_NAME', 'Expo Background Fetch expected a non-empty task name.');
  }
  return value;
}

function parseOptions(value: ESObject): Options {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_OPTIONS', 'Expo Background Fetch options must be an object.');
  }

  const input = value as OptionsInput;
  for (const key of Object.keys(value as Record<string, ESObject>)) {
    if (key !== 'minimumInterval' && key !== 'stopOnTerminate' && key !== 'startOnBoot') {
      throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_OPTIONS', `Unsupported BackgroundFetch option '${key}'.`);
    }
  }
  const options = new Options();

  if (input.minimumInterval !== undefined) {
    if (typeof input.minimumInterval !== 'number' || !Number.isFinite(input.minimumInterval) || input.minimumInterval <= 0) {
      throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_INTERVAL', 'minimumInterval must be a positive finite number of seconds.');
    }
    options.minimumInterval = input.minimumInterval;
  }

  if (input.stopOnTerminate !== undefined) {
    if (typeof input.stopOnTerminate !== 'boolean') {
      throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_STOP_ON_TERMINATE', 'stopOnTerminate must be a boolean.');
    }
    options.stopOnTerminate = input.stopOnTerminate;
  }

  if (input.startOnBoot !== undefined) {
    if (typeof input.startOnBoot !== 'boolean') {
      throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_START_ON_BOOT', 'startOnBoot must be a boolean.');
    }
    options.startOnBoot = input.startOnBoot;
  }

  if (options.startOnBoot === true && options.stopOnTerminate !== false) {
    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_LIFECYCLE_OPTIONS', 'startOnBoot: true requires stopOnTerminate: false on HarmonyOS.');
  }

  return options;
}

function createWorkInfo(context: ExpoModuleContext, workId: number, taskName: string, options: Options): workScheduler.WorkInfo {
  const requested = Math.ceil((options.minimumInterval ?? DEFAULT_MINIMUM_INTERVAL_SECONDS) * 1000);

  if (!Number.isSafeInteger(requested)) {
    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_INTERVAL', 'minimumInterval is too large for HarmonyOS WorkScheduler.');
  }

  const params: Record<string, number | string | boolean> = {};
  params[OWNER_PARAMETER] = OWNER_PARAMETER_VALUE;
  params[TASK_NAME_PARAMETER] = taskName;
  params[SCHEDULER_GENERATION_PARAMETER] = util.generateRandomUUID(true);
  ExpoTaskManagerWorkMetadata.write(params, ExpoTaskManagerRegistry.ownerKey(context));
  params[MINIMUM_INTERVAL_PARAMETER] = options.minimumInterval ?? DEFAULT_MINIMUM_INTERVAL_SECONDS;
  params[STOP_ON_TERMINATE_PARAMETER] = options.stopOnTerminate !== false;
  params[START_ON_BOOT_PARAMETER] = options.startOnBoot === true;

  return {
    workId,
    bundleName: context.uiAbilityContext.abilityInfo.bundleName,
    abilityName: WORK_SCHEDULER_EXTENSION_NAME,
    isPersisted: options.startOnBoot === true,
    networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
    isRepeat: true,
    repeatCycleTime: Math.max(requested, WORK_SCHEDULER_MINIMUM_INTERVAL_MS),
    parameters: params,
  };
}

function workMatchesOptions(work: workScheduler.WorkInfo, taskName: string, options: Options, ownerKey: string): boolean {
  const seconds = options.minimumInterval ?? DEFAULT_MINIMUM_INTERVAL_SECONDS;
  const interval = Math.max(Math.ceil(seconds * 1000), WORK_SCHEDULER_MINIMUM_INTERVAL_MS);
  const params = work.parameters;

  return (
    work.isRepeat === true &&
    work.networkType === workScheduler.NetworkType.NETWORK_TYPE_ANY &&
    work.repeatCycleTime === interval &&
    (work.isPersisted === true) === (options.startOnBoot === true) &&
    params?.[TASK_NAME_PARAMETER] === taskName &&
    ExpoTaskManagerWorkMetadata.owner(params) === ownerKey &&
    typeof params?.[SCHEDULER_GENERATION_PARAMETER] === 'string' &&
    params?.[MINIMUM_INTERVAL_PARAMETER] === seconds &&
    params?.[STOP_ON_TERMINATE_PARAMETER] === (options.stopOnTerminate !== false) &&
    params?.[START_ON_BOOT_PARAMETER] === (options.startOnBoot === true)
  );
}

function isOwnedWork(context: ExpoModuleContext, work: workScheduler.WorkInfo): boolean {
  return (
    work.bundleName === context.uiAbilityContext.abilityInfo.bundleName &&
    work.abilityName === WORK_SCHEDULER_EXTENSION_NAME &&
    work.parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    ExpoTaskManagerWorkMetadata.owner(work.parameters, true) === ExpoTaskManagerRegistry.ownerKey(context)
  );
}

function stopOnTerminateFromWork(work: workScheduler.WorkInfo): boolean {
  return work.parameters?.[STOP_ON_TERMINATE_PARAMETER] !== false;
}

function taskNameFromWork(work: workScheduler.WorkInfo): string | undefined {
  const value = work.parameters?.[TASK_NAME_PARAMETER];

  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

async function readAllWorks(): Promise<workScheduler.WorkInfo[]> {
  try {
    return await workScheduler.obtainAllWorks();
  } catch (error) {
    throw new ExpoBackgroundFetchError(
      'ERR_BACKGROUND_FETCH_SCHEDULER',
      `Unable to query registered tasks with HarmonyOS WorkScheduler: ${String(error)}`,
    );
  }
}

function allocateWorkId(works: workScheduler.WorkInfo[], taskName: string, ownerKey: string): number {
  const ids: Set<number> = new Set(works.map((work: workScheduler.WorkInfo): number => work.workId));
  let id = stableWorkId(workIdentity(`${TASK_TYPE}:${ownerKey}`, taskName), WORK_ID_MINIMUM, WORK_ID_MAXIMUM);
  const initial = id;

  do {
    if (!ids.has(id)) return id;

    id = id === WORK_ID_MAXIMUM ? WORK_ID_MINIMUM : id + 1;
  } while (id !== initial);

  throw new ExpoBackgroundFetchError(
    'ERR_BACKGROUND_FETCH_WORK_ID',
    'HarmonyOS has no available WorkScheduler identifier for Expo Background Fetch.',
  );
}

function cancelWork(work: workScheduler.WorkInfo): void {
  try {
    workScheduler.stopWork(work, true);
  } catch (error) {
    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_SCHEDULER', `Unable to cancel with HarmonyOS WorkScheduler: ${String(error)}`);
  }
}

async function cancelWorks(works: workScheduler.WorkInfo[], context: ExpoModuleContext): Promise<void> {
  let failures = 0;

  for (const work of works) {
    let failed = false;

    try {
      cancelWork(work);
    } catch (error) {
      failed = true;
      context.logger.warn(`Unable to cancel Expo Background Fetch work '${work.workId}': ${String(error)}`);
    }

    try {
      await BackgroundFetchRuntime.expire(context.uiAbilityContext, work);
    } catch (error) {
      failed = true;
      context.logger.warn(`Unable to expire Expo Background Fetch work '${work.workId}': ${String(error)}`);
    }

    if (failed) failures += 1;
  }

  if (failures > 0) {
    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_SCHEDULER', `Unable to cancel ${failures} Expo Background Fetch work(s).`);
  }
}

function cancelWorkBestEffort(work: workScheduler.WorkInfo, context: ExpoModuleContext): void {
  try {
    workScheduler.stopWork(work, true);
  } catch (error) {
    context.logger.error(`Unable to roll back Expo Background Fetch work '${work.workId}': ${String(error)}`);
  }
}

export function registerBackgroundFetchConsumer(): void {
  if (consumerRegistered) return;
  ExpoTaskManagerRegistry.registerConsumer(consumer);
  consumerRegistered = true;
}

function registerConsumer(): void {
  registerBackgroundFetchConsumer();
}
