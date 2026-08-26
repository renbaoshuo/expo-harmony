import { LifecycleState, RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { EXPO_MODULE_EVENT, ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import type { ExpoPlatformServiceFactory } from '@expo-harmony/expo-modules-core';

import {
  EXECUTION_REQUEST_SCHEMA_VERSION,
  REQUEST_PHASE_EXPIRING,
  REQUEST_PHASE_FINISHING,
  REQUEST_PHASE_QUEUED,
  TASK_RECORD_SCHEMA_VERSION,
  decodeExecutionRequest,
  decodeTaskRecords,
} from './TaskManagerStorageCodec.ts';

const SERVICE_NAME: string = 'ExpoTaskManagerService';
const MODULE_NAME: string = 'ExpoTaskManager';
const TASK_EVENT_NAME: string = 'TaskManager.executeTask';
const PREFERENCES_NAME: string = 'ExpoTaskManager';
const REGISTERED_TASKS_KEY: string = 'registeredTasks';
const PENDING_EXECUTION_KEY_PREFIX: string = 'pendingExecution.';
const CORRUPTED_REGISTERED_TASKS_KEY: string = 'corruptedRegisteredTasks';
const CORRUPTED_PENDING_EXECUTIONS_KEY: string = 'corruptedPendingExecutions';
const QUEUE_CHANGED_EVENT: string = 'expo.taskManager.pendingExecutionChanged';
const QUEUE_EXPIRED_EVENT: string = 'expo.taskManager.pendingExecutionExpired';
const RNOH_TIMERS_RESUME_MESSAGE: string = 'FOREGROUND';
const RNOH_TIMERS_PAUSE_MESSAGE: string = 'BACKGROUND';
const MAXIMUM_FUTURE_CLOCK_SKEW_MS: number = 5 * 60 * 1000;
const DEFAULT_DIRECT_EXECUTION_TIMEOUT_MS: number = 2 * 60 * 1000;
const QUEUE_RETRY_DELAY_MS: number = 1000;
const MAXIMUM_REQUEST_ID_LENGTH: number = 128;
const MAXIMUM_SERIALIZED_REQUEST_LENGTH: number = 512 * 1024;
const MAXIMUM_CORRUPTION_DIAGNOSTICS: number = 20;
let packageRegistered: boolean = false;

export class ExpoTaskRecord {
  version: number = TASK_RECORD_SCHEMA_VERSION;
  taskName: string;
  taskType: string;
  options: ESObject;
  ownerKey: string;
  consumerId: string;
  consumerVersion: number;
  registrationGeneration: number;

  constructor(
    taskName: string,
    taskType: string,
    options: ESObject,
    ownerKey: string,
    consumerId: string,
    consumerVersion: number,
    registrationGeneration: number,
  ) {
    this.taskName = taskName;
    this.taskType = taskType;
    this.options = options;
    this.ownerKey = ownerKey;
    this.consumerId = consumerId;
    this.consumerVersion = consumerVersion;
    this.registrationGeneration = registrationGeneration;
  }
}

class ExpoTaskPublicRecord {
  taskName: string;
  taskType: string;
  options: ESObject;

  constructor(task: ExpoTaskRecord) {
    this.taskName = task.taskName;
    this.taskType = task.taskType;
    this.options = task.options;
  }
}

export class ExpoTaskExecutionResult {
  taskName: string;
  result: ESObject;

  constructor(taskName: string, result: ESObject) {
    this.taskName = taskName;
    this.result = result;
  }
}

export interface ExpoTaskConsumer {
  readonly taskType: string;
  readonly consumerId: string;
  readonly consumerVersion: number;
  onTasksChanged(context: UITurboModuleContext, tasks: ExpoTaskRecord[]): Promise<void>;
  onExecutionFinished?(context: UITurboModuleContext, results: ExpoTaskExecutionResult[], requestId?: string): Promise<void>;
  onExecutionExpired?(context: UITurboModuleContext, requestId?: string): Promise<void>;
}

class TaskExecutionInfo {
  eventId: string;
  taskName: string;

  constructor(eventId: string, taskName: string) {
    this.eventId = eventId;
    this.taskName = taskName;
  }
}

class TaskExecutionBody {
  data: ESObject;
  error: ESObject;
  executionInfo: TaskExecutionInfo;

  constructor(eventId: string, taskName: string, data: ESObject, error: ESObject) {
    this.data = data;
    this.error = error;
    this.executionInfo = new TaskExecutionInfo(eventId, taskName);
  }
}

class TaskManagerEventMessage {
  moduleName: string = MODULE_NAME;
  eventName: string = TASK_EVENT_NAME;
  arguments: ESObject[];

  constructor(body: TaskExecutionBody) {
    this.arguments = [body];
  }
}

class PendingExecutionRequest {
  version: number = EXECUTION_REQUEST_SCHEMA_VERSION;
  id: string;
  taskType: string;
  taskName?: string;
  ownerKey: string;
  consumerId: string;
  consumerVersion: number;
  registrationGeneration: number;
  createdAt: number;
  expiresAt: number;
  phase: string;
  data: ESObject;
  error: ESObject;
  results?: ExpoTaskExecutionResult[];

  constructor(
    id: string,
    taskType: string,
    createdAt: number,
    expiresAt: number,
    ownerKey: string,
    consumerId: string,
    consumerVersion: number,
    registrationGeneration: number,
    taskName?: string,
    data: ESObject = {},
    error: ESObject = null,
    phase: string = REQUEST_PHASE_QUEUED,
    results?: ExpoTaskExecutionResult[],
  ) {
    this.id = id;
    this.taskType = taskType;
    this.taskName = taskName;
    this.ownerKey = ownerKey;
    this.consumerId = consumerId;
    this.consumerVersion = consumerVersion;
    this.registrationGeneration = registrationGeneration;
    this.createdAt = createdAt;
    this.expiresAt = expiresAt;
    this.phase = phase;
    this.data = data;
    this.error = error;
    this.results = results;
  }
}

class PendingExecutionBatch {
  ready: PendingExecutionRequest[] = [];
  expired: PendingExecutionRequest[] = [];
}

class PendingExecutionSignal {
  requestId?: string;
  taskType: string;
  taskName?: string;
  ownerKey: string;

  constructor(taskType: string, ownerKey: string, requestId?: string, taskName?: string) {
    this.taskType = taskType;
    this.ownerKey = ownerKey;
    this.requestId = requestId;
    this.taskName = taskName;
  }
}

class ActiveTaskExecution {
  readonly eventId: string;
  readonly taskName: string;
  readonly taskType: string;
  readonly requestId?: string;
  readonly completion: Promise<void>;
  result?: ExpoTaskExecutionResult;
  expired: boolean = false;
  aborted: boolean = false;
  private callback?: () => void;

  constructor(eventId: string, taskName: string, taskType: string, requestId?: string) {
    this.eventId = eventId;
    this.taskName = taskName;
    this.taskType = taskType;
    this.requestId = requestId;
    this.completion = new Promise<void>((resolve) => {
      this.callback = resolve;
    });
  }

  finish(result: ESObject): void {
    const callback = this.callback;
    if (callback === undefined) return;

    this.callback = undefined;
    this.result = new ExpoTaskExecutionResult(this.taskName, result);
    callback();
  }

  expire(): void {
    const callback = this.callback;
    if (callback === undefined) return;

    this.callback = undefined;
    this.expired = true;
    callback();
  }

  abort(): void {
    const callback = this.callback;
    if (callback === undefined) return;

    this.callback = undefined;
    this.aborted = true;
    callback();
  }
}

class ExpoTaskManagerError extends ExpoPlatformServiceError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoTaskManagerError';
  }
}

class TaskManagerStorageLock {
  private static mutation: Promise<void> = Promise.resolve();

