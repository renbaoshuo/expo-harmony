import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { ExpoTaskManagerBackgroundQueue } from '@expo-harmony/expo-task-manager';

import {
  OWNER_PARAMETER,
  OWNER_PARAMETER_VALUE,
  TASK_NAME_PARAMETER,
  TASK_MANAGER_OWNER_PARAMETER,
  TASK_TYPE,
  WORK_SCHEDULER_EXECUTION_WINDOW_MS,
} from './BackgroundFetchConstants';
import { decodePendingWorks, PENDING_WORK_SCHEMA_VERSION } from './BackgroundFetchStorageCodec.ts';

const PREFERENCES_NAME: string = 'ExpoBackgroundFetch';
const PENDING_WORKS_KEY: string = 'pendingWorks';
const CORRUPTED_PENDING_WORKS_KEY: string = 'corruptedPendingWorks';

class PendingWork {
  version: number = PENDING_WORK_SCHEMA_VERSION;
  requestId: string;
  workId: number;
  bundleName: string;
  abilityName: string;
  taskName: string;
  ownerKey: string;

  constructor(requestId: string, workId: number, bundleName: string, abilityName: string, taskName: string, ownerKey: string) {
    this.requestId = requestId;
    this.workId = workId;
    this.bundleName = bundleName;
    this.abilityName = abilityName;
    this.taskName = taskName;
    this.ownerKey = ownerKey;
  }

  toWorkInfo(): workScheduler.WorkInfo {
    return {
      workId: this.workId,
      bundleName: this.bundleName,
      abilityName: this.abilityName,
    };
  }
}

export class BackgroundFetchRuntime {
  private static mutation: Promise<void> = Promise.resolve();

  static start(context: common.Context, work: workScheduler.WorkInfo): void {
    if (!isOwnedWork(work)) return;

    const taskName = taskNameFromWork(work);
    if (taskName === undefined) {
      finishWorkBestEffort(work);
      console.error('Expo Background Fetch ignored a scheduler callback without a task name.');
      return;
    }

    BackgroundFetchRuntime.serialize(async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);
      const current = works.find((pending: PendingWork): boolean => pending.workId === work.workId);
      const ownerKey = taskManagerOwnerFromWork(work);

      if (current !== undefined) {
        if (current.taskName !== taskName) {
          throw new Error(`Expo Background Fetch work '${work.workId}' changed task from '${current.taskName}' to '${taskName}'.`);
        }

        await ExpoTaskManagerBackgroundQueue.expireRequest(context, current.ownerKey, TASK_TYPE, current.requestId);
        const replacement = new PendingWork(createRequestId(work), work.workId, work.bundleName, work.abilityName, taskName, ownerKey);
        const nextWorks = works.filter((pending: PendingWork): boolean => pending.requestId !== current.requestId);
        nextWorks.push(replacement);
        await writePendingWorks(store, nextWorks);
        await ExpoTaskManagerBackgroundQueue.enqueue(
          context,
          ownerKey,
          TASK_TYPE,
          Date.now() + WORK_SCHEDULER_EXECUTION_WINDOW_MS,
          replacement.requestId,
          taskName,
          {},
          null,
        );
        return;
      }

      const next = new PendingWork(createRequestId(work), work.workId, work.bundleName, work.abilityName, taskName, ownerKey);
      works.push(next);

      await writePendingWorks(store, works);

      try {
        await ExpoTaskManagerBackgroundQueue.enqueue(
          context,
          ownerKey,
          TASK_TYPE,
          Date.now() + WORK_SCHEDULER_EXECUTION_WINDOW_MS,
          next.requestId,
          taskName,
          {},
          null,
        );
      } catch (error) {
        try {
          await writePendingWorks(
            store,
            works.filter((pending: PendingWork): boolean => pending.requestId !== next.requestId),
          );
        } catch (rollback) {
          console.error(`Unable to roll back Expo Background Fetch pending state: ${String(rollback)}`);
        }

        throw new Error(`Unable to enqueue Expo Background Fetch execution: ${String(error)}`);
      }
    }).catch((error: Object): void => {
      finishWorkBestEffort(work);
      console.error(String(error));
    });
  }

  static stop(context: common.Context, work: workScheduler.WorkInfo): void {
    if (!isOwnedWork(work)) return;

    BackgroundFetchRuntime.expire(context, work).catch((error: Object): void => {
      console.error(`Unable to expire Expo Background Fetch execution: ${String(error)}`);
    });
  }

  static async expire(context: common.Context, work: workScheduler.WorkInfo): Promise<void> {
    if (!isOwnedWork(work)) return;

    await BackgroundFetchRuntime.serialize(async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);
      const matching = works.filter((pending: PendingWork): boolean => pending.workId === work.workId);

      await expirePendingWorks(context, matching);
    });
  }

  static async expireAll(context: common.Context): Promise<void> {
    await BackgroundFetchRuntime.serialize(async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);

      await expirePendingWorks(context, works);
    });
  }

  static async finish(context: common.Context, requestId?: string): Promise<void> {
    await BackgroundFetchRuntime.serialize(async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);

      if (requestId === undefined) {
        try {
          await writePendingWorks(store, []);
        } finally {
          works.forEach((work: PendingWork): void => finishWorkBestEffort(work.toWorkInfo()));
        }
        return;
      }

      const pending = works.find((work: PendingWork): boolean => work.requestId === requestId);
      const remaining = works.filter((work: PendingWork): boolean => work.requestId !== requestId);

      if (pending === undefined) return;

      try {
        await writePendingWorks(store, remaining);
      } finally {
        finishWorkBestEffort(pending.toWorkInfo());
      }
    });
  }

  private static async serialize(action: () => Promise<void>): Promise<void> {
    const next = BackgroundFetchRuntime.mutation.catch((): void => {}).then(action);

    BackgroundFetchRuntime.mutation = next.catch((): void => {});
    await next;
  }
}

