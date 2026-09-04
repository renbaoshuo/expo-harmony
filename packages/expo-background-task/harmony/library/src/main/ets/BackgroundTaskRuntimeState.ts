export const PENDING_WORK_SCHEMA_VERSION: number = 1;
export const PENDING_WORK_MAXIMUM_AGE_MS: number = 2 * 60 * 1000;

export const PENDING_PHASE_ENQUEUING: string = 'enqueuing';
export const PENDING_PHASE_QUEUED: string = 'queued';
export const PENDING_PHASE_EXPIRING: string = 'expiring';
export const PENDING_PHASE_COMPLETING: string = 'completing';

export class ScheduledWork {
  workId: number;
  bundleName: string;
  abilityName: string;

  constructor(workId: number, bundleName: string, abilityName: string) {
    this.workId = workId;
    this.bundleName = bundleName;
    this.abilityName = abilityName;
  }
}

export class StoredPendingWork extends ScheduledWork {
  version: number = PENDING_WORK_SCHEMA_VERSION;
  requestId: string;
  startedAt: number;
  phase: string;

  constructor(
    requestId: string,
    workId: number,
    bundleName: string,
    abilityName: string,
    startedAt: number,
    phase: string,
  ) {
    super(workId, bundleName, abilityName);
    this.requestId = requestId;
    this.startedAt = startedAt;
    this.phase = phase;
  }
}

export interface BackgroundTaskRuntimeDriver {
  read(): Promise<StoredPendingWork[]>;
  save(work: StoredPendingWork): Promise<void>;
  remove(requestId: string): Promise<void>;
  enqueue(requestId: string, expiresAt: number): Promise<void>;
  requestExpiration(requestId: string): Promise<boolean>;
  stop(work: ScheduledWork): Promise<void>;
  report(message: string): void;
}

export class BackgroundTaskRuntimeState {
  private readonly driver: BackgroundTaskRuntimeDriver;

  constructor(driver: BackgroundTaskRuntimeDriver) {
    this.driver = driver;
  }

  async start(work: ScheduledWork, requestId: string, startedAt: number): Promise<string> {
    const works = await this.driver.read();
    let current: StoredPendingWork | undefined;

    for (const pending of works) {
      if (pending.phase === PENDING_PHASE_COMPLETING) {
        await this.completeBestEffort(pending);
        continue;
      }

      if (pending.phase === PENDING_PHASE_EXPIRING) {
        await this.requestExpirationBestEffort(pending);
        continue;
      }

      if (
        current === undefined
        && sameWork(pending, work)
        && !isPendingWorkExpired(pending, startedAt)
      ) {
        current = pending;
        continue;
      }

      await this.requestExpirationBestEffort(pending);
    }

    if (current !== undefined) {
      await this.driver.enqueue(current.requestId, current.startedAt + PENDING_WORK_MAXIMUM_AGE_MS);

      if (current.phase !== PENDING_PHASE_QUEUED) {
        current.phase = PENDING_PHASE_QUEUED;
        await this.driver.save(current);
      }

      return current.requestId;
    }

    const next = new StoredPendingWork(
      requestId,
      work.workId,
      work.bundleName,
      work.abilityName,
      startedAt,
      PENDING_PHASE_ENQUEUING,
    );
    await this.driver.save(next);

    try {
      await this.driver.enqueue(requestId, startedAt + PENDING_WORK_MAXIMUM_AGE_MS);

      next.phase = PENDING_PHASE_QUEUED;
      await this.driver.save(next);
    } catch (error) {
      await this.stopAndRemove(next);

      throw new Error(`Unable to enqueue Expo BackgroundTask execution: ${String(error)}`);
    }

    return requestId;
  }