  static async serialize(operation: () => Promise<void>): Promise<void> {
    const next = TaskManagerStorageLock.mutation.catch((): void => {}).then(operation);
    TaskManagerStorageLock.mutation = next.catch((): void => {});
    await next;
  }
}

class CorruptionDiagnostic {
  key: string;
  valueType: string;
  length: number;
  recoveredAt: number;

  constructor(key: string, value: ESObject) {
    this.key = key;
    this.valueType = value === null ? 'null' : typeof value;
    this.length = serializedLength(value);
    this.recoveredAt = Date.now();
  }
}

class TaskRepository {
  private readonly store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  static async create(context: common.Context): Promise<TaskRepository> {
    const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
    return new TaskRepository(store);
  }

  async readTasks(): Promise<ExpoTaskRecord[]> {
    let tasks: ExpoTaskRecord[] = [];
    await TaskRepository.serialize(async (): Promise<void> => {
      tasks = await this.readTasksLocked();
    });
    return tasks;
  }

  async readTasksLocked(): Promise<ExpoTaskRecord[]> {
    const raw = await this.store.get(REGISTERED_TASKS_KEY, '[]');
    const decoded = decodeTaskRecords(raw);
    const tasks = decoded.values.map(
      (task): ExpoTaskRecord =>
        new ExpoTaskRecord(
          task.taskName,
          task.taskType,
          task.options,
          task.ownerKey,
          task.consumerId,
          task.consumerVersion,
          task.registrationGeneration,
        ),
    );

    if (decoded.corrupted) {
      await recordCorruptionDiagnostic(this.store, CORRUPTED_REGISTERED_TASKS_KEY, REGISTERED_TASKS_KEY, raw);
      await this.writeTasks(tasks);
      console.error('Expo TaskManager repaired corrupted registered task storage.');
    }

    return tasks;
  }

  async writeTasks(tasks: ExpoTaskRecord[]): Promise<void> {
    await this.store.put(REGISTERED_TASKS_KEY, JSON.stringify(tasks));
    await this.store.flush();
  }

  static async serialize(operation: () => Promise<void>): Promise<void> {
    await TaskManagerStorageLock.serialize(operation);
  }
}

async function readPendingExecutions(store: preferences.Preferences): Promise<PendingExecutionRequest[]> {
  const raw = await store.getAll();
  const values = raw as Record<string, ESObject>;
  const requests: PendingExecutionRequest[] = [];
  let changed = false;

  for (const key of Object.keys(values)) {
    if (!key.startsWith(PENDING_EXECUTION_KEY_PREFIX)) continue;

    const value: ESObject = values[key] as ESObject;
    const request = decodeExecutionRequest(value);

    if (request !== undefined && key === pendingExecutionKey(request.ownerKey, request.id)) {
      const pending = new PendingExecutionRequest(
        request.id,
        request.taskType,
        request.createdAt,
        request.expiresAt,
        request.ownerKey,
        request.consumerId,
        request.consumerVersion,
        request.registrationGeneration,
        request.taskName,
        request.data,
        request.error,
        request.phase,
        executionResults(request.results),
      );
      requests.push(pending);
      continue;
    }

    await recordCorruptionDiagnostic(store, CORRUPTED_PENDING_EXECUTIONS_KEY, key, value);
    await store.delete(key);
    changed = true;
  }

  if (changed) {
    await store.flush();
    console.error('Expo TaskManager repaired corrupted pending execution storage.');
  }

  requests.sort((left: PendingExecutionRequest, right: PendingExecutionRequest): number => {
    if (left.createdAt !== right.createdAt) return left.createdAt - right.createdAt;
    return left.id.localeCompare(right.id);
  });
  return requests;
}

async function savePendingExecution(store: preferences.Preferences, request: PendingExecutionRequest): Promise<void> {
  const serialized = serializeRequest(request);
  await store.put(pendingExecutionKey(request.ownerKey, request.id), serialized);
  await store.flush();
}

async function removePendingExecution(store: preferences.Preferences, ownerKey: string, requestId: string): Promise<void> {
  await store.delete(pendingExecutionKey(ownerKey, requestId));
}

function pendingExecutionKey(ownerKey: string, requestId: string): string {
  return `${PENDING_EXECUTION_KEY_PREFIX}${ownerStorageSegment(ownerKey)}.${requestId}`;
}

function ownerStorageSegment(ownerKey: string): string {
  let first = 0x811c9dc5;
  let second = 0x9e3779b9;
  for (let index = 0; index < ownerKey.length; ++index) {
    const code = ownerKey.charCodeAt(index);
    first = Math.imul(first ^ code, 0x01000193);
    second = Math.imul(second ^ code, 0x85ebca6b);
  }
  return `${first >>> 0}-${second >>> 0}`;
}

function executionResults(values: ESObject[] | undefined): ExpoTaskExecutionResult[] | undefined {
  if (values === undefined) return undefined;
  const results: ExpoTaskExecutionResult[] = [];
  for (let index = 0; index < values.length; ++index) {
    const value: ESObject = values[index];
    if (value === null || typeof value !== 'object' || Array.isArray(value)) continue;
    const record = value as Record<string, ESObject>;
    if (typeof record['taskName'] !== 'string') continue;
    results.push(new ExpoTaskExecutionResult(record['taskName'], record['result']));
  }
  return results;
}

function serializeRequest(request: PendingExecutionRequest): string {
  let serialized: string;
  try {
    serialized = JSON.stringify(request);
  } catch (error) {
    throw new ExpoTaskManagerError(
      'ERR_TASK_MANAGER_REQUEST_SERIALIZATION',
      `Unable to serialize background request '${request.id}': ${String(error)}`,
    );
  }
  if (serialized.length > MAXIMUM_SERIALIZED_REQUEST_LENGTH) {
    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_REQUEST_TOO_LARGE', `Background request '${request.id}' exceeds the storage limit.`);
  }
  return serialized;
}

function serializedLength(value: ESObject): number {
  if (typeof value === 'string') return value.length;
  try {
    return JSON.stringify(value).length;
  } catch (_) {
    return -1;
  }
}

async function recordCorruptionDiagnostic(store: preferences.Preferences, storageKey: string, corruptedKey: string, value: ESObject): Promise<void> {
  const diagnostics: CorruptionDiagnostic[] = [];
  const raw = await store.get(storageKey, '[]');
  if (typeof raw === 'string') {
    try {
      const parsed: ESObject = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        const items: ESObject[] = parsed as ESObject[];
        const start = Math.max(0, items.length - MAXIMUM_CORRUPTION_DIAGNOSTICS + 1);
        for (let index = start; index < items.length; ++index) {
          const item: ESObject = items[index];
          if (item !== null && typeof item === 'object' && !Array.isArray(item)) diagnostics.push(item as CorruptionDiagnostic);
        }
      }
    } catch (_) {}
  }
  diagnostics.push(new CorruptionDiagnostic(corruptedKey, value));
  await store.put(storageKey, JSON.stringify(diagnostics));
}

/**
 * Persistence boundary used by a WorkSchedulerExtensionAbility before an RNOH
 * runtime is necessarily available. A live TaskManager scope consumes the
 * request immediately; otherwise the consumer-provided deadline remains
 * durable until native cleanup succeeds.
 */
