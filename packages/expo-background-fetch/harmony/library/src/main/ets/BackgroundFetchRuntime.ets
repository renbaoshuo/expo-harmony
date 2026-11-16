/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { process, util } from '@kit.ArkTS';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { deviceInfo, settings } from '@kit.BasicServicesKit';
import { ExpoTaskManagerBackgroundQueue, ExpoTaskManagerWorkMetadata } from '@expo-harmony/expo-task-manager';

import {
  OWNER_PARAMETER,
  OWNER_PARAMETER_VALUE,
  SCHEDULER_GENERATION_PARAMETER,
  REGISTRATION_GENERATION_PARAMETER,
  START_ON_BOOT_PARAMETER,
  STOP_ON_TERMINATE_PARAMETER,
  TASK_NAME_PARAMETER,
  TASK_TYPE,
  WORK_SCHEDULER_CLEANUP_MARGIN_MS,
  WORK_SCHEDULER_EXECUTION_WINDOW_MS,
  WORK_SCHEDULER_EXTENSION_NAME,
} from './BackgroundFetchConstants';
import {
  decodePendingWorks,
  MAXIMUM_PENDING_WORKS,
  MAXIMUM_PENDING_WORKS_LENGTH,
  StoredPendingWork,
} from './BackgroundFetchStorageCodec';

const PREFERENCES_NAME: string = 'ExpoBackgroundFetch';
const PENDING_WORKS_KEY: string = 'pendingWorks';
const BOOT_COUNT_API: number = 21;

export enum BackgroundFetchState {
  Background,
  Foreground,
  Terminated,
  Rebooted,
}

export class BackgroundFetchRuntime {
  private static mutation: Promise<void> = Promise.resolve();

  static async updateSchedule(
    context: common.UIAbilityContext,
    expireAll: boolean,
    reconcile: (expired: workScheduler.WorkInfo[]) => Promise<void>,
  ): Promise<void> {
    await BackgroundFetchRuntime.serialize(context, async (): Promise<void> => {
      const expired: workScheduler.WorkInfo[] = [];

      try {
        await reconcile(expired);
      } finally {
        if (expireAll || expired.length > 0) {
          const works = await readPendingWorks(context);
          const owner = context.abilityInfo.bundleName;
          const owned = works.filter((pending: StoredPendingWork): boolean =>
            belongsTo(pending, owner) && (expireAll || expired.some((work: workScheduler.WorkInfo): boolean => matchesWork(pending, work))),
          );

          await expirePendingWorks(context, works, owned);
        }
      }
    });
  }

  static setState(context: common.Context, owner: string, state: BackgroundFetchState): void {
    writeTextAtomically(statePath(context, owner), `${bootCount(context)}:${state}:${process.pid}`);
  }

  static getState(context: common.Context, owner: string): Promise<BackgroundFetchState> {
    return readState(context, owner);
  }

