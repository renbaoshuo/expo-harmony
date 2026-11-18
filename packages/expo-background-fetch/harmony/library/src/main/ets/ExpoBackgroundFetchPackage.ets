/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { workScheduler } from '@kit.BackgroundTasksKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  ExpoAppLifecycleSubscriber,
  ExpoAbilityLifecycleSubscriber,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
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
  OWNER_PARAMETER,
  OWNER_PARAMETER_VALUE,
  SCHEDULER_GENERATION_PARAMETER,
  REGISTRATION_GENERATION_PARAMETER,
  START_ON_BOOT_PARAMETER,
  STOP_ON_TERMINATE_PARAMETER,
  TASK_NAME_PARAMETER,
  TASK_TYPE,
  WORK_ID_MAXIMUM,
  WORK_ID_MINIMUM,
  WORK_SCHEDULER_CAPABILITY,
  WORK_SCHEDULER_EXTENSION_NAME,
  WORK_SCHEDULER_MAXIMUM_INTERVAL_MS,
  WORK_SCHEDULER_MINIMUM_INTERVAL_MS,
} from './BackgroundFetchConstants';
import {
  BackgroundFetchRuntime,
  BackgroundFetchState,
  isOwnedWork,
  registrationGenerationFromWork,
  schedulerGenerationFromWork,
  startOnBootFromWork,
  stopOnTerminateFromWork,
  taskNameFromWork,
} from './BackgroundFetchRuntime';
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

  async onTasksChanged(context: ExpoModuleContext, tasks: ExpoTaskRecord[], restoring: boolean = false): Promise<void> {
    // Restoring the runtime must not replace the running work that started it.
    if (context.isHeadless && restoring) return;

    await this.update(context.uiAbilityContext, tasks);
  }

  async onExecutionFinished(context: ExpoModuleContext, _results: ExpoTaskExecutionResult[], requestId?: string): Promise<void> {
    await BackgroundFetchRuntime.finish(context.uiAbilityContext, requestId);
  }

  async onExecutionExpired(context: ExpoModuleContext, requestId?: string): Promise<void> {
    await BackgroundFetchRuntime.finish(context.uiAbilityContext, requestId);
  }

  updateLifecycle(context: common.UIAbilityContext, state: BackgroundFetchState): void {
    const owner = context.abilityInfo.bundleName;

    BackgroundFetchRuntime.setState(context, owner, state)
      .then((): Promise<void> =>
        ExpoTaskManagerRegistry.withRegisteredTasks(context, owner, TASK_TYPE, (tasks: ExpoTaskRecord[]): Promise<void> =>
          this.update(context, tasks),
        ),
      )
      .catch((error: Object): void => {
        console.warn(`Unable to update Expo Background Fetch lifecycle: ${String(error)}`);
      });
  }

  private async update(context: common.UIAbilityContext, tasks: ExpoTaskRecord[]): Promise<void> {
    await BackgroundFetchRuntime.updateSchedule(context, tasks.length === 0, (expired: workScheduler.WorkInfo[]): Promise<void> =>
      this.reconcile(context, tasks, expired),
    );
  }

  private async reconcile(context: common.UIAbilityContext, tasks: ExpoTaskRecord[], expired: workScheduler.WorkInfo[]): Promise<void> {
    if (!canIUse(WORK_SCHEDULER_CAPABILITY)) {
      if (tasks.length === 0) return;

      requireAvailable(context);
    }

    const works = await readAllWorks();
    const owner = context.abilityInfo.bundleName;
    const owned = works.filter((work: workScheduler.WorkInfo): boolean => isOwnedWork(work, owner));

    if (tasks.length === 0) {
      cancelWorks(owned, expired);

      return;
    }

    requireAvailable(context);

    const state = await BackgroundFetchRuntime.getState(context, owner);

    const reserved = works.slice();
    const names = new Set<string>(tasks.map((task: ExpoTaskRecord): string => task.taskName));
    const matches = new Map<string, workScheduler.WorkInfo[]>();
    const obsolete: workScheduler.WorkInfo[] = [];

    for (const work of owned) {
      const name = taskNameFromWork(work);
      if (name === undefined || !names.has(name)) {
        obsolete.push(work);
        continue;
      }

      const matching = matches.get(name) ?? [];
      matching.push(work);
      matches.set(name, matching);
    }

    cancelWorks(obsolete, expired);

    // Clear duplicates before restoring tasks that need a new scheduler slot.
    const ordered = tasks.slice().sort((left: ExpoTaskRecord, right: ExpoTaskRecord): number =>
      Number(matches.has(right.taskName)) - Number(matches.has(left.taskName)),
    );

    for (const task of ordered) {
      const name = task.taskName;
      const options = parseOptions(task.options);
      const matching = matches.get(name) ?? [];

      const paused =
        (state === BackgroundFetchState.Terminated && options.stopOnTerminate !== false) ||
        (state === BackgroundFetchState.Rebooted && options.startOnBoot !== true);

      if (paused && options.startOnBoot !== true) {
        cancelWorks(matching, expired);

        continue;
      }

      const current = matching.find(
        (work: workScheduler.WorkInfo): boolean => workMatchesOptions(work, task, options, owner),
      );

      if (current !== undefined) {
        cancelWorks(matching.filter((work: workScheduler.WorkInfo): boolean => work.workId !== current.workId), expired);

        continue;
      }

      const id = matching[0]?.workId ?? allocateWorkId(reserved, name, owner);
      const next = createWorkInfo(context, id, task, options);

      // Replacing a task must not require an extra WorkScheduler slot when the app is at its quota.
      cancelWorks(matching, expired);

      try {
        workScheduler.startWork(next);
      } catch (error) {
        for (const previous of matching) {
          try {
            workScheduler.startWork(previous);
          } catch (rollback) {
            console.error(`Unable to restore Expo Background Fetch work '${previous.workId}': ${String(rollback)}`);
          }
        }

        throw new ExpoBackgroundFetchError(
          'ERR_BACKGROUND_FETCH_SCHEDULER',
          `Unable to schedule task '${name}' with HarmonyOS WorkScheduler: ${String(error)}`,
        );
      }

      reserved.push(next);
    }

    if (state === BackgroundFetchState.Foreground || state === BackgroundFetchState.Terminated) {
      // stopWork(false) ends a current invocation. The periodic registration must survive
      // the foreground transition and, for persisted work, this process's termination.
      const paused = reserved.filter(
        (work: workScheduler.WorkInfo): boolean =>
          isOwnedWork(work, owner) && (state === BackgroundFetchState.Foreground || stopOnTerminateFromWork(work)),
      );

      expired.push(...paused);
    }
  }
}