export class ExpoTaskManagerBackgroundQueue {
  static async enqueue(
    context: common.Context,
    ownerKey: string,
    taskType: string,
    expiresAt: number,
    requestId: string,
    taskName?: string,
    data: ESObject = {},
    error: ESObject = null,
  ): Promise<string> {
    requireTaskType(taskType);
    requireRequestId(requestId);
    if (taskName !== undefined) requireTaskName(taskName);
    const createdAt = Date.now();
    requireExecutionDeadline(expiresAt, createdAt);
    requireObject(data, 'task execution data');
    if (error !== null) requireObject(error, 'task execution error');
    const owner = requireOwnerKey(ownerKey);

    await TaskManagerStorageLock.serialize(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const requests = await readPendingExecutions(store);
      const current = requests.find((request: PendingExecutionRequest): boolean => request.id === requestId && request.ownerKey === owner);
      const target = await queueTarget(store, owner, taskType, taskName);

      if (current !== undefined && !sameRequest(current, taskType, taskName, owner, expiresAt, data, error, target)) {
        throw new ExpoTaskManagerError(
          'ERR_TASK_MANAGER_DUPLICATE_REQUEST',
          `Background execution request '${requestId}' conflicts with an existing request generation.`,
        );
      }

      if (current === undefined) {
        const request = new PendingExecutionRequest(
          requestId,
          taskType,
          createdAt,
          expiresAt,
          owner,
          target.consumerId,
          target.consumerVersion,
          target.registrationGeneration,
          taskName,
          data,
          error,
        );

        await savePendingExecution(store, request);
      }
    });

    context.getApplicationContext().eventHub.emit(QUEUE_CHANGED_EVENT);
    await ExpoTaskManagerRegistry.ensureRuntime(owner);

    return requestId;
  }

  static async expireRequest(context: common.Context, ownerKey: string, taskType: string, requestId: string): Promise<void> {
    requireTaskType(taskType);
    requireRequestId(requestId);
    const owner = requireOwnerKey(ownerKey);
    const request = await TaskManagerQueueRepository.markExpiring(context, owner, taskType, requestId);
    if (request !== undefined) emitExpiration(context, request);
  }
}

class QueueTarget {
  consumerId: string;
  consumerVersion: number;
  registrationGeneration: number;

  constructor(consumerId: string, consumerVersion: number, registrationGeneration: number) {
    this.consumerId = consumerId;
    this.consumerVersion = consumerVersion;
    this.registrationGeneration = registrationGeneration;
  }
}

class TaskManagerQueueRepository {
  static async pending(context: common.Context, ownerKey: string, now: number): Promise<PendingExecutionBatch> {
    const batch = new PendingExecutionBatch();
    await TaskManagerStorageLock.serialize(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const requests = await readPendingExecutions(store);

      for (const request of requests) {
        if (request.ownerKey !== ownerKey) continue;
        if (request.phase === REQUEST_PHASE_EXPIRING || request.expiresAt <= now || request.createdAt > now + MAXIMUM_FUTURE_CLOCK_SKEW_MS) {
          batch.expired.push(request);
        } else {
          batch.ready.push(request);
        }
      }
    });

    return batch;
  }

  static async markFinishing(context: common.Context, request: PendingExecutionRequest, results: ExpoTaskExecutionResult[]): Promise<boolean> {
    let acquired = false;
    await TaskManagerStorageLock.serialize(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const requests = await readPendingExecutions(store);
      const current = requests.find((pending: PendingExecutionRequest): boolean => pending.id === request.id);
      if (current === undefined || !sameTarget(current, request)) return;
      if (current.phase === REQUEST_PHASE_EXPIRING) return;
      if (current.phase === REQUEST_PHASE_FINISHING) {
        acquired = true;
        return;
      }
      current.phase = REQUEST_PHASE_FINISHING;
      current.results = results;
      await savePendingExecution(store, current);
      acquired = true;
    });
    return acquired;
  }

  static async markExpiring(
    context: common.Context,
    ownerKey: string,
    taskType: string,
    requestId: string,
  ): Promise<PendingExecutionRequest | undefined> {
    let found: PendingExecutionRequest | undefined;
    await TaskManagerStorageLock.serialize(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const requests = await readPendingExecutions(store);
      const request = requests.find((pending: PendingExecutionRequest): boolean => {
        return pending.id === requestId && pending.taskType === taskType && pending.ownerKey === ownerKey;
      });
      if (request === undefined || request.phase === REQUEST_PHASE_FINISHING) return;
      request.phase = REQUEST_PHASE_EXPIRING;
      request.expiresAt = Math.min(request.expiresAt, Date.now());
      await savePendingExecution(store, request);
      found = request;
    });
    return found;
  }

  static async acknowledge(context: common.Context, request: PendingExecutionRequest, phase: string): Promise<void> {
    await TaskManagerStorageLock.serialize(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const requests = await readPendingExecutions(store);
      const current = requests.find((pending: PendingExecutionRequest): boolean => pending.id === request.id);
      if (current === undefined || !sameTarget(current, request) || current.phase !== phase) return;
      await removePendingExecution(store, request.ownerKey, request.id);
      await store.flush();
    });
  }
}

async function queueTarget(store: preferences.Preferences, ownerKey: string, taskType: string, taskName?: string): Promise<QueueTarget> {
  const consumer = ExpoTaskManagerRegistry.consumer(taskType);
  if (consumer === undefined) {
    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_CONSUMER_NOT_FOUND', `No Harmony native task consumer is registered for '${taskType}'.`);
  }
  const decoded = decodeTaskRecords(await store.get(REGISTERED_TASKS_KEY, '[]'));
  let generation = 0;
  if (taskName === undefined) return new QueueTarget(consumer.consumerId, consumer.consumerVersion, generation);
  for (const task of decoded.values) {
    if (task.ownerKey !== ownerKey || task.taskType !== taskType || task.taskName !== taskName) continue;
    generation = Math.max(generation, task.registrationGeneration);
  }
  return new QueueTarget(consumer.consumerId, consumer.consumerVersion, generation);
}

function sameTarget(left: PendingExecutionRequest, right: PendingExecutionRequest): boolean {
  return (
    left.id === right.id &&
    left.taskType === right.taskType &&
    left.taskName === right.taskName &&
    left.ownerKey === right.ownerKey &&
    left.consumerId === right.consumerId &&
    left.consumerVersion === right.consumerVersion &&
    left.registrationGeneration === right.registrationGeneration
  );
}

function sameRequest(
  current: PendingExecutionRequest,
  taskType: string,
  taskName: string | undefined,
  ownerKey: string,
  expiresAt: number,
  data: ESObject,
  error: ESObject,
  target: QueueTarget,
): boolean {
  return (
    current.phase === REQUEST_PHASE_QUEUED &&
    current.taskType === taskType &&
    current.taskName === taskName &&
    current.ownerKey === ownerKey &&
    current.expiresAt === expiresAt &&
    current.consumerId === target.consumerId &&
    current.consumerVersion === target.consumerVersion &&
    current.registrationGeneration === target.registrationGeneration &&
    serializedEquals(current.data, data) &&
    serializedEquals(current.error, error)
  );
}

function serializedEquals(left: ESObject, right: ESObject): boolean {
  try {
    return JSON.stringify(left) === JSON.stringify(right);
  } catch (_) {
    return false;
  }
}

function emitExpiration(context: common.Context, request: PendingExecutionRequest): void {
  context
    .getApplicationContext()
    .eventHub.emit(QUEUE_EXPIRED_EVENT, new PendingExecutionSignal(request.taskType, request.ownerKey, request.id, request.taskName));
}

class ExpoTaskManagerScope {
  private readonly context: UITurboModuleContext;
  private readonly repository: TaskRepository;
  private readonly owner: string;
  private readonly activeExecutions: Map<string, ActiveTaskExecution> = new Map();
  private readonly queuedEvents: TaskExecutionBody[] = [];
  private readonly claimedIds: Set<string> = new Set();
  private readonly expirations: Map<string, Promise<void>> = new Map();
  private readonly consumerFailures: Map<string, string> = new Map();
  private readonly subscriptions: Array<() => void> = [];
  private readonly queueListener: () => void;
  private readonly expiryListener: (signal: PendingExecutionSignal) => void;
  private observing: boolean = false;
  private foreground: boolean;
  private destroyed: boolean = false;
  private timerLeaseCount: number = 0;
  private retryTimer: number = -1;
  private draining: Promise<void> = Promise.resolve();

