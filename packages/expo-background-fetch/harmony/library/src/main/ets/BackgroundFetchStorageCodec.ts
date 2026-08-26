export const PENDING_WORK_SCHEMA_VERSION: number = 1;

export class StoredPendingWork {
  version: number = PENDING_WORK_SCHEMA_VERSION;
  requestId: string;
  workId: number;
  bundleName: string;
  abilityName: string;
  taskName: string;
  ownerKey: string;

  constructor(
    requestId: string,
    workId: number,
    bundleName: string,
    abilityName: string,
    taskName: string,
    ownerKey: string,
  ) {
    this.requestId = requestId;
    this.workId = workId;
    this.bundleName = bundleName;
    this.abilityName = abilityName;
    this.taskName = taskName;
    this.ownerKey = ownerKey;
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
  let corrupted = false;

  for (const value of data) {
    const item = asRecord(value);
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

    if (
      version !== PENDING_WORK_SCHEMA_VERSION
      || typeof requestId !== 'string'
      || requestId.length === 0
      || typeof workId !== 'number'
      || !Number.isSafeInteger(workId)
      || typeof bundleName !== 'string'
      || bundleName.length === 0
      || typeof abilityName !== 'string'
      || abilityName.length === 0
      || typeof taskName !== 'string'
      || taskName.length === 0
      || typeof ownerKey !== 'string'
      || ownerKey.length === 0
    ) {
      corrupted = true;
      continue;
    }

    works.push(new StoredPendingWork(requestId, workId, bundleName, abilityName, taskName, ownerKey));
  }

  return new PendingWorkDecodeResult(works, corrupted);
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
