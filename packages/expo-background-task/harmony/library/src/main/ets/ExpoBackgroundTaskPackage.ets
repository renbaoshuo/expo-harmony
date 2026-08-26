import { bundleManager } from '@kit.AbilityKit';
import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { EXPO_MODULE_EVENT, ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import type { ExpoPlatformServiceFactory } from '@expo-harmony/expo-modules-core';
import { ExpoTaskConsumer, ExpoTaskExecutionResult, ExpoTaskManagerRegistry, ExpoTaskRecord } from '@expo-harmony/expo-task-manager';

import {
  BACKGROUND_TASK_MODULE_NAME,
  BACKGROUND_TASK_SERVICE_NAME,
  BACKGROUND_TASK_STATUS_AVAILABLE,
  BACKGROUND_TASK_STATUS_RESTRICTED,
  BACKGROUND_TASK_TYPE,
  EXPO_DEFAULT_INTERVAL_MS,
  EXPIRATION_EVENT_NAME,
  FNV_OFFSET_BASIS,
  FNV_PRIME,
  MILLISECONDS_PER_MINUTE,
  OWNER_PARAMETER,
  OWNER_PARAMETER_VALUE,
  TASK_MANAGER_OWNER_PARAMETER,
  WORK_ID_MAXIMUM,
  WORK_ID_MINIMUM,
  WORK_SCHEDULER_CAPABILITY,
  WORK_SCHEDULER_EXTENSION_NAME,
  WORK_SCHEDULER_MINIMUM_INTERVAL_MS,
} from './BackgroundTaskConstants';
import { BackgroundTaskRuntime } from './BackgroundTaskRuntime';

let packageRegistered: boolean = false;

interface BackgroundTaskOptionsInput {
  minimumInterval?: ESObject;
}

class EmptyEventPayload {}

class BackgroundTaskEventMessage {
  moduleName: string = BACKGROUND_TASK_MODULE_NAME;
  eventName: string = EXPIRATION_EVENT_NAME;
  arguments: ESObject[] = [new EmptyEventPayload()];
}

class ExpoBackgroundTaskError extends ExpoPlatformServiceError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoBackgroundTaskError';
  }
}

class ExpoBackgroundTaskConsumer implements ExpoTaskConsumer {
  readonly taskType: string = BACKGROUND_TASK_TYPE;
  readonly consumerId: string = '@expo-harmony/expo-background-task';
  readonly consumerVersion: number = 1;
  private mutation: Promise<void> = Promise.resolve();

  async onTasksChanged(context: UITurboModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      await this.reconcile(context, tasks);
    });
  }

  async onExecutionFinished(context: UITurboModuleContext, _results: ExpoTaskExecutionResult[], requestId?: string): Promise<void> {
    await BackgroundTaskRuntime.finish(context.uiAbilityContext, ExpoTaskManagerRegistry.ownerKey(context), requestId);
  }

  async onExecutionExpired(context: UITurboModuleContext, requestId?: string): Promise<void> {
    try {
      context.rnInstance.postMessageToCpp(EXPO_MODULE_EVENT, new BackgroundTaskEventMessage());
    } finally {
      await BackgroundTaskRuntime.expire(context.uiAbilityContext, ExpoTaskManagerRegistry.ownerKey(context), requestId);
    }
  }

  private async reconcile(context: UITurboModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
    if (!canIUse(WORK_SCHEDULER_CAPABILITY)) {
      if (tasks.length === 0) return;

      throw new ExpoBackgroundTaskError(
        'ERR_BACKGROUND_TASK_NOT_CONFIGURED',
        `HarmonyOS WorkScheduler or extension '${WORK_SCHEDULER_EXTENSION_NAME}' is unavailable. ` +
          'Run Expo prebuild with the @expo-harmony/expo-background-task config plugin.',
      );
    }

    const works = await readAllWorks();
    const owned = works.filter((work: workScheduler.WorkInfo): boolean => isOwnedWork(context, work));

    if (tasks.length === 0) {
      owned.forEach((work: workScheduler.WorkInfo): void => cancelWork(work));
      return;
    }

    if (!hasWorkSchedulerExtension()) {
      throw new ExpoBackgroundTaskError(
        'ERR_BACKGROUND_TASK_NOT_CONFIGURED',
        `HarmonyOS WorkScheduler or extension '${WORK_SCHEDULER_EXTENSION_NAME}' is unavailable. ` +
          'Run Expo prebuild with the @expo-harmony/expo-background-task config plugin.',
      );
    }

    const interval = intervalForTasks(tasks);
    const current = owned.length > 0 ? owned[0] : undefined;
    if (current !== undefined && workMatchesInterval(current, interval, ExpoTaskManagerRegistry.ownerKey(context))) {
      for (let i = 1; i < owned.length; ++i) {
        cancelWorkBestEffort(owned[i], context);
      }
      return;
    }

    const id = allocateWorkId(context, works);
    const next = createWorkInfo(context, id, interval);
    if (current !== undefined) cancelWork(current);

    try {
      workScheduler.startWork(next);
    } catch (error) {
      if (current !== undefined) restoreWorkBestEffort(current, context);

      throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_SCHEDULER', `Unable to schedule with HarmonyOS WorkScheduler: ${String(error)}`);
    }

    for (let i = 1; i < owned.length; ++i) {
      cancelWorkBestEffort(owned[i], context);
    }
  }

  private async serialize(operation: () => Promise<void>): Promise<void> {
    const next = this.mutation.catch((): void => {}).then(operation);
    this.mutation = next.catch((): void => {});
    await next;
  }
}