  constructor(context: UITurboModuleContext, repository: TaskRepository) {
    this.context = context;
    this.repository = repository;
    this.owner = runtimeOwnerKey(context);
    this.foreground = context.rnInstance.getLifecycleState() === LifecycleState.READY;
    this.queueListener = (): void => this.scheduleDrain();
    this.expiryListener = (signal: PendingExecutionSignal): void => this.scheduleExpiry(signal);

    const eventHub = context.uiAbilityContext.getApplicationContext().eventHub;
    eventHub.on(QUEUE_CHANGED_EVENT, this.queueListener);
    eventHub.on(QUEUE_EXPIRED_EVENT, this.expiryListener);

    this.subscriptions.push(
      (): void => eventHub.off(QUEUE_CHANGED_EVENT, this.queueListener),
      (): void => eventHub.off(QUEUE_EXPIRED_EVENT, this.expiryListener),
      context.rnInstance.subscribeToLifecycleEvents('FOREGROUND', () => {
        this.foreground = true;
        ExpoTaskManagerRegistry.ownerAvailabilityChanged(this);
      }),
      context.rnInstance.subscribeToLifecycleEvents('BACKGROUND', () => {
        this.foreground = false;
        ExpoTaskManagerRegistry.ownerAvailabilityChanged(this);
        this.reassertTimerLeaseAfterBackgroundTransition();
        this.scheduleDrain();
      }),
    );
  }

  runtimeId(): number {
    return this.context.rnInstance.getId();
  }

  ownerKey(): string {
    return this.owner;
  }

  isForeground(): boolean {
    return this.foreground;
  }

  canOwnQueue(): boolean {
    return !this.destroyed && this.observing;
  }

  async reconcileConsumers(): Promise<void> {
    await TaskRepository.serialize(async (): Promise<void> => {
      const stored = await this.repository.readTasksLocked();
      const tasks: ExpoTaskRecord[] = [];

      for (const task of stored) {
        if (task.ownerKey !== this.owner) {
          tasks.push(task);
          continue;
        }
        const consumer = ExpoTaskManagerRegistry.consumer(task.taskType);
        if (consumer === undefined) {
          tasks.push(task);
          this.consumerFailures.set(task.taskType, `Native consumer '${task.taskType}' is unavailable.`);
          continue;
        }

        if (task.consumerId !== consumer.consumerId || task.consumerVersion !== consumer.consumerVersion) {
          tasks.push(task);
          this.consumerFailures.set(task.taskType, `Native consumer '${task.taskType}' changed incompatibly.`);
          continue;
        }

        tasks.push(task);
      }

      for (const consumer of ExpoTaskManagerRegistry.allConsumers()) {
        try {
          await this.notifyConsumer(consumer.taskType, tasks);
          this.consumerFailures.delete(consumer.taskType);
        } catch (error) {
          const message = errorDescription(error);
          this.consumerFailures.set(consumer.taskType, message);
          this.context.logger.error(`Unable to restore Expo task consumer '${consumer.taskType}': ${message}`);
        }
      }
    });
  }

  async reconcileConsumer(_taskType: string): Promise<void> {
    await this.reconcileConsumers();
  }

  async registerTask(taskName: string, taskType: string, options: ESObject): Promise<void> {
    await TaskRepository.serialize(async (): Promise<void> => {
      const tasks = await this.repository.readTasksLocked();
      const index = tasks.findIndex((task: ExpoTaskRecord): boolean => task.ownerKey === this.owner && task.taskName === taskName);
      const current = index >= 0 ? tasks[index] : undefined;
      const consumer = ExpoTaskManagerRegistry.consumer(taskType);
      if (consumer === undefined) {
        throw new ExpoTaskManagerError('ERR_TASK_MANAGER_CONSUMER_NOT_FOUND', `No Harmony native task consumer is registered for '${taskType}'.`);
      }

      const next = tasks.filter((task: ExpoTaskRecord): boolean => task.ownerKey !== this.owner || task.taskName !== taskName);
      next.push(
        new ExpoTaskRecord(
          taskName,
          taskType,
          options,
          this.owner,
          consumer.consumerId,
          consumer.consumerVersion,
          (current?.registrationGeneration ?? 0) + 1,
        ),
      );

      await this.repository.writeTasks(next);

      try {
        if (current !== undefined && current.taskType !== taskType) {
          await this.notifyConsumer(current.taskType, next);
        }
        await this.notifyConsumer(taskType, next, true);
      } catch (error) {
        await this.repository.writeTasks(tasks);

        const types = current !== undefined && current.taskType !== taskType ? [current.taskType, taskType] : [taskType];
        for (const type of types) {
          try {
            await this.notifyConsumer(type, tasks);
          } catch (rollback) {
            this.context.logger.error(`Unable to restore native consumer '${type}' after registration failed: ${String(rollback)}`);
          }
        }

        throw new ExpoTaskManagerError(
          'ERR_TASK_MANAGER_REGISTRATION_FAILED',
          `Unable to activate native consumer '${taskType}' for task '${taskName}': ${errorDescription(error)}`,
        );
      }

      if (current !== undefined && current.taskType !== taskType) {
        this.abortExecutionsForTask(taskName);
      }
    });
  }

  async unregisterTask(taskName: string): Promise<void> {
    await TaskRepository.serialize(async (): Promise<void> => {
      await this.unregisterTaskInternal(taskName);
    });
  }

  async unregisterTaskForConsumer(taskName: string, taskType: string): Promise<void> {
    await TaskRepository.serialize(async (): Promise<void> => {
      await this.unregisterTaskInternal(taskName, taskType);
    });
  }

  async unregisterAllTasks(): Promise<void> {
    await TaskRepository.serialize(async (): Promise<void> => {
      const tasks = await this.repository.readTasksLocked();
      const owned = tasks.filter((task: ExpoTaskRecord): boolean => task.ownerKey === this.owner);
      if (owned.length === 0) return;

      const types: string[] = [];
      for (const task of owned) {
        if (!types.includes(task.taskType)) types.push(task.taskType);
      }

      const next = tasks.filter((task: ExpoTaskRecord): boolean => task.ownerKey !== this.owner);
      await this.repository.writeTasks(next);

      try {
        for (const taskType of types) {
          await this.notifyConsumer(taskType, next);
        }
      } catch (error) {
        await this.repository.writeTasks(tasks);

        for (const taskType of types) {
          try {
            await this.notifyConsumer(taskType, tasks);
          } catch (rollback) {
            this.context.logger.error(`Unable to restore native consumer '${taskType}' after unregistering all tasks failed: ${String(rollback)}`);
          }
        }

        throw new ExpoTaskManagerError(
          'ERR_TASK_MANAGER_UNREGISTRATION_FAILED',
          `Unable to deactivate all native task consumers: ${errorDescription(error)}`,
        );
      }

      this.abortAllExecutions();
    });
  }

  async isTaskRegistered(taskName: string): Promise<boolean> {
    return (await this.repository.readTasks()).some((task: ExpoTaskRecord): boolean => task.ownerKey === this.owner && task.taskName === taskName);
  }

  async getTaskOptions(taskName: string): Promise<ESObject> {
    const task = (await this.repository.readTasks()).find(
      (item: ExpoTaskRecord): boolean => item.ownerKey === this.owner && item.taskName === taskName,
    );

    return task?.options ?? null;
  }

  async getRegisteredTasks(): Promise<ExpoTaskPublicRecord[]> {
    return (await this.repository.readTasks())
      .filter((task: ExpoTaskRecord): boolean => task.ownerKey === this.owner)
      .map((task: ExpoTaskRecord): ExpoTaskPublicRecord => new ExpoTaskPublicRecord(task));
  }

  notifyTaskFinished(taskName: string, response: ESObject): void {
    if (response === null || typeof response !== 'object' || typeof response.eventId !== 'string') {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INVALID_RESPONSE', 'TaskManager completion response must contain a string eventId.');
    }

    const execution = this.activeExecutions.get(response.eventId);
    if (execution === undefined || execution.taskName !== taskName) return;

    this.activeExecutions.delete(response.eventId);
    execution.finish(response.result ?? null);
  }

