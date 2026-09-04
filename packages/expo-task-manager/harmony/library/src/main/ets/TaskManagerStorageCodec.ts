export const TASK_RECORD_SCHEMA_VERSION: number = 2;
export const EXECUTION_REQUEST_SCHEMA_VERSION: number = 2;

export const REQUEST_PHASE_QUEUED: string = 'queued';
export const REQUEST_PHASE_EXECUTING: string = 'executing';
export const REQUEST_PHASE_FINISHING: string = 'finishing';
export const REQUEST_PHASE_EXPIRING: string = 'expiring';

export class StoredTaskRecord {
  version: number;
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
    version: number = TASK_RECORD_SCHEMA_VERSION,
  ) {
    this.version = version;
    this.taskName = taskName;
    this.taskType = taskType;
    this.options = options;
    this.ownerKey = ownerKey;
    this.consumerId = consumerId;
    this.consumerVersion = consumerVersion;
    this.registrationGeneration = registrationGeneration;
  }
}

export class StoredExecutionRequest {
  version: number;
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
  results?: ESObject[];
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
    results?: ESObject[],
    claimToken?: string,
    claimExpiresAt?: number,
    allowForeground: boolean = true,
    version: number = EXECUTION_REQUEST_SCHEMA_VERSION,
  ) {
    this.version = version;
    this.id = id;
    this.taskType = taskType;
    this.createdAt = createdAt;
    this.taskName = taskName;
    this.expiresAt = expiresAt;
    this.data = data;
    this.error = error;
    this.ownerKey = ownerKey;
    this.consumerId = consumerId;
    this.consumerVersion = consumerVersion;
    this.registrationGeneration = registrationGeneration;
    this.phase = phase;
    this.results = results;
    this.claimToken = claimToken;
    this.claimExpiresAt = claimExpiresAt;
    this.allowForeground = allowForeground;
  }
}

export class DecodeResult<T> {
  values: T[];
  corrupted: boolean;

  constructor(values: T[], corrupted: boolean) {
    this.values = values;
    this.corrupted = corrupted;
  }
}

export function decodeTaskRecords(raw: ESObject): DecodeResult<StoredTaskRecord> {
  const data = decodeArray(raw);
  if (data === undefined) return new DecodeResult([], true);

  const tasks: StoredTaskRecord[] = [];
  const taskIndex: Map<string, number> = new Map();
  let corrupted = false;

  for (const value of data) {
    const item = asRecord(value);
    if (item === undefined) {
      corrupted = true;
      continue;
    }

    const name = item['taskName'];
    const type = item['taskType'];
    const options = item['options'];
    const version = item['version'];
    const ownerKey = item['ownerKey'];
    const consumerId = item['consumerId'];
    const consumerVersion = item['consumerVersion'];
    const generation = item['registrationGeneration'];
    if (
      typeof name !== 'string'
      || name.length === 0
      || typeof type !== 'string'
      || type.length === 0
      || asRecord(options) === undefined
      || version !== TASK_RECORD_SCHEMA_VERSION
      || typeof ownerKey !== 'string'
      || ownerKey.length === 0
      || typeof consumerId !== 'string'
      || consumerId.length === 0
      || !isNonNegativeInteger(consumerVersion)
      || typeof generation !== 'number'
      || !Number.isSafeInteger(generation)
      || generation < 1
    ) {
      corrupted = true;
      continue;
    }

    const task = new StoredTaskRecord(
      name,
      type,
      options,
      ownerKey,
      consumerId,
      consumerVersion,
      generation,
    );
    const identity = `${task.ownerKey}\u0000${name}`;
    const existingIndex = taskIndex.get(identity);
    if (existingIndex !== undefined) {
      tasks[existingIndex] = task;
      corrupted = true;
    } else {
      taskIndex.set(identity, tasks.length);
      tasks.push(task);
    }
  }

  return new DecodeResult(tasks, corrupted);
}

