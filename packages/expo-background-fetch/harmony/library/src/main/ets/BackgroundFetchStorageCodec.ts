export const PENDING_WORK_SCHEMA_VERSION: number = 2;
export const MAXIMUM_PENDING_WORKS: number = 128;

export class StoredPendingWork {
  version: number = PENDING_WORK_SCHEMA_VERSION;
  requestId: string;
  workId: number;
  bundleName: string;
  abilityName: string;
  taskName: string;
  ownerKey: string;
  schedulerGeneration: string;
  expiresAt: number;

  constructor(
    requestId: string,
    workId: number,
    bundleName: string,
    abilityName: string,
    taskName: string,
    ownerKey: string,
    schedulerGeneration: string,
    expiresAt: number,
  ) {
    this.requestId = requestId;
    this.workId = workId;
    this.bundleName = bundleName;
    this.abilityName = abilityName;
    this.taskName = taskName;
    this.ownerKey = ownerKey;
    this.schedulerGeneration = schedulerGeneration;
    this.expiresAt = expiresAt;
  }
}

export class PendingWorkDecodeResult {
  values: StoredPendingWork[];
  corrupted: boolean;

  constructor(values: StoredPendingWork[], corrupted: boolean) {
    this.values = values;
    this.corrupted = corrupted;
  }
}

export function decodePendingWorks(raw: ESObject): PendingWorkDecodeResult {
  const data = decodeArray(raw);
  if (data === undefined) return new PendingWorkDecodeResult([], true);

  const works: StoredPendingWork[] = [];
  const requestIds: Set<string> = new Set();
  let corrupted = data.length > MAXIMUM_PENDING_WORKS;
  const limit = Math.min(data.length, MAXIMUM_PENDING_WORKS);

  for (let index = 0; index < limit; ++index) {
    const item = asRecord(data[index]);
    if (item === undefined) {
      corrupted = true;
      continue;
    }

    const requestId = item['requestId'];
    const version = item['version'];
    const workId = item['workId'];
    const bundleName = item['bundleName'];
    const abilityName = item['abilityName'];
    const taskName = item['taskName'];
    const ownerKey = item['ownerKey'];
    const schedulerGeneration = item['schedulerGeneration'];
    const expiresAt = item['expiresAt'];

    if (
      version !== PENDING_WORK_SCHEMA_VERSION
      || !isSafeString(requestId, 256)
      || requestIds.has(requestId as string)
      || typeof workId !== 'number'
      || !Number.isSafeInteger(workId)
      || workId < 1
      || workId > 0x7fffffff
      || !isSafeString(bundleName, 256)
      || !isSafeString(abilityName, 256)
      || !isSafeString(taskName, 256)
      || !isSafeString(ownerKey, 1024)
      || !isSafeString(schedulerGeneration, 128)
      || typeof expiresAt !== 'number'
      || !Number.isSafeInteger(expiresAt)
      || expiresAt <= 0
    ) {
      corrupted = true;
      continue;
    }

    requestIds.add(requestId as string);
    works.push(new StoredPendingWork(
      requestId as string,
      workId as number,
      bundleName as string,
      abilityName as string,
      taskName as string,
      ownerKey as string,
      schedulerGeneration as string,
      expiresAt as number,
    ));
  }

  return new PendingWorkDecodeResult(works, corrupted);
}

function decodeArray(raw: ESObject): ESObject[] | undefined {
  if (typeof raw !== 'string' || raw.length > 1024 * 1024) return undefined;

  try {
    const value: ESObject = JSON.parse(raw);

    return Array.isArray(value) ? value : undefined;
  } catch (_) {
    return undefined;
  }
}

function isSafeString(value: ESObject, maximumLength: number): boolean {
  if (typeof value !== 'string' || value.length === 0 || value.length > maximumLength) return false;
  for (let index = 0; index < value.length; ++index) {
    if (value.charCodeAt(index) < 0x20) return false;
  }
  return true;
}

function asRecord(value: ESObject): Record<string, ESObject> | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;

  return value as Record<string, ESObject>;
}