  async executeTask(taskName: string, data: ESObject, error: ESObject = null, allowForeground: boolean = false): Promise<ExpoTaskExecutionResult[]> {
    const task = (await this.repository.readTasks()).find(
      (record: ExpoTaskRecord): boolean => record.ownerKey === this.owner && record.taskName === taskName,
    );
    if (task === undefined) {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_TASK_NOT_FOUND', `Task '${taskName}' is not registered.`);
    }

    return (
      (await this.executeTaskType(
        task.taskType,
        allowForeground,
        undefined,
        taskName,
        data,
        error,
        Date.now() + DEFAULT_DIRECT_EXECUTION_TIMEOUT_MS,
      )) ?? []
    );
  }

  async executeTaskType(
    taskType: string,
    allowForeground: boolean = false,
    requestId?: string,
    taskName?: string,
    data: ESObject = {},
    error: ESObject = null,
    expiresAt?: number,
    queueRequest?: PendingExecutionRequest,
    ownerGeneration?: number,
  ): Promise<ExpoTaskExecutionResult[] | undefined> {
    if (this.destroyed) return undefined;
    if (ownerGeneration !== undefined && !ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return undefined;

    let timerLease: boolean = false;
    let deadlineTimer: number = -1;
    const executions: ActiveTaskExecution[] = [];
    try {
      const consumer = ExpoTaskManagerRegistry.consumer(taskType);
      if (consumer === undefined) {
        throw new ExpoTaskManagerError('ERR_TASK_MANAGER_CONSUMER_NOT_FOUND', `No Harmony native task consumer is registered for '${taskType}'.`);
      }
      if (
        queueRequest !== undefined &&
        (queueRequest.ownerKey !== this.owner ||
          queueRequest.consumerId !== consumer.consumerId ||
          queueRequest.consumerVersion !== consumer.consumerVersion)
      ) {
        throw new ExpoTaskManagerError(
          'ERR_TASK_MANAGER_STALE_REQUEST',
          `Background request '${queueRequest.id}' targets a different owner or native consumer generation.`,
        );
      }

      const tasks = (await this.repository.readTasks()).filter(
        (task: ExpoTaskRecord): boolean =>
          task.ownerKey === this.owner && task.taskType === taskType && (taskName === undefined || task.taskName === taskName),
      );
      if (this.destroyed) return undefined;
      if (ownerGeneration !== undefined && !ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return undefined;
      if (
        queueRequest !== undefined &&
        queueRequest.registrationGeneration > 0 &&
        tasks.some((task: ExpoTaskRecord): boolean => task.registrationGeneration !== queueRequest.registrationGeneration)
      ) {
        throw new ExpoTaskManagerError(
          'ERR_TASK_MANAGER_STALE_REQUEST',
          `Background request '${queueRequest.id}' targets an obsolete task registration.`,
        );
      }

      if (tasks.length === 0) {
        if (queueRequest === undefined) await consumer.onExecutionFinished?.(this.context, [], requestId);

        return [];
      }

      if (this.foreground && !allowForeground) return undefined;
      const deadline = expiresAt ?? Date.now() + DEFAULT_DIRECT_EXECUTION_TIMEOUT_MS;
      if (Date.now() >= deadline) return undefined;
      timerLease = this.acquireTimerLease();

      const completions: Promise<void>[] = [];
      for (const task of tasks) {
        const eventId = util.generateRandomUUID(true);
        const execution = new ActiveTaskExecution(eventId, task.taskName, taskType, requestId);

        this.activeExecutions.set(eventId, execution);
        executions.push(execution);
        completions.push(execution.completion);
      }

      deadlineTimer = this.scheduleExecutionDeadline(deadline, executions, consumer, queueRequest);
      if (Date.now() >= deadline) {
        await this.expireExecutionGroup(executions, consumer, queueRequest);
        return undefined;
      }
      if (ownerGeneration !== undefined && !ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return undefined;
      for (const execution of executions) {
        this.publishOrQueue(new TaskExecutionBody(execution.eventId, execution.taskName, data, error));
      }

      await Promise.all(completions);
      if (deadlineTimer >= 0) {
        clearTimeout(deadlineTimer);
        deadlineTimer = -1;
      }
      if (this.destroyed || executions.some((execution: ActiveTaskExecution): boolean => execution.aborted || execution.expired)) {
        return undefined;
      }

      const results: ExpoTaskExecutionResult[] = [];
      for (const execution of executions) {
        if (execution.result !== undefined) results.push(execution.result);
      }
      if (queueRequest === undefined) await consumer.onExecutionFinished?.(this.context, results, requestId);

      return results;
    } finally {
      if (deadlineTimer >= 0) clearTimeout(deadlineTimer);
      for (const execution of executions) {
        if (this.activeExecutions.get(execution.eventId) !== execution) continue;
        this.activeExecutions.delete(execution.eventId);
        this.removeQueuedEvent(execution.eventId);
        execution.abort();
      }
      this.releaseTimerLease(timerLease);
    }
  }

  async expireTaskType(taskType: string, requestId?: string): Promise<void> {
    let expired: boolean = false;
    for (const execution of this.activeExecutions.values()) {
      if (execution.taskType !== taskType) continue;
      if (requestId !== undefined && execution.requestId !== requestId) continue;

      expired = true;
      this.activeExecutions.delete(execution.eventId);
      this.removeQueuedEvent(execution.eventId);
      execution.expire();
    }

    if (expired || requestId !== undefined) {
      await ExpoTaskManagerRegistry.consumer(taskType)?.onExecutionExpired?.(this.context, requestId);
    }
  }

  startObserving(): void {
    if (this.destroyed || this.observing) return;

    this.observing = true;
    ExpoTaskManagerRegistry.ownerAvailabilityChanged(this);
    const events = this.queuedEvents.splice(0);
    for (const body of events) {
      if (this.activeExecutions.has(body.executionInfo.eventId)) this.publish(body);
    }
    this.scheduleDrain();
  }

  stopObserving(): void {
    this.observing = false;
    ExpoTaskManagerRegistry.ownerAvailabilityChanged(this);
  }

  retryPendingExecutions(): void {
    this.scheduleDrain();
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.observing = false;
    if (this.retryTimer >= 0) clearTimeout(this.retryTimer);
    this.retryTimer = -1;
    this.queuedEvents.length = 0;
    this.claimedIds.clear();

    for (const unsubscribe of this.subscriptions) {
      try {
        unsubscribe();
      } catch (error) {
        this.context.logger.warn(`Unable to remove an Expo TaskManager subscription: ${String(error)}`);
      }
    }
    this.subscriptions.length = 0;

    this.abortAllExecutions();
    try {
      if (this.timerLeaseCount > 0 && !this.foreground) this.postTimerLifecycle(RNOH_TIMERS_PAUSE_MESSAGE);
    } catch (error) {
      this.context.logger.error(`Unable to release the RNOH timer lease while destroying TaskManager: ${String(error)}`);
    } finally {
      this.timerLeaseCount = 0;
      ExpoTaskManagerRegistry.detach(this);
    }
  }

  private async unregisterTaskInternal(taskName: string, expectedTaskType?: string): Promise<void> {
    const tasks = await this.repository.readTasksLocked();
    const task = tasks.find((item: ExpoTaskRecord): boolean => item.ownerKey === this.owner && item.taskName === taskName);

    if (task === undefined) {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_TASK_NOT_FOUND', `Task '${taskName}' is not registered.`);
    }

    if (expectedTaskType !== undefined && task.taskType !== expectedTaskType) {
      throw new ExpoTaskManagerError(
        'ERR_TASK_MANAGER_TASK_CONFLICT',
        `Task '${taskName}' belongs to native consumer '${task.taskType}', not '${expectedTaskType}'.`,
      );
    }

    const next = tasks.filter((item: ExpoTaskRecord): boolean => item.ownerKey !== this.owner || item.taskName !== taskName);
    await this.repository.writeTasks(next);

    try {
      await this.notifyConsumer(task.taskType, next);
    } catch (error) {
      await this.repository.writeTasks(tasks);

      try {
        await this.notifyConsumer(task.taskType, tasks);
      } catch (rollback) {
        this.context.logger.error(`Unable to restore native consumer '${task.taskType}' after unregistration failed: ${String(rollback)}`);
      }

      throw new ExpoTaskManagerError(
        'ERR_TASK_MANAGER_UNREGISTRATION_FAILED',
        `Unable to deactivate native consumer '${task.taskType}' for task '${taskName}': ${errorDescription(error)}`,
      );
    }

    this.abortExecutionsForTask(taskName);
  }

  private async notifyConsumer(taskType: string, tasks: ExpoTaskRecord[], required: boolean = false): Promise<void> {
    const consumer = ExpoTaskManagerRegistry.consumer(taskType);
    if (consumer === undefined) {
      if (required) {
        throw new ExpoTaskManagerError('ERR_TASK_MANAGER_CONSUMER_NOT_FOUND', `No Harmony native task consumer is registered for '${taskType}'.`);
      }
      return;
    }

    await consumer.onTasksChanged(
      this.context,
      tasks.filter((task: ExpoTaskRecord): boolean => task.ownerKey === this.owner && task.taskType === taskType),
    );
  }

  private publishOrQueue(body: TaskExecutionBody): void {
    if (this.observing) {
      this.publish(body);
    } else {
      this.queuedEvents.push(body);
    }
  }

  private publish(body: TaskExecutionBody): void {
    if (this.destroyed) return;
    this.context.rnInstance.postMessageToCpp(EXPO_MODULE_EVENT, new TaskManagerEventMessage(body));
  }

  private abortExecutionsForTask(taskName: string): void {
    for (const execution of this.activeExecutions.values()) {
      if (execution.taskName !== taskName) continue;

      this.activeExecutions.delete(execution.eventId);
      this.removeQueuedEvent(execution.eventId);
      execution.abort();
    }
  }

  private abortAllExecutions(): void {
    for (const execution of this.activeExecutions.values()) execution.abort();
    this.activeExecutions.clear();
    this.queuedEvents.length = 0;
  }

  private removeQueuedEvent(eventId: string): void {
    const index = this.queuedEvents.findIndex((body: TaskExecutionBody): boolean => body.executionInfo.eventId === eventId);
    if (index >= 0) this.queuedEvents.splice(index, 1);
  }

  private acquireTimerLease(): boolean {
    if (this.foreground) return false;

    this.timerLeaseCount += 1;
    if (this.timerLeaseCount === 1) {
      // RNOH 0.84.1 only exposes its timer lifecycle through C++ messages.
      // Posting directly keeps React timers alive without changing ArkTS AppState.
      try {
        this.postTimerLifecycle(RNOH_TIMERS_RESUME_MESSAGE);
      } catch (error) {
        this.timerLeaseCount -= 1;
        this.context.logger.error(`Unable to acquire the RNOH timer lease: ${String(error)}`);
        return false;
      }
    }
    return true;
  }

  private releaseTimerLease(acquired: boolean): void {
    if (!acquired || this.timerLeaseCount === 0) return;

    this.timerLeaseCount -= 1;
    if (this.timerLeaseCount === 0 && !this.foreground) {
      try {
        this.postTimerLifecycle(RNOH_TIMERS_PAUSE_MESSAGE);
      } catch (error) {
        this.context.logger.error(`Unable to release the RNOH timer lease: ${String(error)}`);
      }
    }
  }

  private reassertTimerLeaseAfterBackgroundTransition(): void {
    if (this.timerLeaseCount === 0) return;

    setTimeout((): void => {
      if (!this.destroyed && !this.foreground && this.timerLeaseCount > 0) {
        try {
          this.postTimerLifecycle(RNOH_TIMERS_RESUME_MESSAGE);
        } catch (error) {
          this.context.logger.error(`Unable to reassert the RNOH timer lease: ${String(error)}`);
        }
      }
    }, 0);
  }

  private postTimerLifecycle(message: string): void {
    // RNOH 0.84.1 has no public typed timer-lease API. Keep the private protocol
    // isolated here so failure cannot corrupt TaskManager's own lease accounting.
    this.context.rnInstance.postMessageToCpp(message, {});
  }

  private scheduleExecutionDeadline(
    expiresAt: number,
    executions: ActiveTaskExecution[],
    consumer: ExpoTaskConsumer,
    request?: PendingExecutionRequest,
  ): number {
    const delay = Math.max(0, expiresAt - Date.now());

    return setTimeout((): void => {
      this.expireExecutionGroup(executions, consumer, request).catch((error: Object): void => {
        const identity = request?.id ?? consumer.taskType;
        this.context.logger.error(`Unable to expire Expo task execution '${identity}' at its deadline: ${String(error)}`);
        this.scheduleRetry();
      });
    }, delay);
  }

  private async expireExecutionGroup(
    executions: ActiveTaskExecution[],
    consumer: ExpoTaskConsumer,
    request?: PendingExecutionRequest,
  ): Promise<void> {
    if (request !== undefined) {
      await this.expirePendingExecution(request);
      return;
    }
    let expired = false;
    for (const execution of executions) {
      if (this.activeExecutions.get(execution.eventId) !== execution) continue;
      this.activeExecutions.delete(execution.eventId);
      this.removeQueuedEvent(execution.eventId);
      execution.expire();
      expired = true;
    }
    if (expired) await consumer.onExecutionExpired?.(this.context);
  }

  private async expirePendingExecution(request: PendingExecutionRequest): Promise<void> {
    const current = this.expirations.get(request.id);
    if (current !== undefined) {
      await current;
      return;
    }

    const app = this.context.uiAbilityContext.getApplicationContext();
    const expiration = (async (): Promise<void> => {
      const durable = await TaskManagerQueueRepository.markExpiring(app, request.ownerKey, request.taskType, request.id);
      if (durable === undefined) return;
      await this.expireTaskType(request.taskType, request.id);
      await TaskManagerQueueRepository.acknowledge(app, durable, REQUEST_PHASE_EXPIRING);
    })();
    this.expirations.set(request.id, expiration);

    try {
      await expiration;
    } finally {
      if (this.expirations.get(request.id) === expiration) this.expirations.delete(request.id);
    }
  }

  private scheduleDrain(): void {
    const ownerGeneration = ExpoTaskManagerRegistry.ownerGeneration(this);
    if (ownerGeneration === undefined) return;

    const next = this.draining
      .catch((): void => {})
      .then(async (): Promise<void> => {
        const app = this.context.uiAbilityContext.getApplicationContext();
        const batch = await TaskManagerQueueRepository.pending(app, this.owner, Date.now());
        if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;

        for (const request of batch.expired) {
          if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;
          try {
            await this.expirePendingExecution(request);
          } catch (error) {
            this.context.logger.error(`Unable to clean up expired Expo task request '${request.id}': ${String(error)}`);
          }
        }

        for (const request of batch.ready) {
          if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;
          if (this.claimedIds.has(request.id)) continue;

          const now = Date.now();
          if (request.expiresAt <= now || request.createdAt > now + MAXIMUM_FUTURE_CLOCK_SKEW_MS) {
            try {
              await this.expirePendingExecution(request);
            } catch (error) {
              this.context.logger.error(`Unable to clean up expired Expo task request '${request.id}': ${String(error)}`);
            }
            continue;
          }

          this.claimedIds.add(request.id);

          try {
            const consumer = ExpoTaskManagerRegistry.consumer(request.taskType);
            if (consumer === undefined || consumer.consumerId !== request.consumerId || consumer.consumerVersion !== request.consumerVersion) {
              await this.expirePendingExecution(request);
              continue;
            }
            let results: ExpoTaskExecutionResult[];
            if (request.phase === REQUEST_PHASE_FINISHING) {
              results = request.results ?? [];
            } else {
              const executionResults = await this.executeTaskType(
                request.taskType,
                true,
                request.id,
                request.taskName,
                request.data,
                request.error,
                request.expiresAt,
                request,
                ownerGeneration,
              );
              if (executionResults === undefined) {
                if (Date.now() >= request.expiresAt) await this.expirePendingExecution(request);
                continue;
              }
              results = executionResults;
              if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;
              if (!(await TaskManagerQueueRepository.markFinishing(app, request, results))) continue;
            }
            if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;
            await consumer.onExecutionFinished?.(this.context, results, request.id);
            if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;
            await TaskManagerQueueRepository.acknowledge(app, request, REQUEST_PHASE_FINISHING);
          } catch (error) {
            this.context.logger.error(`Unable to execute queued Expo task request '${request.id}': ${String(error)}`);
            this.scheduleRetry();
          } finally {
            this.claimedIds.delete(request.id);
          }
        }
      });

    this.draining = next;
    next.catch((error: Object): void => {
      this.context.logger.error(`Unable to execute queued Expo tasks: ${String(error)}`);
    });
  }

  private scheduleExpiry(signal: PendingExecutionSignal): void {
    if (signal.ownerKey !== this.owner || ExpoTaskManagerRegistry.ownerGeneration(this) === undefined) return;

    const requestId = signal.requestId;
    if (requestId === undefined) {
      this.expireTaskType(signal.taskType).catch((error: Object): void => {
        this.context.logger.error(`Unable to expire Expo tasks for '${signal.taskType}': ${String(error)}`);
      });
      return;
    }

    const app = this.context.uiAbilityContext.getApplicationContext();
    TaskManagerQueueRepository.markExpiring(app, this.owner, signal.taskType, requestId)
      .then((request): void => {
        if (request === undefined) return;
        this.expirePendingExecution(request).catch((error: Object): void => {
          this.context.logger.error(`Unable to expire Expo task request '${requestId}': ${String(error)}`);
          this.scheduleRetry();
        });
      })
      .catch((error: Object): void => {
        this.context.logger.error(`Unable to expire Expo task request '${requestId}': ${String(error)}`);
        this.scheduleRetry();
      });
  }

  private scheduleRetry(): void {
    if (this.destroyed || this.retryTimer >= 0) return;
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.scheduleDrain();
    }, QUEUE_RETRY_DELAY_MS);
  }
}

export interface ExpoTaskManagerRuntimeLoader {
  readonly ownerKey: string;
  isAvailable(): boolean;
  load(): Promise<void>;
}

export class ExpoTaskManagerRegistry {
  private static readonly consumers: Map<string, ExpoTaskConsumer> = new Map();
  private static readonly scopes: Map<number, ExpoTaskManagerScope> = new Map();
  private static readonly loaders: Map<string, ExpoTaskManagerRuntimeLoader> = new Map();
  private static readonly ownerRuntimeIds: Map<string, number> = new Map();
  private static readonly ownerGenerations: Map<string, number> = new Map();

