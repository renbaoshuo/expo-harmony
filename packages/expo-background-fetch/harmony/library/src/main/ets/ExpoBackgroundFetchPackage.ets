import { workScheduler } from '@kit.BackgroundTasksKit';
import { bundleManager } from '@kit.AbilityKit';
import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import type { ExpoPlatformServiceFactory } from '@expo-harmony/expo-modules-core';
import { ExpoTaskConsumer, ExpoTaskExecutionResult, ExpoTaskManagerRegistry, ExpoTaskRecord } from '@expo-harmony/expo-task-manager';

import {
  BACKGROUND_FETCH_SERVICE_NAME,
  BACKGROUND_FETCH_STATUS_AVAILABLE,
  BACKGROUND_FETCH_STATUS_RESTRICTED,
  DEFAULT_MINIMUM_INTERVAL_SECONDS,
  MINIMUM_INTERVAL_PARAMETER,
  OWNER_PARAMETER,
  OWNER_PARAMETER_VALUE,
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

class ExpoBackgroundFetchError extends ExpoPlatformServiceError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoBackgroundFetchError';
  }
}

class BackgroundFetchConsumer implements ExpoTaskConsumer {
  readonly taskType: string = TASK_TYPE;
  private mutation: Promise<void> = Promise.resolve();

  async onTasksChanged(context: UITurboModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      await this.reconcile(context, tasks);
    });
  }

  async onExecutionFinished(context: UITurboModuleContext, _results: ExpoTaskExecutionResult[], requestId?: string): Promise<void> {
    await BackgroundFetchRuntime.finish(context.uiAbilityContext, requestId);
  }

  async onExecutionExpired(context: UITurboModuleContext, requestId?: string): Promise<void> {
    await BackgroundFetchRuntime.finish(context.uiAbilityContext, requestId);
  }

  stopOnTerminate(context: UITurboModuleContext): void {
    this.serialize(async (): Promise<void> => {
      const works = await readAllWorks();
      const owned = works.filter((work: workScheduler.WorkInfo): boolean => isOwnedWork(context, work) && stopOnTerminateFromWork(work));

      await cancelWorks(owned, context);
    }).catch((error: Object): void => {
      context.logger.warn(`Unable to stop Expo Background Fetch on termination: ${String(error)}`);
    });
  }

  private async reconcile(context: UITurboModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
    if (!canIUse(WORK_SCHEDULER_CAPABILITY)) {
      if (tasks.length === 0) {
        await BackgroundFetchRuntime.expireAll(context.uiAbilityContext);
        return;
      }

      requireAvailable();
    }

    const works = await readAllWorks();
    const owned = works.filter((work: workScheduler.WorkInfo): boolean => isOwnedWork(context, work));

    if (tasks.length === 0) {
      await cancelWorks(owned, context);
      await BackgroundFetchRuntime.expireAll(context.uiAbilityContext);
      return;
    }

    requireAvailable();

    const reserved = works.slice();
    const desiredNames = new Set<string>();

    for (const task of tasks) {
      const name = task.taskName;
      const options = parseOptions(task.options);
      const matching = owned.filter((work: workScheduler.WorkInfo): boolean => taskNameFromWork(work) === name);
      const current = matching.length > 0 ? matching[0] : undefined;

      desiredNames.add(name);

      if (current !== undefined && workMatchesOptions(current, name, options)) {
        await cancelWorks(matching.slice(1), context);
        continue;
      }

      const workId = current?.workId ?? allocateWorkId(reserved, name);
      const next = createWorkInfo(context, workId, name, options);

      if (current !== undefined) cancelWork(current);

      try {
        workScheduler.startWork(next);
      } catch (error) {
        if (current !== undefined) restoreWorkBestEffort(current, context);

        throw new ExpoBackgroundFetchError(
          'ERR_BACKGROUND_FETCH_SCHEDULER',
          `Unable to schedule task '${name}' with HarmonyOS WorkScheduler: ${String(error)}`,
        );
      }

      reserved.push(next);
      await cancelWorks(matching.slice(1), context);
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

class BackgroundFetchService {
  readonly name: string = BACKGROUND_FETCH_SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private reloading: boolean = false;

  constructor(context: UITurboModuleContext) {
    this.context = context;
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'getStatusAsync') return status();

    if (method === 'registerTaskAsync') {
      const name = requireTaskName(args[0]);
      const options = parseOptions(args[1]);

      await ExpoTaskManagerRegistry.registerTask(this.context, name, TASK_TYPE, options);

      return null;
    }

    if (method === 'unregisterTaskAsync') {
      const name = requireTaskName(args[0]);

      await ExpoTaskManagerRegistry.unregisterTaskForConsumer(this.context, name, TASK_TYPE);

      return null;
    }

    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_UNKNOWN_METHOD', `Unknown Expo Background Fetch Harmony method '${method}'.`);
  }

  prepareForReload(): void {
    this.reloading = true;
  }

  onDestroy(): void {
    if (!this.reloading) consumer.stopOnTerminate(this.context);
  }
}

function status(): number {
  return hasWorkSchedulerExtension() ? BACKGROUND_FETCH_STATUS_AVAILABLE : BACKGROUND_FETCH_STATUS_RESTRICTED;
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

function requireAvailable(): void {
  if (status() !== BACKGROUND_FETCH_STATUS_AVAILABLE) {
    throw new ExpoBackgroundFetchError(
      'ERR_BACKGROUND_FETCH_UNAVAILABLE',
      `HarmonyOS WorkScheduler or extension '${WORK_SCHEDULER_EXTENSION_NAME}' is unavailable. ` +
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

function createWorkInfo(context: UITurboModuleContext, workId: number, taskName: string, options: Options): workScheduler.WorkInfo {
  const requested = Math.ceil((options.minimumInterval ?? DEFAULT_MINIMUM_INTERVAL_SECONDS) * 1000);

  if (!Number.isSafeInteger(requested)) {
    throw new ExpoBackgroundFetchError('ERR_BACKGROUND_FETCH_INTERVAL', 'minimumInterval is too large for HarmonyOS WorkScheduler.');
  }

  const params: Record<string, number | string | boolean> = {};
  params[OWNER_PARAMETER] = OWNER_PARAMETER_VALUE;
  params[TASK_NAME_PARAMETER] = taskName;
  params[MINIMUM_INTERVAL_PARAMETER] = options.minimumInterval ?? DEFAULT_MINIMUM_INTERVAL_SECONDS;
  params[STOP_ON_TERMINATE_PARAMETER] = options.stopOnTerminate !== false;
  params[START_ON_BOOT_PARAMETER] = options.startOnBoot === true;

  return {
    workId,
    bundleName: context.uiAbilityContext.abilityInfo.bundleName,
    abilityName: WORK_SCHEDULER_EXTENSION_NAME,
    isPersisted: options.startOnBoot === true,
    batteryStatus: workScheduler.BatteryStatus.BATTERY_STATUS_LOW_OR_OKAY,
    isRepeat: true,
    repeatCycleTime: Math.max(requested, WORK_SCHEDULER_MINIMUM_INTERVAL_MS),
    parameters: params,
  };
}

function workMatchesOptions(work: workScheduler.WorkInfo, taskName: string, options: Options): boolean {
  const seconds = options.minimumInterval ?? DEFAULT_MINIMUM_INTERVAL_SECONDS;
  const interval = Math.max(Math.ceil(seconds * 1000), WORK_SCHEDULER_MINIMUM_INTERVAL_MS);
  const params = work.parameters;

  return (
    work.isRepeat === true &&
    work.repeatCycleTime === interval &&
    (work.isPersisted === true) === (options.startOnBoot === true) &&
    params?.[TASK_NAME_PARAMETER] === taskName &&
    params?.[MINIMUM_INTERVAL_PARAMETER] === seconds &&
    params?.[STOP_ON_TERMINATE_PARAMETER] === (options.stopOnTerminate !== false) &&
    params?.[START_ON_BOOT_PARAMETER] === (options.startOnBoot === true)
  );
}

function isOwnedWork(context: UITurboModuleContext, work: workScheduler.WorkInfo): boolean {
  return (
    work.bundleName === context.uiAbilityContext.abilityInfo.bundleName &&
    work.abilityName === WORK_SCHEDULER_EXTENSION_NAME &&
    work.parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE
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

function allocateWorkId(works: workScheduler.WorkInfo[], taskName: string): number {
  const ids: Set<number> = new Set(works.map((work: workScheduler.WorkInfo): number => work.workId));
  let id = stableWorkId(workIdentity(TASK_TYPE, taskName), WORK_ID_MINIMUM, WORK_ID_MAXIMUM);
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

async function cancelWorks(works: workScheduler.WorkInfo[], context: UITurboModuleContext): Promise<void> {
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

function restoreWorkBestEffort(work: workScheduler.WorkInfo, context: UITurboModuleContext): void {
  try {
    workScheduler.startWork(work);
  } catch (error) {
    context.logger.error(`Unable to restore Expo Background Fetch after an update failed: ${String(error)}`);
  }
}

class BackgroundFetchServiceFactory implements ExpoPlatformServiceFactory {
  readonly name: string = BACKGROUND_FETCH_SERVICE_NAME;

  create(context: UITurboModuleContext): BackgroundFetchService {
    return new BackgroundFetchService(context);
  }
}

let registered: boolean = false;

function registerPackage(): void {
  if (registered) return;

  ExpoTaskManagerRegistry.registerConsumer(consumer);
  ExpoPlatformServiceRegistry.register(new BackgroundFetchServiceFactory());

  registered = true;
}

export class ExpoBackgroundFetchPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerPackage();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-background-fetch';
  }
}