  static async start(
    context: common.ExtensionContext,
    work: workScheduler.WorkInfo,
    startedAt: number,
    isStopped: () => boolean,
  ): Promise<string | undefined> {
    const owner = context.extensionAbilityInfo.bundleName;
    if (!isOwnedWork(work, owner)) return undefined;

    let requestId: string | undefined;
    const schedulerGeneration = schedulerGenerationFromWork(work);
    const stopAt = startedAt + WORK_SCHEDULER_EXECUTION_WINDOW_MS;

    try {
      await BackgroundFetchRuntime.serialize(context, async (): Promise<void> => {
        if (isStopped() || schedulerGeneration === '') return;

        const taskName = taskNameFromWork(work);
        const generation = registrationGenerationFromWork(work);
        const current = (await workScheduler.obtainAllWorks()).find(
          (value: workScheduler.WorkInfo): boolean =>
            value.workId === work.workId &&
            isOwnedWork(value, owner) &&
            schedulerGenerationFromWork(value) === schedulerGeneration &&
            taskNameFromWork(value) === taskName &&
            registrationGenerationFromWork(value) === generation,
        );

        if (current === undefined || isStopped()) return;

        if (taskName === undefined || generation === undefined) {
          await finishWorkBestEffort(work, schedulerGeneration, stopAt);

          return;
        }

        let works = await readPendingWorks(context);
        const stale = works.filter((pending: StoredPendingWork): boolean => belongsTo(pending, owner) && workStopDeadline(pending) <= startedAt);
        if (stale.length > 0) {
          try {
            await expirePendingWorks(context, works, stale);
          } catch (error) {
            console.error(String(error));
          }

          works = await readPendingWorks(context);
        }

        if (isStopped()) return;

        const pending = new StoredPendingWork(
          createRequestId(work),
          work.workId,
          work.bundleName,
          work.abilityName,
          taskName,
          owner,
          schedulerGeneration,
          stopAt - WORK_SCHEDULER_CLEANUP_MARGIN_MS,
          generation,
        );

        const state = await readState(context, pending.ownerKey);
        if (isStopped()) return;

        if (
          pending.expiresAt <= Date.now() ||
          state === BackgroundFetchState.Foreground ||
          (state === BackgroundFetchState.Terminated && stopOnTerminateFromWork(current)) ||
          (state === BackgroundFetchState.Rebooted && !startOnBootFromWork(current)) ||
          works.length >= MAXIMUM_PENDING_WORKS
        ) {
          await finishPendingWorkIfIdle(pending, works);

          return;
        }

        const next = [...works, pending];

        try {
          writePendingWorks(context, next);
        } catch (error) {
          await finishPendingWorkIfIdle(pending, works);

          throw new Error(`Unable to store Expo Background Fetch execution: ${String(error)}`);
        }

        try {
          await ExpoTaskManagerBackgroundQueue.enqueue(
            context,
            pending.ownerKey,
            TASK_TYPE,
            pending.expiresAt,
            pending.requestId,
            taskName,
            {},
            null,
            false,
            generation,
          );

          requestId = pending.requestId;
        } catch (error) {
          // Enqueue can fail after it writes the durable request.
          await expirePendingWorks(context, next, [pending]);

          throw new Error(`Unable to enqueue Expo Background Fetch execution: ${String(error)}`);
        }
      });
    } catch (error) {
      console.error(String(error));
    }

    return requestId;
  }

  static stop(context: common.ExtensionContext, work: workScheduler.WorkInfo, request?: Promise<string | undefined>): void {
    if (!isOwnedWork(work, context.extensionAbilityInfo.bundleName)) return;

    const stoppedAt = Date.now();
    Promise.resolve(request)
      .then(async (requestId: string | undefined): Promise<void> => {
        if (request !== undefined && requestId === undefined) return;

        await BackgroundFetchRuntime.serialize(context, async (): Promise<void> => {
          const works = await readPendingWorks(context);
          const matching = works.filter((pending: StoredPendingWork): boolean =>
            matchesWork(pending, work) &&
            (requestId === undefined ? workStopDeadline(pending) - WORK_SCHEDULER_EXECUTION_WINDOW_MS <= stoppedAt : pending.requestId === requestId),
          );

          await expirePendingWorks(context, works, matching);
        });
      })
      .catch((error: Object): void => {
        console.error(`Unable to expire Expo Background Fetch execution: ${String(error)}`);
      });
  }

  static async finish(context: common.UIAbilityContext, requestId?: string): Promise<void> {
    if (requestId === undefined) {
      console.error('Expo Background Fetch ignored a completion without a TaskManager request id.');
      return;
    }

    await BackgroundFetchRuntime.serialize(context, async (): Promise<void> => {
      const works = await readPendingWorks(context);
      const pending = works.find((work: StoredPendingWork): boolean => work.requestId === requestId && belongsTo(work, context.abilityInfo.bundleName));

      if (pending === undefined) return;

      const remaining = works.filter((work: StoredPendingWork): boolean => work.requestId !== requestId);
      writePendingWorks(context, remaining);

      await finishPendingWorkIfIdle(pending, remaining);
    });
  }

  private static async serialize(context: common.Context, action: () => Promise<void>): Promise<void> {
    const next = BackgroundFetchRuntime.mutation
      .catch((): void => {})
      .then(async (): Promise<void> => {
        const app = context.getApplicationContext();
        const file = await fs.open(`${app.filesDir}/ExpoBackgroundFetch.lock`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);

        try {
          await file.lock(true);
          await action();
        } finally {
          fs.closeSync(file);
        }
      });

    BackgroundFetchRuntime.mutation = next.catch((): void => {});
    await next;
  }
}

