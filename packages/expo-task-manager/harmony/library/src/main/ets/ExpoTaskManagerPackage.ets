import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';

import {
  EXECUTION_REQUEST_SCHEMA_VERSION,
  REQUEST_PHASE_EXECUTING,
  REQUEST_PHASE_EXPIRING,
  REQUEST_PHASE_FINISHING,
  REQUEST_PHASE_QUEUED,
  TASK_RECORD_SCHEMA_VERSION,
  decodeExecutionRequest,
  decodeTaskRecords,
} from './TaskManagerStorageCodec.ts';

const MODULE_NAME: string = 'ExpoTaskManager';
const TASK_EVENT_NAME: string = 'TaskManager.executeTask';
const PREFERENCES_NAME: string = 'ExpoTaskManager';
const REGISTERED_TASKS_KEY: string = 'registeredTasks';
const REGISTRATION_GENERATIONS_KEY: string = 'registrationGenerations';
const PENDING_EXECUTION_KEY_PREFIX: string = 'pendingExecution.';
const CORRUPTED_REGISTERED_TASKS_KEY: string = 'corruptedRegisteredTasks';
const CORRUPTED_PENDING_EXECUTIONS_KEY: string = 'corruptedPendingExecutions';
const QUEUE_CHANGED_EVENT: string = 'expo.taskManager.pendingExecutionChanged';
const QUEUE_EXPIRED_EVENT: string = 'expo.taskManager.pendingExecutionExpired';
const WORK_METADATA_OWNER_PARAMETER: string = 'expo.taskManager.owner';
const WORK_METADATA_VERSION_PARAMETER: string = 'expo.taskManager.protocolVersion';
const WORK_METADATA_VERSION: number = 1;
const MAXIMUM_FUTURE_CLOCK_SKEW_MS: number = 5 * 60 * 1000;
const DEFAULT_DIRECT_EXECUTION_TIMEOUT_MS: number = 2 * 60 * 1000;
const QUEUE_RETRY_BASE_DELAY_MS: number = 1000;
const QUEUE_RETRY_MAX_DELAY_MS: number = 60 * 1000;
const MAXIMUM_REQUEST_ID_LENGTH: number = 128;
const MAXIMUM_SERIALIZED_REQUEST_LENGTH: number = 512 * 1024;
const MAXIMUM_CORRUPTION_DIAGNOSTICS: number = 20;

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
  onTasksChanged(context: ExpoModuleContext, tasks: ExpoTaskRecord[]): Promise<void>;
  onExecutionFinished?(context: ExpoModuleContext, results: ExpoTaskExecutionResult[], requestId?: string): Promise<void>;
  onExecutionExpired?(context: ExpoModuleContext, requestId?: string): Promise<void>;
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
  claimToken?: string;
  claimExpiresAt?: number;
  allowForeground: boolean;

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
    claimToken?: string,
    claimExpiresAt?: number,
    allowForeground: boolean = true,
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
    this.claimToken = claimToken;
    this.claimExpiresAt = claimExpiresAt;
    this.allowForeground = allowForeground;
  }
}

class PendingExecutionBatch {
  ready: PendingExecutionRequest[] = [];
  expired: PendingExecutionRequest[] = [];
  retryAt?: number;
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

class ExpoTaskManagerError extends ExpoModuleError {
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
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

class RegistrationGeneration {
  ownerKey: string;
  taskName: string;
  generation: number;

