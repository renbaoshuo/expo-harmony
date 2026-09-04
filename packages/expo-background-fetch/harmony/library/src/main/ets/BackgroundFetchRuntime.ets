import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { ExpoTaskManagerBackgroundQueue, ExpoTaskManagerWorkMetadata } from '@expo-harmony/expo-task-manager';

import {
  OWNER_PARAMETER,
  OWNER_PARAMETER_VALUE,
  SCHEDULER_GENERATION_PARAMETER,
  TASK_NAME_PARAMETER,
  TASK_TYPE,
  WORK_SCHEDULER_CLEANUP_MARGIN_MS,
  WORK_SCHEDULER_EXECUTION_WINDOW_MS,
} from './BackgroundFetchConstants';
import { decodePendingWorks, PENDING_WORK_SCHEMA_VERSION } from './BackgroundFetchStorageCodec.ts';

const PREFERENCES_NAME: string = 'ExpoBackgroundFetch';
const PENDING_WORKS_KEY: string = 'pendingWorks';
const CORRUPTED_PENDING_WORKS_KEY: string = 'corruptedPendingWorks';
const MAXIMUM_CORRUPTION_DIAGNOSTICS: number = 20;

class PendingWork {
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

  toWorkInfo(): workScheduler.WorkInfo {
    return { workId: this.workId, bundleName: this.bundleName, abilityName: this.abilityName };
  }
}

export class BackgroundFetchRuntime {
  private static mutation: Promise<void> = Promise.resolve();

  static async start(context: common.Context, work: workScheduler.WorkInfo, startedAt: number = Date.now()): Promise<string | undefined> {
    if (!isOwnedWork(work)) return undefined;

    const taskName = taskNameFromWork(work);
    if (taskName === undefined) {
      finishWorkBestEffort(work);
      console.error('Expo Background Fetch ignored a scheduler callback without a task name.');
      return undefined;
    }

    let requestId: string | undefined;
    try {
      await BackgroundFetchRuntime.serialize(async (): Promise<void> => {
        const expiresAt = startedAt + WORK_SCHEDULER_EXECUTION_WINDOW_MS - WORK_SCHEDULER_CLEANUP_MARGIN_MS;
        if (expiresAt <= Date.now()) {
          throw new Error('Expo Background Fetch callback expired before it reached TaskManager.');
        }

        const store = await openStore(context);
        const works = await readPendingWorks(store);
        const pending = new PendingWork(
          createRequestId(work),
          work.workId,
          work.bundleName,
          work.abilityName,
          taskName,
          taskManagerOwnerFromWork(work),
          schedulerGenerationFromWork(work),
          expiresAt,
        );
        works.push(pending);
        await writePendingWorks(store, works);

        try {
          await ExpoTaskManagerBackgroundQueue.enqueue(context, pending.ownerKey, TASK_TYPE, expiresAt, pending.requestId, taskName, {}, null, false);
          requestId = pending.requestId;
        } catch (error) {
          await writePendingWorks(
            store,
            works.filter((item: PendingWork): boolean => item.requestId !== pending.requestId),
          );
          throw new Error(`Unable to enqueue Expo Background Fetch execution: ${String(error)}`);
        }
      });
    } catch (error) {
      finishWorkBestEffort(work);
      console.error(String(error));
    }
    return requestId;
  }

  static stop(context: common.Context, work: workScheduler.WorkInfo, request?: Promise<string | undefined>): void {
    if (!isOwnedWork(work)) return;
    BackgroundFetchRuntime.serialize(async (): Promise<void> => {
      const requestId = request === undefined ? undefined : await request;
      const store = await openStore(context);
      const works = await readPendingWorks(store);
      const generation = schedulerGenerationFromWork(work);
      const matching =
        requestId === undefined
          ? works.filter((pending: PendingWork): boolean => pending.workId === work.workId && pending.schedulerGeneration === generation)
          : works.filter((pending: PendingWork): boolean => pending.requestId === requestId);
      await expirePendingWorks(context, store, works, matching);
    }).catch((error: Object): void => {
      console.error(`Unable to expire Expo Background Fetch execution: ${String(error)}`);
    });
  }