const consumer = new BackgroundFetchConsumer();

export class ExpoBackgroundFetchModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoBackgroundFetch')
      .asyncFunction(
        'getStatusAsync',
        ExpoFunction.typed0(async (): Promise<number> => status(this.context.uiAbilityContext)).returns(ExpoValueTypes.number()),
      )
      .asyncFunction(
        'registerTaskAsync',
        ExpoFunction.typed2(ExpoValueTypes.string(), ExpoValueTypes.any(), async (name: string, options: ESObject): Promise<void> => {
          requireAvailable(this.context.uiAbilityContext);
          const minimumInterval = parseOptions(options).minimumInterval;
          if (minimumInterval !== undefined && minimumInterval > WORK_SCHEDULER_MAXIMUM_INTERVAL_MS / 1000) {
            throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_INTERVAL', 'minimumInterval is too large for HarmonyOS WorkScheduler.');
          }

          await ExpoTaskManagerRegistry.registerTask(this.context, requireTaskName(name), TASK_TYPE, options);
        }),
      )
      .asyncFunction(
        'unregisterTaskAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (name: string): Promise<void> => {
          await ExpoTaskManagerRegistry.unregisterTaskForConsumer(this.context, requireTaskName(name), TASK_TYPE);
        }),
      );
  }
}

function status(context: common.UIAbilityContext): number {
  return canIUse(WORK_SCHEDULER_CAPABILITY) && hasWorkSchedulerExtension() &&
    ExpoTaskManagerRegistry.hasRuntimeLoader(context.abilityInfo.bundleName)
    ? BACKGROUND_FETCH_STATUS_AVAILABLE
    : BACKGROUND_FETCH_STATUS_RESTRICTED;
}