  static registerConsumer(consumer: ExpoTaskConsumer): void {
    requireTaskType(consumer.taskType);
    requireConsumerId(consumer.consumerId);
    requireConsumerVersion(consumer.consumerVersion);
    if (ExpoTaskManagerRegistry.consumers.has(consumer.taskType)) {
      throw new ExpoTaskManagerError(
        'ERR_TASK_MANAGER_DUPLICATE_CONSUMER',
        `A Harmony native task consumer is already registered for '${consumer.taskType}'.`,
      );
    }

    ExpoTaskManagerRegistry.consumers.set(consumer.taskType, consumer);
    for (const scope of ExpoTaskManagerRegistry.scopes.values()) {
      scope.reconcileConsumer(consumer.taskType).catch((error: Object): void => {
        console.error(`Unable to reconcile Expo task consumer '${consumer.taskType}': ${String(error)}`);
      });
    }
  }

  static consumer(taskType: string): ExpoTaskConsumer | undefined {
    return ExpoTaskManagerRegistry.consumers.get(taskType);
  }

  static allConsumers(): ExpoTaskConsumer[] {
    return Array.from(ExpoTaskManagerRegistry.consumers.values());
  }

  static registerRuntimeLoader(loader: ExpoTaskManagerRuntimeLoader): void {
    const owner = requireOwnerKey(loader.ownerKey);
    if (ExpoTaskManagerRegistry.loaders.has(owner)) {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_DUPLICATE_LOADER', `A TaskManager runtime loader is already registered for '${owner}'.`);
    }
    ExpoTaskManagerRegistry.loaders.set(owner, loader);
  }