async function expirePendingWorks(context: common.Context, matching: PendingWork[]): Promise<void> {
  if (matching.length === 0) return;

  let failures = 0;

  for (const pending of matching) {
    try {
      await ExpoTaskManagerBackgroundQueue.expireRequest(context, pending.ownerKey, TASK_TYPE, pending.requestId);
    } catch (error) {
      failures += 1;
      console.error(`Unable to expire Expo Background Fetch request '${pending.requestId}': ${String(error)}`);
    }
  }

  if (failures > 0) {
    throw new Error(`Unable to expire ${failures} Expo Background Fetch execution request(s).`);
  }
}

async function openStore(context: common.Context): Promise<preferences.Preferences> {
  return await preferences.getPreferences(context, { name: PREFERENCES_NAME });
}

async function readPendingWorks(store: preferences.Preferences): Promise<PendingWork[]> {
  const raw = await store.get(PENDING_WORKS_KEY, '[]');
  const decoded = decodePendingWorks(raw);

  if (decoded.corrupted) {
    await store.put(CORRUPTED_PENDING_WORKS_KEY, typeof raw === 'string' ? raw : JSON.stringify(raw));

    if (decoded.values.length === 0) await store.delete(PENDING_WORKS_KEY);
    else await store.put(PENDING_WORKS_KEY, JSON.stringify(decoded.values));

    await store.flush();
    console.error('Expo Background Fetch repaired corrupted pending work storage.');
  }

  return decoded.values.map(
    (pending): PendingWork =>
      new PendingWork(pending.requestId, pending.workId, pending.bundleName, pending.abilityName, pending.taskName, pending.ownerKey),
  );
}

async function writePendingWorks(store: preferences.Preferences, works: PendingWork[]): Promise<void> {
  if (works.length === 0) {
    await store.delete(PENDING_WORKS_KEY);
  } else {
    await store.put(PENDING_WORKS_KEY, JSON.stringify(works));
  }
  await store.flush();
}

function isOwnedWork(work: workScheduler.WorkInfo): boolean {
  const ownerKey = work.parameters?.[TASK_MANAGER_OWNER_PARAMETER];
  return work.parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE && typeof ownerKey === 'string' && ownerKey.length > 0;
}

function taskNameFromWork(work: workScheduler.WorkInfo): string | undefined {
  const value = work.parameters?.[TASK_NAME_PARAMETER];

  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function createRequestId(work: workScheduler.WorkInfo): string {
  return `${OWNER_PARAMETER_VALUE}:${work.workId}:${util.generateRandomUUID(true)}`;
}

function taskManagerOwnerFromWork(work: workScheduler.WorkInfo): string {
  const value = work.parameters?.[TASK_MANAGER_OWNER_PARAMETER];
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('Expo Background Fetch work is missing its TaskManager owner.');
  }
  return value;
}

function finishWorkBestEffort(work: workScheduler.WorkInfo): void {
  try {
    workScheduler.stopWork(work, false);
  } catch (error) {
    console.error(`Unable to finish Expo Background Fetch execution: ${String(error)}`);
  }
}