function bootCount(context: common.Context): number {
  try {
    if (deviceInfo.sdkApiVersion >= BOOT_COUNT_API) return deviceInfo.bootCount;
    const count = Number(settings.getValueSync(context, settings.general.BOOT_COUNTING, '-1'));
    if (Number.isSafeInteger(count) && count >= 0) return count;
  } catch (error) {
    console.warn(`Unable to read the system boot count for Expo Background Fetch: ${String(error)}`);
  }
  return -1;
}

function statePath(context: common.Context, owner: string): string {
  return `${context.getApplicationContext().filesDir}/ExpoBackgroundFetch.${encodeURIComponent(owner)}.state`;
}

async function readState(context: common.Context, owner: string): Promise<BackgroundFetchState> {
  const path = statePath(context, owner);
  if (!fs.accessSync(path)) return BackgroundFetchState.Background;

  const fields = fs.readTextSync(path).split(':');
  const boot = bootCount(context);
  const recordedBoot = Number(fields[0]);
  if (boot >= 0 && recordedBoot >= 0 && recordedBoot !== boot) return BackgroundFetchState.Rebooted;

  const state = Number(fields[1]);
  if (state !== BackgroundFetchState.Foreground && state !== BackgroundFetchState.Background) return BackgroundFetchState.Terminated;

  const pid = Number(fields[2]);
  if (Number.isSafeInteger(pid) && pid > 0 && pid !== process.pid) {
    try {
      // WorkScheduler runs in a separate process, and process termination can skip onDestroy.
      const processes = await context.getApplicationContext().getRunningProcessInformation();
      if (!processes.some(info => info.pid === pid)) return BackgroundFetchState.Terminated;
    } catch (error) {
      console.warn(`Unable to verify the Expo Background Fetch application process: ${String(error)}`);
    }
  }

  return state;
}

async function expirePendingWorks(
  context: common.Context,
  all: StoredPendingWork[],
  matching: StoredPendingWork[],
): Promise<void> {
  if (matching.length === 0) return;

  const remove: Set<string> = new Set();
  let failures = 0;

  for (const pending of matching) {
    try {
      const found = await ExpoTaskManagerBackgroundQueue.expireRequest(context, pending.ownerKey, TASK_TYPE, pending.requestId);
      if (!found) remove.add(pending.requestId);
    } catch (error) {
      failures += 1;
      console.error(`Unable to expire Expo Background Fetch request '${pending.requestId}': ${String(error)}`);
    }
  }

  if (remove.size > 0) {
    const remaining = all.filter((pending: StoredPendingWork): boolean => !remove.has(pending.requestId));
    writePendingWorks(context, remaining);

    for (const pending of matching) {
      if (remove.has(pending.requestId)) await finishPendingWorkIfIdle(pending, remaining);
    }
  }

  if (failures > 0) throw new Error(`Unable to expire ${failures} Expo Background Fetch execution request(s).`);
}

async function finishPendingWorkIfIdle(work: StoredPendingWork, remaining: StoredPendingWork[]): Promise<void> {
  const workInfo: workScheduler.WorkInfo = { workId: work.workId, bundleName: work.bundleName, abilityName: work.abilityName };
  const active = remaining.some(
    (pending: StoredPendingWork): boolean =>
      belongsTo(pending, work.bundleName) && pending.workId === work.workId &&
      pending.schedulerGeneration === work.schedulerGeneration && isWithinExecutionWindow(workStopDeadline(pending)),
  );

  if (!active) await finishWorkBestEffort(workInfo, work.schedulerGeneration, workStopDeadline(work));
}

function pendingWorksPath(context: common.Context): string {
  return `${context.getApplicationContext().filesDir}/ExpoBackgroundFetch.pending.json`;
}

async function readPendingWorks(context: common.Context): Promise<StoredPendingWork[]> {
  const path = pendingWorksPath(context);
  const exists = fs.accessSync(path);
  let raw: ESObject;

  if (exists) {
    // A UTF-16 code unit can require up to three bytes in UTF-8.
    raw = fs.statSync(path).size <= MAXIMUM_PENDING_WORKS_LENGTH * 3 ? fs.readTextSync(path) : '';
  } else {
    // Both processes migrate the old Preferences under the same lock.
    const legacy = await preferences.getPreferences(context.getApplicationContext(), { name: PREFERENCES_NAME });
    raw = await legacy.get(PENDING_WORKS_KEY, '[]');
  }

  const decoded = decodePendingWorks(raw);
  if (!exists || decoded.corrupted) writePendingWorks(context, decoded.values);
  if (decoded.corrupted) console.warn('Expo Background Fetch repaired corrupted pending work storage.');

  return decoded.values;
}

