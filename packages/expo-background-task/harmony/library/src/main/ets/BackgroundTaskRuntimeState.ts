/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

const PENDING_WORK_SCHEMA_VERSION: number = 2;
export const WORK_SCHEDULER_EXECUTION_WINDOW_MS: number = 2 * 60 * 1000;
const WORK_SCHEDULER_CLEANUP_MARGIN_MS: number = 10 * 1000;
export const PENDING_WORK_MAXIMUM_AGE_MS: number = WORK_SCHEDULER_EXECUTION_WINDOW_MS - WORK_SCHEDULER_CLEANUP_MARGIN_MS;

const PENDING_PHASE_ENQUEUING: string = 'enqueuing';
const PENDING_PHASE_QUEUED: string = 'queued';
const PENDING_PHASE_EXPIRING: string = 'expiring';
const PENDING_PHASE_COMPLETING: string = 'completing';

export class ScheduledWork {
  workId: number;
  bundleName: string;
  abilityName: string;
  schedulerGeneration: string;

  constructor(workId: number, bundleName: string, abilityName: string, schedulerGeneration: string = '') {
    this.workId = workId;
    this.bundleName = bundleName;
    this.abilityName = abilityName;
    this.schedulerGeneration = schedulerGeneration;
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
    schedulerGeneration: string = '',
  ) {
    super(workId, bundleName, abilityName, schedulerGeneration);
    this.requestId = requestId;
    this.startedAt = startedAt;
    this.phase = phase;
  }
}

export interface BackgroundTaskRuntimeDriver {
  read(): Promise<StoredPendingWork[]>;
  save(work: StoredPendingWork): Promise<void>;
  remove(id: string): Promise<void>;
  enqueue(id: string, deadline: number): Promise<void>;
  requestExpiration(id: string): Promise<boolean>;
  stop(work: StoredPendingWork): Promise<void>;
  report(message: string): void;
}

export class BackgroundTaskRuntimeState {
  private readonly driver: BackgroundTaskRuntimeDriver;

  constructor(driver: BackgroundTaskRuntimeDriver) {
    this.driver = driver;
  }

  async start(
    work: ScheduledWork,
    id: string,
    now: number,
    startedAt: number,
    wasStopped: () => boolean,
  ): Promise<string | undefined> {
    const works = await this.driver.read();
    if (wasStopped()) return undefined;

    let current: StoredPendingWork | undefined;

    for (const pending of works) {
      if (
        current === undefined
        && pending.phase !== PENDING_PHASE_COMPLETING
        && pending.phase !== PENDING_PHASE_EXPIRING
        && sameWork(pending, work)
        && !isPendingWorkExpired(pending, now)
      ) {
        current = pending;

        continue;
      }

      if (sameWork(pending, work)) {
        // Periodic runs share a generation; persistently detach old requests so
        // late cleanup cannot stop this run. Empty generations never stop work.
        pending.schedulerGeneration = '';

        await this.driver.save(pending);
      }

      if (pending.phase === PENDING_PHASE_COMPLETING) {
        await this.completeBestEffort(pending);

        continue;
      }

      await this.requestExpirationBestEffort(pending);
    }

    if (wasStopped()) return undefined;

    const pending = current ?? new StoredPendingWork(
      id,
      work.workId,
      work.bundleName,
      work.abilityName,
      startedAt,
      PENDING_PHASE_ENQUEUING,
      work.schedulerGeneration,
    );

    if (current === undefined) await this.driver.save(pending);
    if (wasStopped()) {
      await this.requestExpirationBestEffort(pending);
      return undefined;
    }

    try {
      await this.driver.enqueue(pending.requestId, pending.startedAt + PENDING_WORK_MAXIMUM_AGE_MS);
    } catch (error) {
      // Enqueue can fail after persisting a request. Expire it through TaskManager.
      await this.requestExpirationBestEffort(pending);
      throw new Error(`Unable to enqueue Expo BackgroundTask execution: ${String(error)}`);
    }

    if (pending.phase !== PENDING_PHASE_QUEUED) {
      pending.phase = PENDING_PHASE_QUEUED;
      try {
        await this.driver.save(pending);
      } catch (error) {
        this.driver.report(`Unable to mark Expo BackgroundTask request '${pending.requestId}' queued: ${String(error)}`);
      }
    }

    return pending.requestId;
  }

  async stop(work: ScheduledWork, id: string | undefined, now: number): Promise<void> {
    const works = await this.driver.read();

    if (id !== undefined) {
      const current = works.find((pending: StoredPendingWork): boolean => {
        return pending.requestId === id && sameWork(pending, work);
      });

      if (current !== undefined) await this.requestExpiration(current);

      return;
    }

    for (const pending of works) {
      if (sameWork(pending, work) && isPendingWorkExpired(pending, now)) {
        await this.requestExpirationBestEffort(pending);
      }
    }
  }

  async complete(id: string | undefined): Promise<void> {
    if (id === undefined) return;

    const works = await this.driver.read();

    const pending = works.find((work: StoredPendingWork): boolean => work.requestId === id);
    if (pending === undefined) return;

    pending.phase = PENDING_PHASE_COMPLETING;

    await this.driver.save(pending);

    await this.stopAndRemove(pending);
  }

  async expire(id: string | undefined): Promise<void> {
    if (id === undefined) return;

    const works = await this.driver.read();

    const pending = works.find((work: StoredPendingWork): boolean => work.requestId === id);
    if (pending === undefined) return;

    await this.stopAndRemove(pending);
  }

  private async completeBestEffort(pending: StoredPendingWork): Promise<void> {
    try {
      await this.stopAndRemove(pending);
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

function isPendingWorkExpired(pending: StoredPendingWork, now: number): boolean {
  return now - pending.startedAt >= PENDING_WORK_MAXIMUM_AGE_MS;
}

function pendingWorkFromValue(value: ESObject): StoredPendingWork | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;

  const item = value as Record<string, ESObject>;
  const version = item['version'];
  const request = item['requestId'];
  const id = item['workId'];
  const bundle = item['bundleName'];
  const ability = item['abilityName'];
  const started = item['startedAt'];
  const phase = item['phase'];
  const generation = version === 1 ? '' : item['schedulerGeneration'];

  if (
    (version !== PENDING_WORK_SCHEMA_VERSION && version !== 1)
    || typeof request !== 'string'
    || request.length === 0
    || typeof id !== 'number'
    || !Number.isSafeInteger(id)
    || typeof bundle !== 'string'
    || bundle.length === 0
    || typeof ability !== 'string'
    || ability.length === 0
    || typeof started !== 'number'
    || !Number.isFinite(started)
    || !isPendingPhase(phase)
    || typeof generation !== 'string'
    || generation.length > 128
  ) {
    return undefined;
  }

  return new StoredPendingWork(request, id, bundle, ability, started, phase, generation);
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
    && left.abilityName === right.abilityName
    && left.schedulerGeneration === right.schedulerGeneration;
}
