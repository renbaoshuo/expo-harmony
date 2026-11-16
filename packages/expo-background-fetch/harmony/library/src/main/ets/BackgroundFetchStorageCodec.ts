/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export const PENDING_WORK_SCHEMA_VERSION: number = 3;
export const MAXIMUM_PENDING_WORKS: number = 128;
export const MAXIMUM_PENDING_WORKS_LENGTH: number = 1024 * 1024;

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
  registrationGeneration: number;

  constructor(
    requestId: string,
    workId: number,
    bundleName: string,
    abilityName: string,
    taskName: string,
    ownerKey: string,
    schedulerGeneration: string,
    expiresAt: number,
    registrationGeneration: number = 0,
  ) {
    this.requestId = requestId;
    this.workId = workId;
    this.bundleName = bundleName;
    this.abilityName = abilityName;
    this.taskName = taskName;
    this.ownerKey = ownerKey;
    this.schedulerGeneration = schedulerGeneration;
    this.expiresAt = expiresAt;
    this.registrationGeneration = registrationGeneration;
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
  const requests: Set<string> = new Set();
  let corrupted = data.length > MAXIMUM_PENDING_WORKS;
  const limit = Math.min(data.length, MAXIMUM_PENDING_WORKS);

  for (let index = 0; index < limit; ++index) {
    const item = asRecord(data[index]);

    if (item === undefined) {
      corrupted = true;
      continue;
    }

    const request = item['requestId'];
    const version = item['version'];
    const id = item['workId'];
    const bundle = item['bundleName'];
    const ability = item['abilityName'];
    const name = item['taskName'];
    const owner = item['ownerKey'];
    const scheduler = item['schedulerGeneration'];
    const expires = item['expiresAt'];
    const generation = version === 2 ? 0 : item['registrationGeneration'];

    if (
      (version !== 2 && version !== PENDING_WORK_SCHEMA_VERSION)
      || !isSafeString(request, 256)
      || requests.has(request as string)
      || typeof id !== 'number'
      || !Number.isSafeInteger(id)
      || id < 1
      || id > 0x7fffffff
      || !isSafeString(bundle, 256)
      || !isSafeString(ability, 256)
      || typeof name !== 'string'
      || name.length === 0
      || !isSafeString(owner, 1024)
      || !isSafeString(scheduler, 128)
      || typeof generation !== 'number'
      || !Number.isSafeInteger(generation)
      || generation < 0
      || typeof expires !== 'number'
      || !Number.isSafeInteger(expires)
      || expires <= 0
    ) {
      corrupted = true;
      continue;
    }

    requests.add(request as string);
    works.push(new StoredPendingWork(
      request as string,
      id as number,
      bundle as string,
      ability as string,
      name as string,
      owner as string,
      scheduler as string,
      expires as number,
      generation as number,
    ));
  }

  return new PendingWorkDecodeResult(works, corrupted);
}

function decodeArray(raw: ESObject): ESObject[] | undefined {
  if (typeof raw !== 'string' || raw.length > MAXIMUM_PENDING_WORKS_LENGTH) return undefined;

  try {
    const value: ESObject = JSON.parse(raw);

    return Array.isArray(value) ? value : undefined;
  } catch (_) {
    return undefined;
  }
}

function isSafeString(value: ESObject, limit: number): boolean {
  if (typeof value !== 'string' || value.length === 0 || value.length > limit) return false;

  for (let index = 0; index < value.length; ++index) {
    if (value.charCodeAt(index) < 0x20) return false;
  }

  return true;
}

function asRecord(value: ESObject): Record<string, ESObject> | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;

  return value as Record<string, ESObject>;
}
