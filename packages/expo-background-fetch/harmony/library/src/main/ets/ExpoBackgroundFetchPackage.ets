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
import { BackgroundFetchRuntime, BackgroundFetchState } from './BackgroundFetchRuntime';
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

    try {
      BackgroundFetchRuntime.setState(context, owner, state);
    } catch (error) {
      console.warn(`Unable to save Expo Background Fetch lifecycle: ${String(error)}`);
      return;
    }

    ExpoTaskManagerRegistry.withRegisteredTasks(context, owner, TASK_TYPE, async (tasks: ExpoTaskRecord[]): Promise<void> => {
      await this.update(context, tasks);
    }).catch((error: Object): void => {
      console.warn(`Unable to update Expo Background Fetch lifecycle: ${String(error)}`);
    });
  }

  private async update(context: common.UIAbilityContext, tasks: ExpoTaskRecord[]): Promise<void> {
    const expired: workScheduler.WorkInfo[] = [];

    try {
      await BackgroundFetchRuntime.updateSchedule(context, async (): Promise<void> => {
        await this.reconcile(context, tasks, expired);
      });
    } finally {
      for (const work of expired) await BackgroundFetchRuntime.expire(context, work);
    }

    if (tasks.length === 0) await BackgroundFetchRuntime.expireAll(context);
  }

  private async reconcile(context: common.UIAbilityContext, tasks: ExpoTaskRecord[], expired: workScheduler.WorkInfo[]): Promise<void> {
    if (!canIUse(WORK_SCHEDULER_CAPABILITY)) {
      if (tasks.length === 0) return;

      requireAvailable(context);
    }

    const works = await readAllWorks();
    const owned = works.filter((work: workScheduler.WorkInfo): boolean => isOwnedWork(context, work));

    if (tasks.length === 0) {
      cancelWorks(owned, expired);

      return;
    }

    requireAvailable(context);
    requireConfigured();

    const state = await BackgroundFetchRuntime.getState(context, context.abilityInfo.bundleName);

    const reserved = works.slice();
    const names = new Set<string>(tasks.map((task: ExpoTaskRecord): string => task.taskName));
    const matchingByName = new Map<string, workScheduler.WorkInfo[]>();
    const obsolete: workScheduler.WorkInfo[] = [];

    for (const work of owned) {
      const name = taskNameFromWork(work);
      if (name === undefined || !names.has(name)) {
        obsolete.push(work);
        continue;
      }

      const matching = matchingByName.get(name) ?? [];
      matching.push(work);
      matchingByName.set(name, matching);
    }

    cancelWorks(obsolete, expired);

    // Clear duplicates before restoring tasks that need a new scheduler slot.
    const ordered = tasks.slice().sort((left: ExpoTaskRecord, right: ExpoTaskRecord): number =>
      Number(matchingByName.has(right.taskName)) - Number(matchingByName.has(left.taskName)),
    );

    for (const task of ordered) {
      const name = task.taskName;
      const options = parseOptions(task.options);
      const matching = matchingByName.get(name) ?? [];

      const paused =
        (state === BackgroundFetchState.Terminated && options.stopOnTerminate !== false) ||
        (state === BackgroundFetchState.Rebooted && options.startOnBoot !== true);

      if (paused && options.startOnBoot !== true) {
        cancelWorks(matching, expired);

        continue;
      }

      const current = matching.find(
        (work: workScheduler.WorkInfo): boolean => workMatchesOptions(work, task, options, context.abilityInfo.bundleName),
      );
      if (current !== undefined) {
        cancelWorks(matching.filter((work: workScheduler.WorkInfo): boolean => work.workId !== current.workId), expired);

        continue;
      }

      const id = matching[0]?.workId ?? allocateWorkId(reserved, name, context.abilityInfo.bundleName);
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
      const paused = (await readAllWorks()).filter(
        (work: workScheduler.WorkInfo): boolean =>
          isOwnedWork(context, work) && (state === BackgroundFetchState.Foreground || stopOnTerminateFromWork(work)),
      );

      pauseWorks(paused, expired);
    }
  }
}

const consumer = new BackgroundFetchConsumer();

const BACKGROUND_FETCH_OPTIONS_TYPE: ExpoValueType<Options> = new ExpoValueType<Options>(
  'BackgroundFetch options object',
  (value: ESObject): Options => parseOptions(value),
  (value: Options): ESObject => value,
);

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
        ExpoFunction.typed2(ExpoValueTypes.string(), BACKGROUND_FETCH_OPTIONS_TYPE, async (name: string, options: Options): Promise<void> => {
          requireConfigured();
          requireAvailable(this.context.uiAbilityContext);
          if (options.minimumInterval !== undefined && options.minimumInterval > WORK_SCHEDULER_MAXIMUM_INTERVAL_MS / 1000) {
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
  return hasWorkSchedulerExtension() && ExpoTaskManagerRegistry.hasRuntimeLoader(context.abilityInfo.bundleName)
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

function requireAvailable(context: common.UIAbilityContext): void {
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

  return options;
}

function createWorkInfo(context: common.UIAbilityContext, id: number, task: ExpoTaskRecord, options: Options): workScheduler.WorkInfo {
  const params: Record<string, number | string | boolean> = {};

  params[OWNER_PARAMETER] = OWNER_PARAMETER_VALUE;
  params[TASK_NAME_PARAMETER] = task.taskName;
  params[REGISTRATION_GENERATION_PARAMETER] = task.registrationGeneration;
  params[SCHEDULER_GENERATION_PARAMETER] = util.generateRandomUUID(true);
  ExpoTaskManagerWorkMetadata.write(params, context.abilityInfo.bundleName);
  params[MINIMUM_INTERVAL_PARAMETER] = options.minimumInterval ?? DEFAULT_MINIMUM_INTERVAL_SECONDS;
  params[STOP_ON_TERMINATE_PARAMETER] = options.stopOnTerminate !== false;
  params[START_ON_BOOT_PARAMETER] = options.startOnBoot === true;

  return {
    workId: id,
    bundleName: context.abilityInfo.bundleName,
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
  const params = work.parameters;

  return (
    work.isRepeat === true &&
    work.networkType === undefined &&
    work.repeatCycleTime === schedulerInterval(seconds) &&
    (work.isPersisted === true) === (options.startOnBoot === true) &&
    params?.[TASK_NAME_PARAMETER] === task.taskName &&
    params?.[REGISTRATION_GENERATION_PARAMETER] === task.registrationGeneration &&
    ExpoTaskManagerWorkMetadata.owner(params) === owner &&
    typeof params?.[SCHEDULER_GENERATION_PARAMETER] === 'string' &&
    params?.[MINIMUM_INTERVAL_PARAMETER] === seconds &&
    params?.[STOP_ON_TERMINATE_PARAMETER] === (options.stopOnTerminate !== false) &&
    params?.[START_ON_BOOT_PARAMETER] === (options.startOnBoot === true)
  );
}

function isOwnedWork(context: common.UIAbilityContext, work: workScheduler.WorkInfo): boolean {
  return (
    work.bundleName === context.abilityInfo.bundleName &&
    work.abilityName === WORK_SCHEDULER_EXTENSION_NAME &&
    work.parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    ExpoTaskManagerWorkMetadata.owner(work.parameters, true) === context.abilityInfo.bundleName
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

function pauseWorks(works: workScheduler.WorkInfo[], expired: workScheduler.WorkInfo[]): void {
  for (const work of works) {
    workScheduler.stopWork(work, false);
    expired.push(work);
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