export function decodeExecutionRequest(raw: ESObject): StoredExecutionRequest | undefined {
  if (typeof raw !== 'string') return undefined;
  try {
    return executionRequestFromValue(JSON.parse(raw));
  } catch (_) {
    return undefined;
  }
}

function decodeArray(raw: ESObject): ESObject[] | undefined {
  if (typeof raw !== 'string') return undefined;
  try {
    const value: ESObject = JSON.parse(raw);
    return Array.isArray(value) ? value : undefined;
  } catch (_) {
    return undefined;
  }
}

function asRecord(value: ESObject): Record<string, ESObject> | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  return value as Record<string, ESObject>;
}

function isNonNegativeInteger(value: ESObject): boolean {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function executionRequestFromValue(value: ESObject): StoredExecutionRequest | undefined {
  const item = asRecord(value);
  if (item === undefined) return undefined;

  const id = item['id'];
  const type = item['taskType'];
  const name = item['taskName'];
  const createdAt = item['createdAt'];
  const version = item['version'];
  const expiresAt = item['expiresAt'];
  const data = item['data'];
  const error = item['error'];
  const ownerKey = item['ownerKey'];
  const consumerId = item['consumerId'];
  const consumerVersion = item['consumerVersion'];
  const generation = item['registrationGeneration'];
  const phase = item['phase'];
  const results = item['results'];
  const claimToken = item['claimToken'];
  const claimExpiresAt = item['claimExpiresAt'];
  const allowForeground = item['allowForeground'];
  if (
    typeof id !== 'string'
    || id.length === 0
    || typeof type !== 'string'
    || type.length === 0
    || (name !== undefined && (typeof name !== 'string' || name.length === 0))
    || typeof createdAt !== 'number'
    || !Number.isSafeInteger(createdAt)
    || createdAt < 0
    || version !== EXECUTION_REQUEST_SCHEMA_VERSION
    || typeof expiresAt !== 'number'
    || !Number.isSafeInteger(expiresAt)
    || expiresAt < createdAt
    || asRecord(data) === undefined
    || (error !== null && asRecord(error) === undefined)
    || typeof ownerKey !== 'string'
    || ownerKey.length === 0
    || typeof consumerId !== 'string'
    || consumerId.length === 0
    || !isNonNegativeInteger(consumerVersion)
    || !isNonNegativeInteger(generation)
    || (allowForeground !== undefined && typeof allowForeground !== 'boolean')
    || (
      phase !== REQUEST_PHASE_QUEUED
      && phase !== REQUEST_PHASE_EXECUTING
      && phase !== REQUEST_PHASE_FINISHING
      && phase !== REQUEST_PHASE_EXPIRING
    )
    || (phase === REQUEST_PHASE_FINISHING ? !isExecutionResults(results) : results !== undefined)
    || (
      phase === REQUEST_PHASE_EXECUTING
        ? (
          typeof claimToken !== 'string'
          || claimToken.length === 0
          || typeof claimExpiresAt !== 'number'
          || !Number.isSafeInteger(claimExpiresAt)
          || claimExpiresAt < createdAt
          || claimExpiresAt > expiresAt
        )
        : claimToken !== undefined || claimExpiresAt !== undefined
    )
  ) {
    return undefined;
  }

  return new StoredExecutionRequest(
    id,
    type,
    createdAt,
    expiresAt,
    ownerKey,
    consumerId,
    consumerVersion,
    generation,
    name,
    data,
    error,
    phase as string,
    results as ESObject[] | undefined,
    claimToken as string | undefined,
    claimExpiresAt as number | undefined,
    (allowForeground ?? true) as boolean,
  );
}

function isExecutionResults(value: ESObject): boolean {
  if (!Array.isArray(value)) return false;
  for (const item of value) {
    const record = asRecord(item);
    if (record === undefined || typeof record['taskName'] !== 'string' || record['taskName'].length === 0) return false;
  }
  return true;
}