function writePendingWorks(context: common.Context, works: StoredPendingWork[]): void {
  const raw = JSON.stringify(works);
  if (raw.length > MAXIMUM_PENDING_WORKS_LENGTH) throw new Error('Expo Background Fetch pending work storage is full.');

  writeTextAtomically(pendingWorksPath(context), raw);
}

function writeTextAtomically(path: string, value: string): void {
  const temp = `${path}.${util.generateRandomUUID(true)}`;
  const bytes = new util.TextEncoder().encodeInto(value);

  try {
    const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);

    try {
      if (fs.writeSync(file.fd, bytes.buffer) !== bytes.byteLength) throw new Error('Incomplete Expo Background Fetch state write.');
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }

    fs.renameSync(temp, path);
  } finally {
    if (fs.accessSync(temp)) fs.unlinkSync(temp);
  }
}

function belongsTo(pending: StoredPendingWork, owner: string): boolean {
  return pending.bundleName === owner && pending.ownerKey === owner && pending.abilityName === WORK_SCHEDULER_EXTENSION_NAME;
}

function matchesWork(pending: StoredPendingWork, work: workScheduler.WorkInfo): boolean {
  return belongsTo(pending, work.bundleName) && pending.workId === work.workId &&
    pending.schedulerGeneration === schedulerGenerationFromWork(work);
}

export function isOwnedWork(work: workScheduler.WorkInfo, bundleName: string): boolean {
  const parameters = ExpoTaskManagerWorkMetadata.parameters(work.parameters);
  return (
    work.bundleName === bundleName &&
    work.abilityName === WORK_SCHEDULER_EXTENSION_NAME &&
    parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    ExpoTaskManagerWorkMetadata.owner(parameters, true) === bundleName
  );
}

export function taskNameFromWork(work: workScheduler.WorkInfo): string | undefined {
  const value = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[TASK_NAME_PARAMETER];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

export function schedulerGenerationFromWork(work: workScheduler.WorkInfo): string {
  const value = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[SCHEDULER_GENERATION_PARAMETER];
  return typeof value === 'string' ? value : '';
}

export function registrationGenerationFromWork(work: workScheduler.WorkInfo): number | undefined {
  const raw = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[REGISTRATION_GENERATION_PARAMETER];
  const value = typeof raw === 'string' && /^[1-9][0-9]*$/.test(raw) ? Number(raw) : raw;
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 ? value : undefined;
}

export function stopOnTerminateFromWork(work: workScheduler.WorkInfo): boolean {
  const value = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[STOP_ON_TERMINATE_PARAMETER];
  return value !== false && value !== 'false';
}

export function startOnBootFromWork(work: workScheduler.WorkInfo): boolean {
  const value = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[START_ON_BOOT_PARAMETER];
  return value === true || value === 'true';
}

function createRequestId(work: workScheduler.WorkInfo): string {
  return `${OWNER_PARAMETER_VALUE}:${work.workId}:${util.generateRandomUUID(true)}`;
}

function workStopDeadline(work: StoredPendingWork): number {
  return work.expiresAt + WORK_SCHEDULER_CLEANUP_MARGIN_MS;
}

function isWithinExecutionWindow(stopAt: number): boolean {
  const remaining = stopAt - Date.now();
  return remaining > 0 && remaining <= WORK_SCHEDULER_EXECUTION_WINDOW_MS;
}

async function finishWorkBestEffort(work: workScheduler.WorkInfo, generation: string, stopAt: number): Promise<void> {
  // Periodic callbacks reuse the work ID. The OS can already be running a later invocation.
  if (generation.length === 0 || !isWithinExecutionWindow(stopAt)) return;

  try {
    const works = await workScheduler.obtainAllWorks();
    const current = works.find((value: workScheduler.WorkInfo): boolean => {
      return (
        value.workId === work.workId &&
        isOwnedWork(value, work.bundleName) &&
        schedulerGenerationFromWork(value) === generation
      );
    });

    if (current !== undefined && isWithinExecutionWindow(stopAt)) workScheduler.stopWork(current, false);
  } catch (error) {
    console.error(`Unable to finish Expo Background Fetch execution: ${String(error)}`);
  }
}