const backgroundTaskConsumer = new ExpoBackgroundTaskConsumer();

export class ExpoBackgroundTaskWorkSchedulerExtension extends WorkSchedulerExtensionAbility {
  private readonly requests: Map<number, Promise<string | undefined>[]> = new Map();

  override onWorkStart(work: workScheduler.WorkInfo): void {
    const request = BackgroundTaskRuntime.start(
      this.context,
      work,
      this.context.extensionAbilityInfo.bundleName,
      this.context.extensionAbilityInfo.name,
    );
    const requests = this.requests.get(work.workId) ?? [];

    requests.push(request);
    this.requests.set(work.workId, requests);
  }

  override onWorkStop(work: workScheduler.WorkInfo): void {
    const requests = this.requests.get(work.workId);
    const request = requests?.shift();

    if (requests !== undefined && requests.length === 0) this.requests.delete(work.workId);

    BackgroundTaskRuntime.stop(this.context, work, this.context.extensionAbilityInfo.bundleName, this.context.extensionAbilityInfo.name, request);
  }
}

class ExpoBackgroundTaskService {
  readonly name: string = BACKGROUND_TASK_SERVICE_NAME;
  private readonly context: UITurboModuleContext;

  constructor(context: UITurboModuleContext) {
    this.context = context;
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'getStatusAsync') return status();
    if (method === 'registerTaskAsync') {
      requireAvailable();

      const taskName = requireTaskName(args[0]);
      const options: ESObject = requireOptions(args[1]);
      minimumIntervalMilliseconds(options);

      await ExpoTaskManagerRegistry.registerTask(this.context, taskName, BACKGROUND_TASK_TYPE, options);

      return null;
    }
    if (method === 'unregisterTaskAsync') {
      const taskName = requireTaskName(args[0]);

      await ExpoTaskManagerRegistry.unregisterTaskForConsumer(this.context, taskName, BACKGROUND_TASK_TYPE);

      return null;
    }
    if (method === 'triggerTaskWorkerForTestingAsync') {
      if (!this.context.uiAbilityContext.applicationInfo.debug) {
        throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_TEST_UNAVAILABLE', 'Background tasks cannot be triggered in production builds.');
      }

      await ExpoTaskManagerRegistry.executeTaskType(this.context, BACKGROUND_TASK_TYPE, true);

      return true;
    }

    throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_UNKNOWN_METHOD', `Unknown Expo BackgroundTask Harmony method '${method}'.`);
  }
}

function status(): number {
  return hasWorkSchedulerExtension() ? BACKGROUND_TASK_STATUS_AVAILABLE : BACKGROUND_TASK_STATUS_RESTRICTED;
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
  if (status() !== BACKGROUND_TASK_STATUS_AVAILABLE) {
    throw new ExpoBackgroundTaskError(
      'ERR_BACKGROUND_TASK_NOT_CONFIGURED',
      `HarmonyOS WorkScheduler or extension '${WORK_SCHEDULER_EXTENSION_NAME}' is unavailable. ` +
        'Run Expo prebuild with the @expo-harmony/expo-background-task config plugin.',
    );
  }
}

function requireTaskName(value: ESObject): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_INVALID_TASK_NAME', 'BackgroundTask expected a non-empty string task name.');
  }
  return value;
}

function requireOptions(value: ESObject): ESObject {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_INVALID_OPTIONS', 'BackgroundTask expected options to be an object.');
  }
  return value;
}

function minimumIntervalMilliseconds(options: ESObject): number {
  const input = options as BackgroundTaskOptionsInput;
  const value: ESObject = input.minimumInterval;
  if (value === undefined || value === null) return EXPO_DEFAULT_INTERVAL_MS;

  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    throw new ExpoBackgroundTaskError(
      'ERR_BACKGROUND_TASK_INVALID_INTERVAL',
      'BackgroundTask minimumInterval must be a positive finite number of minutes.',
    );
  }

  const interval = Math.ceil(value * MILLISECONDS_PER_MINUTE);
  if (!Number.isSafeInteger(interval)) {
    throw new ExpoBackgroundTaskError(
      'ERR_BACKGROUND_TASK_INVALID_INTERVAL',
      'BackgroundTask minimumInterval is too large for HarmonyOS WorkScheduler.',
    );
  }

  return Math.max(WORK_SCHEDULER_MINIMUM_INTERVAL_MS, interval);
}