  static async expire(context: common.Context, work: workScheduler.WorkInfo): Promise<void> {
    if (!isOwnedWork(work)) return;
    await BackgroundFetchRuntime.serialize(async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);
      const generation = schedulerGenerationFromWork(work);
      const matching = works.filter((pending: PendingWork): boolean => pending.workId === work.workId && pending.schedulerGeneration === generation);
      await expirePendingWorks(context, store, works, matching);
    });
  }

  static async expireAll(context: common.Context): Promise<void> {
    await BackgroundFetchRuntime.serialize(async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);
      await expirePendingWorks(context, store, works, works.slice());
    });
  }

  static async finish(context: common.Context, requestId?: string): Promise<void> {
    if (requestId === undefined) {
      console.error('Expo Background Fetch ignored a completion without a TaskManager request id.');
      return;
    }
    await BackgroundFetchRuntime.serialize(async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);
      const pending = works.find((work: PendingWork): boolean => work.requestId === requestId);
      if (pending === undefined) return;

      const remaining = works.filter((work: PendingWork): boolean => work.requestId !== requestId);
      await writePendingWorks(store, remaining);
      const sameSchedulerRun = remaining.some(
        (work: PendingWork): boolean => work.workId === pending.workId && work.schedulerGeneration === pending.schedulerGeneration,
      );
      if (!sameSchedulerRun) finishWorkBestEffort(pending.toWorkInfo());
    });
  }

  private static async serialize(action: () => Promise<void>): Promise<void> {
    const next = BackgroundFetchRuntime.mutation.catch((): void => {}).then(action);
    BackgroundFetchRuntime.mutation = next.catch((): void => {});
    await next;
  }
}

async function expirePendingWorks(
  context: common.Context,
  store: preferences.Preferences,
  all: PendingWork[],
  matching: PendingWork[],
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
    await writePendingWorks(
      store,
      all.filter((pending: PendingWork): boolean => !remove.has(pending.requestId)),
    );
    for (const pending of matching) {
      if (remove.has(pending.requestId)) finishWorkBestEffort(pending.toWorkInfo());
    }
  }
  if (failures > 0) throw new Error(`Unable to expire ${failures} Expo Background Fetch execution request(s).`);
}

async function openStore(context: common.Context): Promise<preferences.Preferences> {
  return await preferences.getPreferences(context, { name: PREFERENCES_NAME });
}

async function readPendingWorks(store: preferences.Preferences): Promise<PendingWork[]> {
  const raw = await store.get(PENDING_WORKS_KEY, '[]');
  const decoded = decodePendingWorks(raw);
  if (decoded.corrupted) {
    await recordCorruptionDiagnostic(store, raw);
    if (decoded.values.length === 0) await store.delete(PENDING_WORKS_KEY);
    else await store.put(PENDING_WORKS_KEY, JSON.stringify(decoded.values));
    await store.flush();
    console.error('Expo Background Fetch repaired corrupted pending work storage.');
  }
  return decoded.values.map(
    (pending): PendingWork =>
      new PendingWork(
        pending.requestId,
        pending.workId,
        pending.bundleName,
        pending.abilityName,
        pending.taskName,
        pending.ownerKey,
        pending.schedulerGeneration,
        pending.expiresAt,
      ),
  );
}

async function recordCorruptionDiagnostic(store: preferences.Preferences, value: ESObject): Promise<void> {
  const raw = await store.get(CORRUPTED_PENDING_WORKS_KEY, '[]');
  let diagnostics: ESObject[] = [];
  if (typeof raw === 'string') {
    try {
      const parsed: ESObject = JSON.parse(raw);
      if (Array.isArray(parsed)) diagnostics = parsed.slice(-MAXIMUM_CORRUPTION_DIAGNOSTICS + 1);
    } catch (_) {}
  }
  diagnostics.push({ valueType: value === null ? 'null' : typeof value, recoveredAt: Date.now() });
  await store.put(CORRUPTED_PENDING_WORKS_KEY, JSON.stringify(diagnostics));
}

async function writePendingWorks(store: preferences.Preferences, works: PendingWork[]): Promise<void> {
  if (works.length === 0) await store.delete(PENDING_WORKS_KEY);
  else await store.put(PENDING_WORKS_KEY, JSON.stringify(works));
  await store.flush();
}

function isOwnedWork(work: workScheduler.WorkInfo): boolean {
  return (
    work.parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    ExpoTaskManagerWorkMetadata.owner(work.parameters, true) !== undefined &&
    schedulerGenerationFromWork(work).length > 0
  );
}

function taskNameFromWork(work: workScheduler.WorkInfo): string | undefined {
  const value = work.parameters?.[TASK_NAME_PARAMETER];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function schedulerGenerationFromWork(work: workScheduler.WorkInfo): string {
  const value = work.parameters?.[SCHEDULER_GENERATION_PARAMETER];
  return typeof value === 'string' ? value : '';
}

function taskManagerOwnerFromWork(work: workScheduler.WorkInfo): string {
  const owner = ExpoTaskManagerWorkMetadata.owner(work.parameters, true);
  if (owner === undefined) throw new Error('Expo Background Fetch work is missing valid TaskManager metadata.');
  return owner;
}

function createRequestId(work: workScheduler.WorkInfo): string {
  return `${OWNER_PARAMETER_VALUE}:${work.workId}:${util.generateRandomUUID(true)}`;
}

function finishWorkBestEffort(work: workScheduler.WorkInfo): void {
  try {
    workScheduler.stopWork(work, false);
  } catch (error) {
    console.error(`Unable to finish Expo Background Fetch execution: ${String(error)}`);
  }
}