  static ownerKey(context: UITurboModuleContext): string {
    return runtimeOwnerKey(context);
  }

  static async ensureRuntime(ownerKey: string): Promise<void> {
    const owner = requireOwnerKey(ownerKey);
    if (ExpoTaskManagerRegistry.hasRuntime(owner)) return;
    const loader = ExpoTaskManagerRegistry.loaders.get(owner);
    if (loader === undefined || !loader.isAvailable()) {
      throw new ExpoTaskManagerError(
        'ERR_TASK_MANAGER_RUNTIME_UNAVAILABLE',
        `No live RNOH runtime or TaskManager runtime loader is available for '${owner}'.`,
      );
    }
    await loader.load();
    if (!ExpoTaskManagerRegistry.hasRuntime(owner)) {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_RUNTIME_LOAD_FAILED', `The TaskManager runtime loader did not attach '${owner}'.`);
    }
  }

  static attach(scope: ExpoTaskManagerScope): void {
    const existing = ExpoTaskManagerRegistry.scopes.get(scope.runtimeId());
    if (existing !== undefined && existing !== scope) existing.destroy();

    ExpoTaskManagerRegistry.scopes.set(scope.runtimeId(), scope);
    ExpoTaskManagerRegistry.refreshOwner(scope.ownerKey());
  }

  static detach(scope: ExpoTaskManagerScope): void {
    if (ExpoTaskManagerRegistry.scopes.get(scope.runtimeId()) === scope) {
      ExpoTaskManagerRegistry.scopes.delete(scope.runtimeId());
      ExpoTaskManagerRegistry.refreshOwner(scope.ownerKey());
    }
  }

  static ownerGeneration(scope: ExpoTaskManagerScope): number | undefined {
    ExpoTaskManagerRegistry.refreshOwner(scope.ownerKey());
    if (ExpoTaskManagerRegistry.primary(scope.ownerKey()) !== scope) return undefined;
    return ExpoTaskManagerRegistry.ownerGenerations.get(scope.ownerKey()) ?? 0;
  }

  static ownsQueue(scope: ExpoTaskManagerScope, generation: number): boolean {
    return (
      ExpoTaskManagerRegistry.primary(scope.ownerKey()) === scope && ExpoTaskManagerRegistry.ownerGenerations.get(scope.ownerKey()) === generation
    );
  }

  static ownerAvailabilityChanged(scope: ExpoTaskManagerScope): void {
    ExpoTaskManagerRegistry.refreshOwner(scope.ownerKey());
  }

  static async registerTask(context: UITurboModuleContext, taskName: string, taskType: string, options: ESObject): Promise<void> {
    await ExpoTaskManagerRegistry.requireScope(context).registerTask(
      requireTaskName(taskName),
      requireTaskType(taskType),
      requireObject(options, 'task options'),
    );
  }

  static async unregisterTask(context: UITurboModuleContext, taskName: string): Promise<void> {
    await ExpoTaskManagerRegistry.requireScope(context).unregisterTask(requireTaskName(taskName));
  }