function intervalForTasks(tasks: ExpoTaskRecord[]): number {
  let interval = EXPO_DEFAULT_INTERVAL_MS;
  for (const task of tasks) {
    interval = Math.min(interval, minimumIntervalMilliseconds(task.options));
  }

  return interval;
}

function createWorkInfo(context: UITurboModuleContext, id: number, interval: number): workScheduler.WorkInfo {
  const params: Record<string, number | string | boolean> = {};
  params[OWNER_PARAMETER] = OWNER_PARAMETER_VALUE;
  params[TASK_MANAGER_OWNER_PARAMETER] = ExpoTaskManagerRegistry.ownerKey(context);

  return {
    workId: id,
    bundleName: context.uiAbilityContext.abilityInfo.bundleName,
    abilityName: WORK_SCHEDULER_EXTENSION_NAME,
    isPersisted: true,
    networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
    isRepeat: true,
    repeatCycleTime: interval,
    parameters: params,
  };
}

function workMatchesInterval(work: workScheduler.WorkInfo, interval: number, ownerKey: string): boolean {
  return (
    work.isPersisted === true &&
    work.networkType === workScheduler.NetworkType.NETWORK_TYPE_ANY &&
    work.isRepeat === true &&
    work.repeatCycleTime === interval &&
    work.parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    work.parameters?.[TASK_MANAGER_OWNER_PARAMETER] === ownerKey
  );
}

function isOwnedWork(context: UITurboModuleContext, work: workScheduler.WorkInfo): boolean {
  return (
    work.bundleName === context.uiAbilityContext.abilityInfo.bundleName &&
    work.abilityName === WORK_SCHEDULER_EXTENSION_NAME &&
    work.parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    work.parameters?.[TASK_MANAGER_OWNER_PARAMETER] === ExpoTaskManagerRegistry.ownerKey(context)
  );
}

async function readAllWorks(): Promise<workScheduler.WorkInfo[]> {
  try {
    return await workScheduler.obtainAllWorks();
  } catch (error) {
    throw new ExpoBackgroundTaskError(
      'ERR_BACKGROUND_TASK_SCHEDULER',
      `Unable to query registered tasks with HarmonyOS WorkScheduler: ${String(error)}`,
    );
  }
}

function allocateWorkId(context: UITurboModuleContext, works: workScheduler.WorkInfo[]): number {
  const ids: Set<number> = new Set(works.map((work: workScheduler.WorkInfo): number => work.workId));

  let id = stableWorkId(`${BACKGROUND_TASK_TYPE}:${ExpoTaskManagerRegistry.ownerKey(context)}`);
  const first = id;
  do {
    if (!ids.has(id)) return id;
    id = id === WORK_ID_MAXIMUM ? WORK_ID_MINIMUM : id + 1;
  } while (id !== first);

  throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_WORK_ID', 'HarmonyOS has no available WorkScheduler identifier for Expo BackgroundTask.');
}

function stableWorkId(value: string): number {
  let hash = FNV_OFFSET_BASIS;
  for (let i = 0; i < value.length; ++i) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, FNV_PRIME);
  }

  return ((hash >>> 0) % WORK_ID_MAXIMUM) + WORK_ID_MINIMUM;
}

function cancelWork(work: workScheduler.WorkInfo): void {
  try {
    workScheduler.stopWork(work, true);
  } catch (error) {
    throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_SCHEDULER', `Unable to cancel with HarmonyOS WorkScheduler: ${String(error)}`);
  }
}

function cancelWorkBestEffort(work: workScheduler.WorkInfo, context: UITurboModuleContext): void {
  try {
    cancelWork(work);
  } catch (error) {
    context.logger.warn(`Unable to remove a duplicate Expo BackgroundTask work: ${String(error)}`);
  }
}

function restoreWorkBestEffort(work: workScheduler.WorkInfo, context: UITurboModuleContext): void {
  try {
    workScheduler.startWork(work);
  } catch (error) {
    context.logger.error(`Unable to restore Expo BackgroundTask after an update failed: ${String(error)}`);
  }
}

function registerPackage(): void {
  if (packageRegistered) return;

  ExpoTaskManagerRegistry.registerConsumer(backgroundTaskConsumer);
  ExpoPlatformServiceRegistry.register(new ExpoBackgroundTaskServiceFactory());
  packageRegistered = true;
}

class ExpoBackgroundTaskServiceFactory implements ExpoPlatformServiceFactory {
  readonly name: string = BACKGROUND_TASK_SERVICE_NAME;

  create(context: UITurboModuleContext): ExpoBackgroundTaskService {
    return new ExpoBackgroundTaskService(context);
  }
}

export class ExpoBackgroundTaskPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerPackage();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-background-task';
  }
}