  constructor(ownerKey: string, taskName: string, generation: number) {
    this.ownerKey = ownerKey;
    this.taskName = taskName;
    this.generation = generation;
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

  async nextRegistrationGenerationLocked(ownerKey: string, taskName: string, current?: ExpoTaskRecord): Promise<number> {
    const generations = await this.readRegistrationGenerationsLocked();
    const existing = generations.find((item: RegistrationGeneration): boolean => {
      return item.ownerKey === ownerKey && item.taskName === taskName;
    });
    const generation = Math.max(existing?.generation ?? 0, current?.registrationGeneration ?? 0) + 1;
    if (!Number.isSafeInteger(generation)) {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_REGISTRATION_GENERATION', `Task '${taskName}' exhausted its registration generation range.`);
    }
    const next = generations.filter((item: RegistrationGeneration): boolean => {
      return item.ownerKey !== ownerKey || item.taskName !== taskName;
    });
    next.push(new RegistrationGeneration(ownerKey, taskName, generation));
    await this.store.put(REGISTRATION_GENERATIONS_KEY, JSON.stringify(next));
    return generation;
  }

  private async readRegistrationGenerationsLocked(): Promise<RegistrationGeneration[]> {
    const raw = await this.store.get(REGISTRATION_GENERATIONS_KEY, '[]');
    if (typeof raw !== 'string') return [];
    try {
      const parsed: ESObject = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      const generations: RegistrationGeneration[] = [];
      const values: ESObject[] = parsed as ESObject[];
      for (let index = 0; index < values.length; ++index) {
        const value: ESObject = values[index];
        if (value === null || typeof value !== 'object' || Array.isArray(value)) continue;
        const item = value as Record<string, ESObject>;
        if (
          typeof item['ownerKey'] !== 'string' ||
          item['ownerKey'].length === 0 ||
          typeof item['taskName'] !== 'string' ||
          item['taskName'].length === 0 ||
          typeof item['generation'] !== 'number' ||
          !Number.isSafeInteger(item['generation']) ||
          item['generation'] < 1
        )
          continue;
        generations.push(new RegistrationGeneration(item['ownerKey'], item['taskName'], item['generation']));
      }
      return generations;
    } catch (_) {
      return [];
    }
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

    const currentKey = request === undefined ? undefined : pendingExecutionKey(request.ownerKey, request.id);
    const legacyKey = request === undefined ? undefined : legacyPendingExecutionKey(request.ownerKey, request.id);
    if (request !== undefined && (key === currentKey || key === legacyKey)) {
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
        request.claimToken,
        request.claimExpiresAt,
        request.allowForeground,
      );
      requests.push(pending);
      if (key === legacyKey && currentKey !== undefined) {
        await savePendingExecution(store, pending);
        await store.delete(key);
        changed = true;
      }
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
  return `${PENDING_EXECUTION_KEY_PREFIX}${encodeURIComponent(ownerKey)}.${requestId}`;
}

function legacyPendingExecutionKey(ownerKey: string, requestId: string): string {
  let first = 0x811c9dc5;
  let second = 0x9e3779b9;
  for (let index = 0; index < ownerKey.length; ++index) {
    const code = ownerKey.charCodeAt(index);
    first = Math.imul(first ^ code, 0x01000193);
    second = Math.imul(second ^ code, 0x85ebca6b);
  }
  return `${PENDING_EXECUTION_KEY_PREFIX}${first >>> 0}-${second >>> 0}.${requestId}`;
}

function executionResults(values: ESObject[] | undefined): ExpoTaskExecutionResult[] | undefined {
  if (values === undefined) return undefined;
  return values.map((value: ESObject): ExpoTaskExecutionResult => {
    const record = value as Record<string, ESObject>;
    return new ExpoTaskExecutionResult(record['taskName'] as string, record['result']);
  });
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

export class ExpoTaskManagerWorkMetadata {
  static write(parameters: Record<string, number | string | boolean>, ownerKey: string): void {
    parameters[WORK_METADATA_OWNER_PARAMETER] = requireOwnerKey(ownerKey);
    parameters[WORK_METADATA_VERSION_PARAMETER] = WORK_METADATA_VERSION;
  }

  static owner(parameters?: Record<string, number | string | boolean>, allowLegacy: boolean = false): string | undefined {
    if (parameters === undefined) return undefined;
    const version = parameters?.[WORK_METADATA_VERSION_PARAMETER];
    if (version !== WORK_METADATA_VERSION && !(allowLegacy && version === undefined)) return undefined;
    const owner = parameters[WORK_METADATA_OWNER_PARAMETER];
    return typeof owner === 'string' && owner.length > 0 ? owner : undefined;
  }
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
    allowForeground: boolean = false,
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

      if (current !== undefined && !sameRequest(current, taskType, taskName, owner, expiresAt, data, error, allowForeground, target)) {
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
          REQUEST_PHASE_QUEUED,
          undefined,
          undefined,
          undefined,
          allowForeground,
        );

        await savePendingExecution(store, request);
      }
    });

    context.getApplicationContext().eventHub.emit(QUEUE_CHANGED_EVENT);
    try {
      await ExpoTaskManagerRegistry.ensureRuntime(owner);
    } catch (error) {
      // The durable commit is the success boundary. A live or subsequently
      // loaded RuntimeContext will drain the request before its deadline.
      console.warn(`Expo TaskManager queued '${requestId}' while its runtime is unavailable: ${String(error)}`);
    }

    return requestId;
  }