  static async unregisterTaskForConsumer(context: UITurboModuleContext, taskName: string, taskType: string): Promise<void> {
    await ExpoTaskManagerRegistry.requireScope(context).unregisterTaskForConsumer(requireTaskName(taskName), requireTaskType(taskType));
  }

  static async isTaskRegistered(context: UITurboModuleContext, taskName: string): Promise<boolean> {
    return await ExpoTaskManagerRegistry.requireScope(context).isTaskRegistered(requireTaskName(taskName));
  }

  static async executeTaskType(
    context: UITurboModuleContext,
    taskType: string,
    allowForeground: boolean = false,
  ): Promise<ExpoTaskExecutionResult[]> {
    return (await ExpoTaskManagerRegistry.requireScope(context).executeTaskType(requireTaskType(taskType), allowForeground)) ?? [];
  }

  static async executeTask(
    context: UITurboModuleContext,
    taskName: string,
    data: ESObject,
    error: ESObject = null,
    allowForeground: boolean = false,
  ): Promise<ExpoTaskExecutionResult | undefined> {
    const name = requireTaskName(taskName);
    const payload: ESObject = requireObject(data, 'task execution data');
    if (error !== null) requireObject(error, 'task execution error');

    const results = await ExpoTaskManagerRegistry.requireScope(context).executeTask(name, payload, error, allowForeground);
    return results.length > 0 ? results[0] : undefined;
  }

  private static hasRuntime(ownerKey: string): boolean {
    for (const scope of ExpoTaskManagerRegistry.scopes.values()) {
      if (scope.ownerKey() === ownerKey) return true;
    }
    return false;
  }

  private static primary(ownerKey: string): ExpoTaskManagerScope | undefined {
    for (const scope of ExpoTaskManagerRegistry.scopes.values()) {
      if (scope.ownerKey() === ownerKey && scope.canOwnQueue() && scope.isForeground()) return scope;
    }
    for (const scope of ExpoTaskManagerRegistry.scopes.values()) {
      if (scope.ownerKey() === ownerKey && scope.canOwnQueue()) return scope;
    }
    return undefined;
  }

  private static refreshOwner(ownerKey: string): void {
    const primary = ExpoTaskManagerRegistry.primary(ownerKey);
    const nextRuntimeId = primary?.runtimeId() ?? -1;
    if (ExpoTaskManagerRegistry.ownerRuntimeIds.get(ownerKey) === nextRuntimeId) return;
    ExpoTaskManagerRegistry.ownerRuntimeIds.set(ownerKey, nextRuntimeId);
    ExpoTaskManagerRegistry.ownerGenerations.set(ownerKey, (ExpoTaskManagerRegistry.ownerGenerations.get(ownerKey) ?? 0) + 1);
    primary?.retryPendingExecutions();
  }

  private static requireScope(context: UITurboModuleContext): ExpoTaskManagerScope {
    const scope = ExpoTaskManagerRegistry.scopes.get(context.rnInstance.getId());
    if (scope === undefined) {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_SCOPE_NOT_FOUND', 'The Expo TaskManager Harmony runtime is not initialized.');
    }
    return scope;
  }
}

class ExpoTaskManagerService {
  readonly name: string = SERVICE_NAME;
  private readonly scope: ExpoTaskManagerScope;

  private constructor(scope: ExpoTaskManagerScope) {
    this.scope = scope;
  }

  static async create(context: UITurboModuleContext): Promise<ExpoTaskManagerService> {
    const repo = await TaskRepository.create(context.uiAbilityContext);
    const scope = new ExpoTaskManagerScope(context, repo);

    ExpoTaskManagerRegistry.attach(scope);
    try {
      await scope.reconcileConsumers();
    } catch (error) {
      scope.destroy();
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INITIALIZATION_FAILED', `Unable to restore native task consumers: ${errorDescription(error)}`);
    }

    return new ExpoTaskManagerService(scope);
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'isAvailableAsync') return true;
    if (method === 'startObserving') {
      this.scope.startObserving();
      return null;
    }
    if (method === 'stopObserving') {
      this.scope.stopObserving();
      return null;
    }
    if (method === 'notifyTaskFinishedAsync') {
      this.scope.notifyTaskFinished(requireTaskName(args[0]), requireObject(args[1], 'completion response'));
      return null;
    }
    if (method === 'isTaskRegisteredAsync') {
      return await this.scope.isTaskRegistered(requireTaskName(args[0]));
    }
    if (method === 'getTaskOptionsAsync') {
      return await this.scope.getTaskOptions(requireTaskName(args[0]));
    }
    if (method === 'getRegisteredTasksAsync') return await this.scope.getRegisteredTasks();
    if (method === 'unregisterTaskAsync') {
      await this.scope.unregisterTask(requireTaskName(args[0]));
      return null;
    }
    if (method === 'unregisterAllTasksAsync') {
      await this.scope.unregisterAllTasks();
      return null;
    }

    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_UNKNOWN_METHOD', `Unknown Expo TaskManager Harmony method '${method}'.`);
  }

  onDestroy(): void {
    this.scope.destroy();
  }
}

function requireTaskName(value: ESObject): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INVALID_TASK_NAME', 'TaskManager expected a non-empty string task name.');
  }
  return value;
}

function requireTaskType(value: ESObject): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INVALID_TASK_TYPE', 'TaskManager expected a non-empty string native task type.');
  }
  return value;
}

function requireRequestId(value: ESObject): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > MAXIMUM_REQUEST_ID_LENGTH || /[\u0000-\u001f]/.test(value)) {
    throw new ExpoTaskManagerError(
      'ERR_TASK_MANAGER_INVALID_REQUEST_ID',
      `TaskManager expected a request ID of 1-${MAXIMUM_REQUEST_ID_LENGTH} characters without control characters.`,
    );
  }
  return value;
}

function requireOwnerKey(value: ESObject): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 1024 || /[\u0000-\u001f]/.test(value)) {
    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INVALID_OWNER', 'TaskManager expected a stable non-empty application owner key.');
  }
  return value;
}

function requireConsumerId(value: ESObject): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INVALID_CONSUMER', 'TaskManager expected a stable non-empty consumer identity.');
  }
  return value;
}

function requireConsumerVersion(value: ESObject): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INVALID_CONSUMER', 'TaskManager expected a non-negative safe-integer consumer version.');
  }
  return value;
}

function requireExecutionDeadline(value: ESObject, createdAt: number): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < createdAt) {
    throw new ExpoTaskManagerError(
      'ERR_TASK_MANAGER_INVALID_DEADLINE',
      'TaskManager expected a safe-integer execution deadline at or after enqueue time.',
    );
  }
  return value;
}

function errorDescription(error: ESObject): string {
  if (error instanceof ExpoPlatformServiceError) return `${error.code}: ${error.message}`;
  if (error instanceof Error) return error.message;
  return String(error);
}

function requireObject(value: ESObject, label: string): ESObject {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INVALID_ARGUMENT', `TaskManager expected ${label} to be an object.`);
  }
  return value;
}

function runtimeOwnerKey(context: UITurboModuleContext): string {
  const bundleName = context.uiAbilityContext.abilityInfo.bundleName;
  const bundleUrl = context.rnInstance.getInitialBundleUrl();
  return requireOwnerKey(bundleUrl === undefined || bundleUrl.length === 0 ? bundleName : `${bundleName}#${bundleUrl}`);
}

function registerPackage(): void {
  if (packageRegistered) return;

  ExpoPlatformServiceRegistry.register(new ExpoTaskManagerServiceFactory());
  packageRegistered = true;
}

class ExpoTaskManagerServiceFactory implements ExpoPlatformServiceFactory {
  readonly name: string = SERVICE_NAME;

  async create(context: UITurboModuleContext): Promise<ExpoTaskManagerService> {
    return await ExpoTaskManagerService.create(context);
  }
}

export class ExpoTaskManagerPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerPackage();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-task-manager';
  }
}