  async stop(work: ScheduledWork, requestId: string | undefined, stoppedAt: number): Promise<void> {
    const works = await this.driver.read();

    if (requestId !== undefined) {
      const current = works.find((pending: StoredPendingWork): boolean => {
        return pending.requestId === requestId && sameWork(pending, work);
      });

      if (current !== undefined) await this.requestExpiration(current);
      return;
    }

    for (const pending of works) {
      if (sameWork(pending, work) && isPendingWorkExpired(pending, stoppedAt)) {
        await this.requestExpirationBestEffort(pending);
      }
    }
  }

  async complete(requestId: string | undefined): Promise<void> {
    if (requestId === undefined) return;

    const works = await this.driver.read();
    const pending = works.find((work: StoredPendingWork): boolean => work.requestId === requestId);
    if (pending === undefined) return;

    pending.phase = PENDING_PHASE_COMPLETING;
    await this.driver.save(pending);
    await this.completePending(pending);
  }

  async expire(requestId: string | undefined): Promise<void> {
    if (requestId === undefined) return;

    const works = await this.driver.read();
    const pending = works.find((work: StoredPendingWork): boolean => work.requestId === requestId);
    if (pending === undefined) return;

    await this.cleanupExpiredPending(pending);
  }

  private async completePending(pending: StoredPendingWork): Promise<void> {
    await this.stopAndRemove(pending);
  }

  private async completeBestEffort(pending: StoredPendingWork): Promise<void> {
    try {
      await this.completePending(pending);
    } catch (error) {
      this.driver.report(`Unable to finish Expo BackgroundTask request '${pending.requestId}': ${String(error)}`);
    }
  }

  private async requestExpiration(pending: StoredPendingWork): Promise<void> {
    if (pending.phase !== PENDING_PHASE_EXPIRING) {
      pending.phase = PENDING_PHASE_EXPIRING;
      await this.driver.save(pending);
    }

    const found = await this.driver.requestExpiration(pending.requestId);
    if (!found) await this.stopAndRemove(pending);
  }

  private async requestExpirationBestEffort(pending: StoredPendingWork): Promise<void> {
    try {
      await this.requestExpiration(pending);
    } catch (error) {
      this.driver.report(`Unable to expire Expo BackgroundTask request '${pending.requestId}': ${String(error)}`);
    }
  }

  private async cleanupExpiredPending(pending: StoredPendingWork): Promise<void> {
    await this.stopAndRemove(pending);
  }

  private async stopAndRemove(pending: StoredPendingWork): Promise<void> {
    await this.driver.stop(pending);
    await this.driver.remove(pending.requestId);
  }
}

export function decodePendingWork(raw: ESObject): StoredPendingWork | undefined {
  if (typeof raw !== 'string') return undefined;

  let value: ESObject;
  try {
    value = JSON.parse(raw);
  } catch (_) {
    return undefined;
  }

  return pendingWorkFromValue(value);
}

export function isPendingWorkExpired(pending: StoredPendingWork, now: number): boolean {
  return now - pending.startedAt > PENDING_WORK_MAXIMUM_AGE_MS;
}

function pendingWorkFromValue(value: ESObject): StoredPendingWork | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;

  const item = value as Record<string, ESObject>;
  const version = item['version'];
  const requestId = item['requestId'];
  const workId = item['workId'];
  const bundleName = item['bundleName'];
  const abilityName = item['abilityName'];
  const startedAt = item['startedAt'];
  const phase = item['phase'];

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
    || typeof startedAt !== 'number'
    || !Number.isFinite(startedAt)
    || !isPendingPhase(phase)
  ) {
    return undefined;
  }

  return new StoredPendingWork(requestId, workId, bundleName, abilityName, startedAt, phase);
}

function isPendingPhase(value: ESObject): boolean {
  return value === PENDING_PHASE_ENQUEUING
    || value === PENDING_PHASE_QUEUED
    || value === PENDING_PHASE_EXPIRING
    || value === PENDING_PHASE_COMPLETING;
}

function sameWork(left: ScheduledWork, right: ScheduledWork): boolean {
  return left.workId === right.workId
    && left.bundleName === right.bundleName
    && left.abilityName === right.abilityName;
}