function hasWorkSchedulerExtension(): boolean {
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

function requireAvailable(context: common.UIAbilityContext): void {
  if (!canIUse(WORK_SCHEDULER_CAPABILITY)) {
    throw new ExpoBackgroundFetchError(
      'ERR_BACKGROUND_FETCH_UNAVAILABLE',
      'HarmonyOS WorkScheduler is unavailable on this device.',
    );
  }

  if (!hasWorkSchedulerExtension()) {
    throw new ExpoBackgroundFetchError(
      'ERR_BACKGROUND_FETCH_NOT_CONFIGURED',
      `WorkScheduler extension '${WORK_SCHEDULER_EXTENSION_NAME}' is missing. ` +
        'Run Expo prebuild with the @expo-harmony/expo-background-fetch config plugin.',
    );
  }
  if (!ExpoTaskManagerRegistry.hasRuntimeLoader(context.abilityInfo.bundleName)) {
    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_UNAVAILABLE', 'A TaskManager cold-start runtime loader is unavailable.');
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
  const options = new Options();

  if (input.minimumInterval !== undefined) {
    if (typeof input.minimumInterval !== 'number' || !Number.isFinite(input.minimumInterval) || input.minimumInterval < 0) {
      throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_INTERVAL', 'minimumInterval must be a non-negative finite number of seconds.');
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

  return options;
}

function createWorkInfo(context: common.UIAbilityContext, id: number, task: ExpoTaskRecord, options: Options): workScheduler.WorkInfo {
  const bundle = context.abilityInfo.bundleName;
  const params: Record<string, number | string | boolean> = {};

  params[OWNER_PARAMETER] = OWNER_PARAMETER_VALUE;
  params[TASK_NAME_PARAMETER] = task.taskName;
  params[REGISTRATION_GENERATION_PARAMETER] = String(task.registrationGeneration);
  params[SCHEDULER_GENERATION_PARAMETER] = util.generateRandomUUID(true);
  ExpoTaskManagerWorkMetadata.write(params, bundle);
  params[STOP_ON_TERMINATE_PARAMETER] = options.stopOnTerminate !== false;
  params[START_ON_BOOT_PARAMETER] = options.startOnBoot === true;

  return {
    workId: id,
    bundleName: bundle,
    abilityName: WORK_SCHEDULER_EXTENSION_NAME,
    isPersisted: options.startOnBoot === true,
    isRepeat: true,
    repeatCycleTime: schedulerInterval(options.minimumInterval ?? DEFAULT_MINIMUM_INTERVAL_SECONDS),
    parameters: params,
  };
}

function schedulerInterval(seconds: number): number {
  // An existing registration can have been saved while its work was paused.
  return Math.min(WORK_SCHEDULER_MAXIMUM_INTERVAL_MS, Math.max(Math.ceil(seconds * 1000), WORK_SCHEDULER_MINIMUM_INTERVAL_MS));
}

function workMatchesOptions(work: workScheduler.WorkInfo, task: ExpoTaskRecord, options: Options, owner: string): boolean {
  const seconds = options.minimumInterval ?? DEFAULT_MINIMUM_INTERVAL_SECONDS;
  return (
    work.isRepeat === true &&
    work.networkType === undefined &&
    work.repeatCycleTime === schedulerInterval(seconds) &&
    (work.isPersisted === true) === (options.startOnBoot === true) &&
    taskNameFromWork(work) === task.taskName &&
    registrationGenerationFromWork(work) === task.registrationGeneration &&
    ExpoTaskManagerWorkMetadata.owner(ExpoTaskManagerWorkMetadata.parameters(work.parameters)) === owner &&
    schedulerGenerationFromWork(work).length > 0 &&
    stopOnTerminateFromWork(work) === (options.stopOnTerminate !== false) &&
    startOnBootFromWork(work) === (options.startOnBoot === true)
  );
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

function allocateWorkId(works: workScheduler.WorkInfo[], name: string, owner: string): number {
  const ids: Set<number> = new Set(works.map((work: workScheduler.WorkInfo): number => work.workId));
  let id = stableWorkId(workIdentity(`${TASK_TYPE}:${owner}`, name), WORK_ID_MINIMUM, WORK_ID_MAXIMUM);
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

function cancelWorks(works: workScheduler.WorkInfo[], expired: workScheduler.WorkInfo[]): void {
  let failures = 0;

  for (const work of works) {
    try {
      cancelWork(work);
      expired.push(work);
    } catch (error) {
      failures += 1;
      console.warn(`Unable to cancel Expo Background Fetch work '${work.workId}': ${String(error)}`);
    }
  }

  if (failures > 0) {
    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_SCHEDULER', `Unable to cancel ${failures} Expo Background Fetch work(s).`);
  }
}

export class ExpoBackgroundFetchLifecycleSubscriber extends ExpoAppLifecycleSubscriber {
  override onCreate(): void {
    ExpoTaskManagerRegistry.registerConsumer(consumer);
  }
}

export class ExpoBackgroundFetchAbilityLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  private static readonly abilities: Set<common.UIAbilityContext> = new Set();
  private static readonly foreground: Set<common.UIAbilityContext> = new Set();

  override onCreate(): void {
    ExpoBackgroundFetchAbilityLifecycleSubscriber.abilities.add(this.context);
    this.update();
  }

  override onForeground(): void {
    ExpoBackgroundFetchAbilityLifecycleSubscriber.foreground.add(this.context);
    this.update();
  }

  override onBackground(): void {
    ExpoBackgroundFetchAbilityLifecycleSubscriber.foreground.delete(this.context);
    this.update();
  }

  override onDestroy(): void {
    ExpoBackgroundFetchAbilityLifecycleSubscriber.abilities.delete(this.context);
    ExpoBackgroundFetchAbilityLifecycleSubscriber.foreground.delete(this.context);
    this.update();
  }

  private update(): void {
    const foreground = ExpoBackgroundFetchAbilityLifecycleSubscriber.foreground;
    const abilities = ExpoBackgroundFetchAbilityLifecycleSubscriber.abilities;
    const state =
      abilities.size === 0
        ? BackgroundFetchState.Terminated
        : foreground.size > 0
          ? BackgroundFetchState.Foreground
          : BackgroundFetchState.Background;

    consumer.updateLifecycle(this.context, state);
  }
}