  static async expireRequest(context: common.Context, ownerKey: string, taskType: string, requestId: string): Promise<boolean> {
    requireTaskType(taskType);
    requireRequestId(requestId);
    const owner = requireOwnerKey(ownerKey);
    const request = await TaskManagerQueueRepository.markExpiring(context, owner, taskType, requestId);
    if (request === undefined) return false;
    emitExpiration(context, request);
    return true;
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
        if (request.phase === REQUEST_PHASE_FINISHING) {
          batch.ready.push(request);
        } else if (request.phase === REQUEST_PHASE_EXPIRING || request.expiresAt <= now || request.createdAt > now + MAXIMUM_FUTURE_CLOCK_SKEW_MS) {
          batch.expired.push(request);
        } else if (request.phase === REQUEST_PHASE_EXECUTING && (request.claimExpiresAt ?? request.expiresAt) > now) {
          const retryAt = request.claimExpiresAt ?? request.expiresAt;
          batch.retryAt = Math.min(batch.retryAt ?? retryAt, retryAt);
        } else {
          batch.ready.push(request);
        }
      }
    });

    return batch;
  }

  static async claim(context: common.Context, request: PendingExecutionRequest, claimToken: string): Promise<PendingExecutionRequest | undefined> {
    let claimed: PendingExecutionRequest | undefined;
    await TaskManagerStorageLock.serialize(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const requests = await readPendingExecutions(store);
      const current = requests.find((pending: PendingExecutionRequest): boolean => {
        return pending.id === request.id && pending.ownerKey === request.ownerKey;
      });
      if (current === undefined || !sameTarget(current, request)) return;
      const now = Date.now();
      if (current.expiresAt <= now) return;
      if (current.phase === REQUEST_PHASE_EXECUTING && current.claimToken !== claimToken && (current.claimExpiresAt ?? current.expiresAt) > now)
        return;
      if (current.phase !== REQUEST_PHASE_QUEUED && current.phase !== REQUEST_PHASE_EXECUTING) return;
      current.phase = REQUEST_PHASE_EXECUTING;
      current.claimToken = claimToken;
      current.claimExpiresAt = current.expiresAt;
      await savePendingExecution(store, current);
      claimed = current;
    });
    return claimed;
  }

  static async releaseClaim(context: common.Context, request: PendingExecutionRequest): Promise<void> {
    await TaskManagerStorageLock.serialize(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const requests = await readPendingExecutions(store);
      const current = requests.find((pending: PendingExecutionRequest): boolean => {
        return pending.id === request.id && pending.ownerKey === request.ownerKey;
      });
      if (
        current === undefined ||
        !sameTarget(current, request) ||
        current.phase !== REQUEST_PHASE_EXECUTING ||
        current.claimToken !== request.claimToken
      )
        return;
      current.phase = REQUEST_PHASE_QUEUED;
      current.claimToken = undefined;
      current.claimExpiresAt = undefined;
      await savePendingExecution(store, current);
    });
  }

  static async markFinishing(context: common.Context, request: PendingExecutionRequest, results: ExpoTaskExecutionResult[]): Promise<boolean> {
    let acquired = false;
    await TaskManagerStorageLock.serialize(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const requests = await readPendingExecutions(store);
      const current = requests.find((pending: PendingExecutionRequest): boolean => {
        return pending.id === request.id && pending.ownerKey === request.ownerKey;
      });
      if (current === undefined || !sameTarget(current, request)) return;
      if (current.phase === REQUEST_PHASE_EXPIRING) return;
      if (current.phase === REQUEST_PHASE_FINISHING) {
        acquired = true;
        return;
      }
      if (current.phase !== REQUEST_PHASE_EXECUTING || current.claimToken === undefined || current.claimToken !== request.claimToken) return;
      current.phase = REQUEST_PHASE_FINISHING;
      current.results = results;
      current.claimToken = undefined;
      current.claimExpiresAt = undefined;
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
      request.results = undefined;
      request.claimToken = undefined;
      request.claimExpiresAt = undefined;
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
      const current = requests.find((pending: PendingExecutionRequest): boolean => {
        return pending.id === request.id && pending.ownerKey === request.ownerKey;
      });
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

function taskMatchesConsumer(task: ExpoTaskRecord, consumer: ExpoTaskConsumer): boolean {
  return task.consumerId === consumer.consumerId && task.consumerVersion === consumer.consumerVersion;
}

function sameTaskRecord(left: ExpoTaskRecord, right: ExpoTaskRecord): boolean {
  return (
    left.ownerKey === right.ownerKey &&
    left.taskName === right.taskName &&
    left.taskType === right.taskType &&
    left.consumerId === right.consumerId &&
    left.consumerVersion === right.consumerVersion &&
    left.registrationGeneration === right.registrationGeneration &&
    serializedEquals(left.options, right.options)
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
  allowForeground: boolean,
  target: QueueTarget,
): boolean {
  return (
    current.phase !== REQUEST_PHASE_EXPIRING &&
    current.taskType === taskType &&
    current.taskName === taskName &&
    current.ownerKey === ownerKey &&
    current.expiresAt === expiresAt &&
    current.consumerId === target.consumerId &&
    current.consumerVersion === target.consumerVersion &&
    current.registrationGeneration === target.registrationGeneration &&
    current.allowForeground === allowForeground &&
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
  private readonly context: ExpoModuleContext;
  private readonly repository: TaskRepository;
  private readonly owner: string;
  private readonly activeExecutions: Map<string, ActiveTaskExecution> = new Map();
  private readonly queuedEvents: TaskExecutionBody[] = [];
  private readonly claimedIds: Set<string> = new Set();
  private readonly expirations: Map<string, Promise<void>> = new Map();
  private readonly consumerFailures: Map<string, string> = new Map();
  private readonly queueListener: () => void;
  private readonly expiryListener: (signal: PendingExecutionSignal) => void;
  private observing: boolean = false;
  private foreground: boolean;
  private destroyed: boolean = false;
  private retryTimer: number = -1;
  private retryAttempt: number = 0;
  private draining: Promise<void> = Promise.resolve();

  constructor(context: ExpoModuleContext, repository: TaskRepository) {
    this.context = context;
    this.repository = repository;
    this.owner = runtimeOwnerKey(context);
    this.foreground = context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND;
    this.queueListener = (): void => this.scheduleDrain();
    this.expiryListener = (signal: PendingExecutionSignal): void => this.scheduleExpiry(signal);

    const eventHub = context.uiAbilityContext.getApplicationContext().eventHub;
    eventHub.on(QUEUE_CHANGED_EVENT, this.queueListener);
    eventHub.on(QUEUE_EXPIRED_EVENT, this.expiryListener);
  }

  runtimeId(): number {
    return this.context.runtimeId;
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

  onForeground(): void {
    if (this.destroyed) return;
    this.foreground = true;
    ExpoTaskManagerRegistry.ownerAvailabilityChanged(this);
  }

  onBackground(): void {
    if (this.destroyed) return;
    this.foreground = false;
    ExpoTaskManagerRegistry.ownerAvailabilityChanged(this);
    this.scheduleDrain();
  }

  async reconcileConsumers(): Promise<void> {
    const tasks = await this.repository.readTasks();
    for (const task of tasks) {
      if (task.ownerKey !== this.owner) continue;
      const consumer = ExpoTaskManagerRegistry.consumer(task.taskType);
      if (consumer === undefined) {
        this.consumerFailures.set(task.taskType, `Native consumer '${task.taskType}' is unavailable.`);
      } else if (!taskMatchesConsumer(task, consumer)) {
        this.consumerFailures.set(task.taskType, `Native consumer '${task.taskType}' changed incompatibly.`);
      }
    }

    for (const consumer of ExpoTaskManagerRegistry.allConsumers()) {
      try {
        await this.notifyConsumer(consumer.taskType, tasks);
        const incompatible = tasks.some((task: ExpoTaskRecord): boolean => {
          return task.ownerKey === this.owner && task.taskType === consumer.taskType && !taskMatchesConsumer(task, consumer);
        });
        if (!incompatible) this.consumerFailures.delete(consumer.taskType);
      } catch (error) {
        const message = errorDescription(error);
        this.consumerFailures.set(consumer.taskType, message);
        this.context.logger.error(`Unable to restore Expo task consumer '${consumer.taskType}': ${message}`);
      }
    }
  }

  async reconcileConsumer(_taskType: string): Promise<void> {
    await this.reconcileConsumers();
  }

  async registerTask(taskName: string, taskType: string, options: ESObject): Promise<void> {
    let tasks: ExpoTaskRecord[] = [];
    let next: ExpoTaskRecord[] = [];
    let current: ExpoTaskRecord | undefined;
    let registered: ExpoTaskRecord | undefined;
    await TaskRepository.serialize(async (): Promise<void> => {
      tasks = await this.repository.readTasksLocked();
      const index = tasks.findIndex((task: ExpoTaskRecord): boolean => task.ownerKey === this.owner && task.taskName === taskName);
      current = index >= 0 ? tasks[index] : undefined;
      const consumer = ExpoTaskManagerRegistry.consumer(taskType);
      if (consumer === undefined) {
        throw new ExpoTaskManagerError('ERR_TASK_MANAGER_CONSUMER_NOT_FOUND', `No Harmony native task consumer is registered for '${taskType}'.`);
      }

      const generation = await this.repository.nextRegistrationGenerationLocked(this.owner, taskName, current);
      next = tasks.filter((task: ExpoTaskRecord): boolean => task.ownerKey !== this.owner || task.taskName !== taskName);
      registered = new ExpoTaskRecord(taskName, taskType, options, this.owner, consumer.consumerId, consumer.consumerVersion, generation);
      next.push(registered);

      await this.repository.writeTasks(next);
    });

    try {
      if (current !== undefined && current.taskType !== taskType) {
        await this.notifyConsumer(current.taskType, next);
      }
      await this.notifyConsumer(taskType, next, true);
    } catch (error) {
      let rolledBack = false;
      await TaskRepository.serialize(async (): Promise<void> => {
        const latest = await this.repository.readTasksLocked();
        const candidate = latest.find((task: ExpoTaskRecord): boolean => task.ownerKey === this.owner && task.taskName === taskName);
        if (registered === undefined || candidate === undefined || !sameTaskRecord(candidate, registered)) return;
        const rollback = latest.filter((task: ExpoTaskRecord): boolean => task.ownerKey !== this.owner || task.taskName !== taskName);
        if (current !== undefined) rollback.push(current);
        await this.repository.writeTasks(rollback);
        rolledBack = true;
      });

      if (rolledBack) {
        const types = current !== undefined && current.taskType !== taskType ? [current.taskType, taskType] : [taskType];
        for (const type of types) {
          try {
            await this.notifyConsumer(type, tasks);
          } catch (rollback) {
            this.context.logger.error(`Unable to restore native consumer '${type}' after registration failed: ${String(rollback)}`);
          }
        }
      }

      throw new ExpoTaskManagerError(
        'ERR_TASK_MANAGER_REGISTRATION_FAILED',
        `Unable to activate native consumer '${taskType}' for task '${taskName}': ${errorDescription(error)}`,
      );
    }

    if (current !== undefined && current.taskType !== taskType) this.abortExecutionsForTask(taskName);
  }

  async unregisterTask(taskName: string): Promise<void> {
    await this.unregisterTaskInternal(taskName);
  }

  async unregisterTaskForConsumer(taskName: string, taskType: string): Promise<void> {
    await this.unregisterTaskInternal(taskName, taskType);
  }

  async unregisterAllTasks(): Promise<void> {
    let tasks: ExpoTaskRecord[] = [];
    let owned: ExpoTaskRecord[] = [];
    let next: ExpoTaskRecord[] = [];
    await TaskRepository.serialize(async (): Promise<void> => {
      tasks = await this.repository.readTasksLocked();
      owned = tasks.filter((task: ExpoTaskRecord): boolean => task.ownerKey === this.owner);
      if (owned.length === 0) return;
      next = tasks.filter((task: ExpoTaskRecord): boolean => task.ownerKey !== this.owner);
      await this.repository.writeTasks(next);
    });
    if (owned.length === 0) return;

    const types: string[] = [];
    for (const task of owned) if (!types.includes(task.taskType)) types.push(task.taskType);
    try {
      for (const taskType of types) await this.notifyConsumer(taskType, next);
    } catch (error) {
      let rolledBack = false;
      await TaskRepository.serialize(async (): Promise<void> => {
        const latest = await this.repository.readTasksLocked();
        if (latest.some((task: ExpoTaskRecord): boolean => task.ownerKey === this.owner)) return;
        await this.repository.writeTasks([...latest, ...owned]);
        rolledBack = true;
      });

      if (rolledBack) {
        for (const taskType of types) {
          try {
            await this.notifyConsumer(taskType, tasks);
          } catch (rollback) {
            this.context.logger.error(`Unable to restore native consumer '${taskType}' after unregistering all tasks failed: ${String(rollback)}`);
          }
        }
      }

      throw new ExpoTaskManagerError(
        'ERR_TASK_MANAGER_UNREGISTRATION_FAILED',
        `Unable to deactivate all native task consumers: ${errorDescription(error)}`,
      );
    }

    this.abortAllExecutions();
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
          task.ownerKey === this.owner &&
          task.taskType === taskType &&
          taskMatchesConsumer(task, consumer) &&
          (taskName === undefined || task.taskName === taskName),
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

    const eventHub = this.context.uiAbilityContext.getApplicationContext().eventHub;
    eventHub.off(QUEUE_CHANGED_EVENT, this.queueListener);
    eventHub.off(QUEUE_EXPIRED_EVENT, this.expiryListener);

    this.abortAllExecutions();
    ExpoTaskManagerRegistry.detach(this);
  }

  private async unregisterTaskInternal(taskName: string, expectedTaskType?: string): Promise<void> {
    let tasks: ExpoTaskRecord[] = [];
    let task: ExpoTaskRecord | undefined;
    let next: ExpoTaskRecord[] = [];
    await TaskRepository.serialize(async (): Promise<void> => {
      tasks = await this.repository.readTasksLocked();
      task = tasks.find((item: ExpoTaskRecord): boolean => item.ownerKey === this.owner && item.taskName === taskName);

      if (task === undefined) {
        throw new ExpoTaskManagerError('ERR_TASK_MANAGER_TASK_NOT_FOUND', `Task '${taskName}' is not registered.`);
      }

      if (expectedTaskType !== undefined && task.taskType !== expectedTaskType) {
        throw new ExpoTaskManagerError(
          'ERR_TASK_MANAGER_TASK_CONFLICT',
          `Task '${taskName}' belongs to native consumer '${task.taskType}', not '${expectedTaskType}'.`,
        );
      }

      next = tasks.filter((item: ExpoTaskRecord): boolean => item.ownerKey !== this.owner || item.taskName !== taskName);
      await this.repository.writeTasks(next);
    });
    const removed = task as ExpoTaskRecord;

    try {
      await this.notifyConsumer(removed.taskType, next);
    } catch (error) {
      let rolledBack = false;
      await TaskRepository.serialize(async (): Promise<void> => {
        const latest = await this.repository.readTasksLocked();
        if (latest.some((item: ExpoTaskRecord): boolean => item.ownerKey === this.owner && item.taskName === taskName)) return;
        await this.repository.writeTasks([...latest, removed]);
        rolledBack = true;
      });

      if (rolledBack) {
        try {
          await this.notifyConsumer(removed.taskType, tasks);
        } catch (rollback) {
          this.context.logger.error(`Unable to restore native consumer '${removed.taskType}' after unregistration failed: ${String(rollback)}`);
        }
      }

      throw new ExpoTaskManagerError(
        'ERR_TASK_MANAGER_UNREGISTRATION_FAILED',
        `Unable to deactivate native consumer '${removed.taskType}' for task '${taskName}': ${errorDescription(error)}`,
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
      tasks.filter((task: ExpoTaskRecord): boolean => {
        return task.ownerKey === this.owner && task.taskType === taskType && taskMatchesConsumer(task, consumer);
      }),
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
    this.context.sendEvent(TASK_EVENT_NAME, body);
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
            this.scheduleRetry();
          }
        }

        if (batch.retryAt !== undefined) this.scheduleRetry(Math.max(0, batch.retryAt - Date.now()));

        for (const request of batch.ready) {
          if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;
          if (this.claimedIds.has(request.id)) continue;

          const now = Date.now();
          if (request.phase !== REQUEST_PHASE_FINISHING && (request.expiresAt <= now || request.createdAt > now + MAXIMUM_FUTURE_CLOCK_SKEW_MS)) {
            try {
              await this.expirePendingExecution(request);
            } catch (error) {
              this.context.logger.error(`Unable to clean up expired Expo task request '${request.id}': ${String(error)}`);
              this.scheduleRetry();
            }
            continue;
          }

          this.claimedIds.add(request.id);
          let claimed: PendingExecutionRequest | undefined;

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
              if (this.foreground && !request.allowForeground) continue;
              claimed = await TaskManagerQueueRepository.claim(app, request, util.generateRandomUUID(true));
              if (claimed === undefined) continue;
              const executionResults = await this.executeTaskType(
                claimed.taskType,
                claimed.allowForeground,
                claimed.id,
                claimed.taskName,
                claimed.data,
                claimed.error,
                claimed.expiresAt,
                claimed,
                ownerGeneration,
              );
              if (executionResults === undefined) {
                if (Date.now() >= claimed.expiresAt) await this.expirePendingExecution(claimed);
                continue;
              }
              results = executionResults;
              if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;
              if (!(await TaskManagerQueueRepository.markFinishing(app, claimed, results))) continue;
            }
            if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;
            await consumer.onExecutionFinished?.(this.context, results, request.id);
            if (!ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) return;
            await TaskManagerQueueRepository.acknowledge(app, request, REQUEST_PHASE_FINISHING);
          } catch (error) {
            this.context.logger.error(`Unable to execute queued Expo task request '${request.id}': ${String(error)}`);
            if (claimed !== undefined && ExpoTaskManagerRegistry.ownsQueue(this, ownerGeneration)) {
              try {
                await TaskManagerQueueRepository.releaseClaim(app, claimed);
              } catch (releaseError) {
                this.context.logger.error(`Unable to release Expo task claim '${request.id}': ${String(releaseError)}`);
              }
            }
            this.scheduleRetry();
          } finally {
            this.claimedIds.delete(request.id);
          }
        }
        if (this.retryTimer < 0) this.retryAttempt = 0;
      });

    this.draining = next;
    next.catch((error: Object): void => {
      this.context.logger.error(`Unable to execute queued Expo tasks: ${String(error)}`);
      this.scheduleRetry();
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

  private scheduleRetry(minimumDelay: number = 0): void {
    if (this.destroyed || this.retryTimer >= 0) return;
    const exponential = Math.min(QUEUE_RETRY_MAX_DELAY_MS, QUEUE_RETRY_BASE_DELAY_MS * Math.pow(2, this.retryAttempt));
    const jittered = Math.round(exponential * (0.8 + Math.random() * 0.4));
    const delay = Math.max(minimumDelay, jittered);
    this.retryAttempt = Math.min(this.retryAttempt + 1, 16);
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.scheduleDrain();
    }, delay);
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
  private static readonly runtimeLoads: Map<string, Promise<void>> = new Map();
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

  static unregisterRuntimeLoader(loader: ExpoTaskManagerRuntimeLoader): void {
    const owner = requireOwnerKey(loader.ownerKey);
    if (ExpoTaskManagerRegistry.loaders.get(owner) === loader) ExpoTaskManagerRegistry.loaders.delete(owner);
  }

  static canEnsureRuntime(ownerKey: string): boolean {
    const owner = requireOwnerKey(ownerKey);
    if (ExpoTaskManagerRegistry.hasRuntime(owner)) return true;
    return ExpoTaskManagerRegistry.loaders.get(owner)?.isAvailable() === true;
  }

  static canEnsureRuntimeForContext(context: ExpoModuleContext): boolean {
    const owner = runtimeOwnerKey(context);
    if (ExpoTaskManagerRegistry.canEnsureRuntime(owner)) return true;
    return context.getModule(MODULE_NAME) instanceof ExpoTaskManagerModule;
  }

  static hasRuntimeLoader(ownerKey: string): boolean {
    const owner = requireOwnerKey(ownerKey);
    return ExpoTaskManagerRegistry.loaders.get(owner)?.isAvailable() === true;
  }

  static ownerKey(context: ExpoModuleContext): string {
    return runtimeOwnerKey(context);
  }

  static async ensureRuntime(ownerKey: string): Promise<void> {
    const owner = requireOwnerKey(ownerKey);
    if (ExpoTaskManagerRegistry.hasRuntime(owner)) return;
    const existing = ExpoTaskManagerRegistry.runtimeLoads.get(owner);
    if (existing !== undefined) return await existing;
    const loader = ExpoTaskManagerRegistry.loaders.get(owner);
    if (loader === undefined || !loader.isAvailable()) {
      throw new ExpoTaskManagerError(
        'ERR_TASK_MANAGER_RUNTIME_UNAVAILABLE',
        `No live RNOH runtime or TaskManager runtime loader is available for '${owner}'.`,
      );
    }
    const pending = (async (): Promise<void> => {
      await loader.load();
      if (!ExpoTaskManagerRegistry.hasRuntime(owner)) {
        throw new ExpoTaskManagerError('ERR_TASK_MANAGER_RUNTIME_LOAD_FAILED', `The TaskManager runtime loader did not attach '${owner}'.`);
      }
    })();
    ExpoTaskManagerRegistry.runtimeLoads.set(owner, pending);
    try {
      await pending;
    } finally {
      if (ExpoTaskManagerRegistry.runtimeLoads.get(owner) === pending) ExpoTaskManagerRegistry.runtimeLoads.delete(owner);
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

  static async registerTask(context: ExpoModuleContext, taskName: string, taskType: string, options: ESObject): Promise<void> {
    await (
      await ExpoTaskManagerRegistry.requireScope(context)
    ).registerTask(requireTaskName(taskName), requireTaskType(taskType), requireObject(options, 'task options'));
  }

  static async unregisterTask(context: ExpoModuleContext, taskName: string): Promise<void> {
    await (await ExpoTaskManagerRegistry.requireScope(context)).unregisterTask(requireTaskName(taskName));
  }

  static async unregisterTaskForConsumer(context: ExpoModuleContext, taskName: string, taskType: string): Promise<void> {
    await (await ExpoTaskManagerRegistry.requireScope(context)).unregisterTaskForConsumer(requireTaskName(taskName), requireTaskType(taskType));
  }

  static async isTaskRegistered(context: ExpoModuleContext, taskName: string): Promise<boolean> {
    return await (await ExpoTaskManagerRegistry.requireScope(context)).isTaskRegistered(requireTaskName(taskName));
  }

  static async executeTaskType(context: ExpoModuleContext, taskType: string, allowForeground: boolean = false): Promise<ExpoTaskExecutionResult[]> {
    return (await (await ExpoTaskManagerRegistry.requireScope(context)).executeTaskType(requireTaskType(taskType), allowForeground)) ?? [];
  }

  static async executeTask(
    context: ExpoModuleContext,
    taskName: string,
    data: ESObject,
    error: ESObject = null,
    allowForeground: boolean = false,
  ): Promise<ExpoTaskExecutionResult | undefined> {
    const name = requireTaskName(taskName);
    const payload: ESObject = requireObject(data, 'task execution data');
    if (error !== null) requireObject(error, 'task execution error');

    const results = await (await ExpoTaskManagerRegistry.requireScope(context)).executeTask(name, payload, error, allowForeground);
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

  private static async requireScope(context: ExpoModuleContext): Promise<ExpoTaskManagerScope> {
    const scope = ExpoTaskManagerRegistry.scopes.get(context.runtimeId);
    if (scope !== undefined) return scope;
    const module = context.getModule(MODULE_NAME);
    if (!(module instanceof ExpoTaskManagerModule)) {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_SCOPE_NOT_FOUND', 'The Expo TaskManager Harmony runtime is not initialized.');
    }
    return await module.scopeForRegistry();
  }
}

class TaskCompletionResponse {
  eventId: string;
  result: ESObject;

  constructor(eventId: string, result: ESObject) {
    this.eventId = eventId;
    this.result = result;
  }
}

const TASK_COMPLETION_RESPONSE_TYPE: ExpoValueType<TaskCompletionResponse> = new ExpoValueType<TaskCompletionResponse>(
  'TaskManager completion response',
  (value: ESObject): TaskCompletionResponse => {
    const response: ESObject = requireObject(value, 'completion response');
    if (typeof response.eventId !== 'string' || response.eventId.length === 0) {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INVALID_RESPONSE', 'TaskManager completion response must contain a non-empty string eventId.');
    }
    return new TaskCompletionResponse(response.eventId, response.result ?? null);
  },
  (value: TaskCompletionResponse): ESObject => value,
);

/** ArkTS author implementation of Expo's TaskManager native module. */
export class ExpoTaskManagerModule extends ExpoModule {
  private scope?: ExpoTaskManagerScope = undefined;
  private scopePromise?: Promise<ExpoTaskManagerScope> = undefined;
  private observing: boolean = false;
  private foreground: boolean;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.foreground = context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND;
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name(MODULE_NAME)
      .events([TASK_EVENT_NAME])
      .constant('EVENT_NAME', TASK_EVENT_NAME)
      .asyncFunction('isAvailableAsync', ExpoFunction.typed0(async (): Promise<boolean> => true).returns(ExpoValueTypes.boolean()))
      .asyncFunction(
        'notifyTaskFinishedAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          TASK_COMPLETION_RESPONSE_TYPE,
          async (taskName: string, response: TaskCompletionResponse): Promise<void> => {
            (await this.scopeForRegistry()).notifyTaskFinished(taskName, response);
          },
        ),
      )
      .asyncFunction(
        'isTaskRegisteredAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (taskName: string): Promise<boolean> => {
          return await (await this.scopeForRegistry()).isTaskRegistered(taskName);
        }).returns(ExpoValueTypes.boolean()),
      )
      .asyncFunction(
        'getTaskOptionsAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (taskName: string): Promise<ESObject> => {
          return await (await this.scopeForRegistry()).getTaskOptions(taskName);
        }),
      )
      .asyncFunction(
        'getRegisteredTasksAsync',
        ExpoFunction.typed0(async (): Promise<ExpoTaskPublicRecord[]> => {
          return await (await this.scopeForRegistry()).getRegisteredTasks();
        }),
      )
      .asyncFunction(
        'unregisterTaskAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (taskName: string): Promise<void> => {
          await (await this.scopeForRegistry()).unregisterTask(taskName);
        }),
      )
      .asyncFunction(
        'unregisterAllTasksAsync',
        ExpoFunction.typed0(async (): Promise<void> => {
          await (await this.scopeForRegistry()).unregisterAllTasks();
        }),
      )
      .onCreate((): void => {
        this.initialize().catch((error: Object): void => {
          this.context.logger.error(`Unable to initialize Expo TaskManager: ${String(error)}`);
        });
      })
      .onStartObserving(TASK_EVENT_NAME, (): void => this.setObserving(true))
      .onStopObserving(TASK_EVENT_NAME, (): void => this.setObserving(false))
      .onForeground((): void => this.setForeground(true))
      .onBackground((): void => this.setForeground(false))
      .onDestroy((): void => this.destroy());
  }

  /** @internal Used by the background task consumers in this Host/runtime. */
  async scopeForRegistry(): Promise<ExpoTaskManagerScope> {
    return await this.initialize();
  }

  private initialize(): Promise<ExpoTaskManagerScope> {
    if (this.destroyed) {
      return Promise.reject(new ExpoTaskManagerError('ERR_TASK_MANAGER_SCOPE_DESTROYED', 'The Expo TaskManager Harmony runtime has been destroyed.'));
    }
    if (this.scopePromise !== undefined) return this.scopePromise;
    const pending = this.createScope();
    this.scopePromise = pending;
    pending.catch((): void => {
      if (this.scopePromise === pending && this.scope === undefined && !this.destroyed) this.scopePromise = undefined;
    });
    return pending;
  }

  private async createScope(): Promise<ExpoTaskManagerScope> {
    const repository = await TaskRepository.create(this.context.uiAbilityContext);
    if (this.destroyed) {
      throw new ExpoTaskManagerError('ERR_TASK_MANAGER_SCOPE_DESTROYED', 'The Expo TaskManager Harmony runtime was destroyed during initialization.');
    }
    const scope = new ExpoTaskManagerScope(this.context, repository);
    ExpoTaskManagerRegistry.attach(scope);
    try {
      await scope.reconcileConsumers();
      if (this.destroyed) {
        scope.destroy();
        throw new ExpoTaskManagerError(
          'ERR_TASK_MANAGER_SCOPE_DESTROYED',
          'The Expo TaskManager Harmony runtime was destroyed during initialization.',
        );
      }
      this.scope = scope;
      if (this.foreground) scope.onForeground();
      else scope.onBackground();
      if (this.observing) scope.startObserving();
      return scope;
    } catch (error) {
      scope.destroy();
      if (error instanceof ExpoTaskManagerError) throw error;
      throw new ExpoTaskManagerError(
        'ERR_TASK_MANAGER_INITIALIZATION_FAILED',
        `Unable to restore native task consumers: ${errorDescription(error as ESObject)}`,
        error as Object,
      );
    }
  }

  private setObserving(observing: boolean): void {
    if (this.destroyed) return;
    this.observing = observing;
    if (observing) {
      this.initialize()
        .then((scope: ExpoTaskManagerScope): void => scope.startObserving())
        .catch((error: Object): void => {
          this.context.logger.error(`Unable to start observing Expo TaskManager: ${String(error)}`);
        });
    } else {
      this.scope?.stopObserving();
    }
  }

  private setForeground(foreground: boolean): void {
    if (this.destroyed) return;
    this.foreground = foreground;
    if (foreground) this.scope?.onForeground();
    else this.scope?.onBackground();
  }

  private destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.observing = false;
    this.scope?.destroy();
    this.scope = undefined;
    this.scopePromise = undefined;
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
  if (error instanceof ExpoModuleError) return `${error.code}: ${error.message}`;
  if (error instanceof Error) return error.message;
  return String(error);
}

function requireObject(value: ESObject, label: string): ESObject {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoTaskManagerError('ERR_TASK_MANAGER_INVALID_ARGUMENT', `TaskManager expected ${label} to be an object.`);
  }
  return value;
}

function runtimeOwnerKey(context: ExpoModuleContext): string {
  const bundleName = context.uiAbilityContext.abilityInfo.bundleName;
  return requireOwnerKey(bundleName);
}
