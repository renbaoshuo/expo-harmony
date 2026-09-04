import { bundleManager } from '@kit.AbilityKit';
import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
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
  BACKGROUND_TASK_MODULE_NAME,
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
  WORK_ID_MAXIMUM,
  WORK_ID_MINIMUM,
  WORK_SCHEDULER_CAPABILITY,
  WORK_SCHEDULER_EXTENSION_NAME,
  WORK_SCHEDULER_MINIMUM_INTERVAL_MS,
} from './BackgroundTaskConstants';
import { BackgroundTaskRuntime } from './BackgroundTaskRuntime';

interface BackgroundTaskOptionsInput {
  minimumInterval?: ESObject;
}

class ExpoBackgroundTaskError extends ExpoModuleError {
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
    this.name = 'ExpoBackgroundTaskError';
  }
}

class ExpoBackgroundTaskConsumer implements ExpoTaskConsumer {
  readonly taskType: string = BACKGROUND_TASK_TYPE;
  readonly consumerId: string = OWNER_PARAMETER_VALUE;
  readonly consumerVersion: number = 1;
  private mutation: Promise<void> = Promise.resolve();

  async onTasksChanged(context: ExpoModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      await this.reconcile(context, tasks);
    });
  }

  async onExecutionFinished(context: ExpoModuleContext, _results: ExpoTaskExecutionResult[], requestId?: string): Promise<void> {
    await BackgroundTaskRuntime.finish(context.uiAbilityContext, ExpoTaskManagerRegistry.ownerKey(context), requestId);
  }

  async onExecutionExpired(context: ExpoModuleContext, requestId?: string): Promise<void> {
    try {
      const module = context.getModule(BACKGROUND_TASK_MODULE_NAME);
      if (module instanceof ExpoBackgroundTaskModule) module.notifyTasksExpired();
    } finally {
      await BackgroundTaskRuntime.expire(context.uiAbilityContext, ExpoTaskManagerRegistry.ownerKey(context), requestId);
    }
  }

  private async reconcile(context: ExpoModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
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

    try {
      workScheduler.startWork(next);
    } catch (error) {
      throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_SCHEDULER', `Unable to schedule with HarmonyOS WorkScheduler: ${String(error)}`);
    }

    if (current !== undefined) {
      try {
        cancelWork(current);
      } catch (error) {
        cancelWorkBestEffort(next, context);
        throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_SCHEDULER', `Unable to replace the previous HarmonyOS work: ${String(error)}`);
      }
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
let consumerRegistered: boolean = false;

class BackgroundTaskOptions {
  minimumInterval?: number = undefined;
}

class EmptyEventPayload {}

const BACKGROUND_TASK_OPTIONS_TYPE: ExpoValueType<BackgroundTaskOptions> = new ExpoValueType<BackgroundTaskOptions>(
  'BackgroundTask options object',
  (value: ESObject): BackgroundTaskOptions => decodeOptions(value),
  (value: BackgroundTaskOptions): ESObject => value,
);

export class ExpoBackgroundTaskWorkSchedulerExtension extends WorkSchedulerExtensionAbility {
  private readonly requests: Map<number, Promise<string | undefined>[]> = new Map();

  override onWorkStart(work: workScheduler.WorkInfo): void {
    registerConsumer();
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
    registerConsumer();
    const requests = this.requests.get(work.workId);
    const request = requests?.shift();

    if (requests !== undefined && requests.length === 0) this.requests.delete(work.workId);

    BackgroundTaskRuntime.stop(this.context, work, this.context.extensionAbilityInfo.bundleName, this.context.extensionAbilityInfo.name, request);
  }
}

/** ArkTS author implementation of Expo's BackgroundTask module. */
export class ExpoBackgroundTaskModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
    registerConsumer();
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name(BACKGROUND_TASK_MODULE_NAME)
      .events([EXPIRATION_EVENT_NAME])
      .asyncFunction('getStatusAsync', ExpoFunction.typed0(async (): Promise<number> => status(this.context)).returns(ExpoValueTypes.number()))
      .asyncFunction(
        'registerTaskAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          BACKGROUND_TASK_OPTIONS_TYPE,
          async (taskName: string, options: BackgroundTaskOptions): Promise<void> => {
            requireConfigured();
            requireAvailable(this.context);
            await ExpoTaskManagerRegistry.registerTask(this.context, requireTaskName(taskName), BACKGROUND_TASK_TYPE, options);
          },
        ),
      )
      .asyncFunction(
        'unregisterTaskAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (taskName: string): Promise<void> => {
          await ExpoTaskManagerRegistry.unregisterTaskForConsumer(this.context, requireTaskName(taskName), BACKGROUND_TASK_TYPE);
        }),
      );
  }

  /** @internal Called by the TaskManager consumer in this RuntimeContext. */
  notifyTasksExpired(): void {
    if (this.context.isValid) this.sendEvent(EXPIRATION_EVENT_NAME, new EmptyEventPayload());
  }
}

function status(context: ExpoModuleContext): number {
  return hasWorkSchedulerExtension() && ExpoTaskManagerRegistry.canEnsureRuntimeForContext(context)
    ? BACKGROUND_TASK_STATUS_AVAILABLE
    : BACKGROUND_TASK_STATUS_RESTRICTED;
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
  if (status(context) !== BACKGROUND_TASK_STATUS_AVAILABLE) {
    throw new ExpoBackgroundTaskError(
      'ERR_BACKGROUND_TASK_UNAVAILABLE',
      'HarmonyOS WorkScheduler or the TaskManager cold-start runtime loader is unavailable.',
    );
  }
}

function requireConfigured(): void {
  if (!hasWorkSchedulerExtension()) {
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

function decodeOptions(value: ESObject): BackgroundTaskOptions {
  const raw: ESObject = requireOptions(value);
  const unknown = Object.keys(raw as Record<string, ESObject>).filter((key: string): boolean => key !== 'minimumInterval');
  if (unknown.length > 0) {
    throw new ExpoBackgroundTaskError('ERR_BACKGROUND_TASK_INVALID_OPTIONS', `Unsupported BackgroundTask option '${unknown[0]}'.`);
  }
  const result = new BackgroundTaskOptions();
  const interval: ESObject = (raw as BackgroundTaskOptionsInput).minimumInterval;
  if (interval !== undefined && interval !== null) {
    minimumIntervalMilliseconds(raw);
    result.minimumInterval = interval as number;
  }
  return result;
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
  return minimumIntervalMilliseconds(tasks[tasks.length - 1]?.options ?? {});
}

function createWorkInfo(context: ExpoModuleContext, id: number, interval: number): workScheduler.WorkInfo {
  const params: Record<string, number | string | boolean> = {};
  params[OWNER_PARAMETER] = OWNER_PARAMETER_VALUE;
  ExpoTaskManagerWorkMetadata.write(params, ExpoTaskManagerRegistry.ownerKey(context));

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
    ExpoTaskManagerWorkMetadata.owner(work.parameters) === ownerKey
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

function allocateWorkId(context: ExpoModuleContext, works: workScheduler.WorkInfo[]): number {
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

function cancelWorkBestEffort(work: workScheduler.WorkInfo, context: ExpoModuleContext): void {
  try {
    cancelWork(work);
  } catch (error) {
    context.logger.warn(`Unable to remove a duplicate Expo BackgroundTask work: ${String(error)}`);
  }
}

function registerConsumer(): void {
  if (consumerRegistered) return;
  ExpoTaskManagerRegistry.registerConsumer(backgroundTaskConsumer);
  consumerRegistered = true;
}
