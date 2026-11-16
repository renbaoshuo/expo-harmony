/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { ExpoTaskManagerBackgroundQueue, ExpoTaskManagerWorkMetadata } from '@expo-harmony/expo-task-manager';

import {
  BACKGROUND_TASK_TYPE,
  OWNER_PARAMETER,
  OWNER_PARAMETER_VALUE,
  SCHEDULER_GENERATION_PARAMETER,
  WORK_SCHEDULER_EXTENSION_NAME,
} from './BackgroundTaskConstants';
import {
  BackgroundTaskRuntimeDriver,
  BackgroundTaskRuntimeState,
  decodePendingWork,
  MAXIMUM_SCHEDULER_GENERATION_LENGTH,
  PENDING_WORK_MAXIMUM_AGE_MS,
  ScheduledWork,
  StoredPendingWork,
  WORK_SCHEDULER_EXECUTION_WINDOW_MS,
} from './BackgroundTaskRuntimeState.ts';

const PREFERENCES_NAME: string = 'ExpoBackgroundTask';
const DATABASE_NAME: string = 'ExpoBackgroundTask.db';
const PENDING_WORK_KEY_PREFIX: string = 'pendingWork.';
const LEGACY_IMPORTED_KEY: string = 'legacyPreferencesImported';

class BackgroundTaskStore implements BackgroundTaskRuntimeDriver {
  private readonly context: common.Context;
  private readonly database: relationalStore.RdbStore;
  private readonly ownerKey: string;

  constructor(context: common.Context, database: relationalStore.RdbStore, ownerKey: string) {
    this.context = context;
    this.database = database;
    this.ownerKey = ownerKey;
  }

  async prepare(app: common.Context): Promise<void> {
    await this.database.executeSql('CREATE TABLE IF NOT EXISTS entries (key TEXT PRIMARY KEY, value TEXT NOT NULL)');

    const rows = await this.database.querySql('SELECT 1 FROM entries WHERE key = ?', [LEGACY_IMPORTED_KEY]);
    try {
      if (rows.goToFirstRow()) return;
    } finally {
      rows.close();
    }

    // WorkScheduler and the UI can run in separate processes, so Preferences is read only for migration.
    const legacy = await preferences.getPreferences(app, { name: PREFERENCES_NAME });
    const entries = (await legacy.getAll()) as Record<string, ESObject>;

    this.database.beginTransaction();
    try {
      for (const key of Object.keys(entries)) {
        if (!key.startsWith(PENDING_WORK_KEY_PREFIX)) continue;

        const work = decodePendingWork(entries[key]);
        if (work !== undefined && pendingWorkKey(work.requestId) === key) {
          this.database.executeSync('INSERT OR REPLACE INTO entries (key, value) VALUES (?, ?)', [key, JSON.stringify(work)]);
        }
      }
      this.database.executeSync('INSERT INTO entries (key, value) VALUES (?, ?)', [LEGACY_IMPORTED_KEY, '1']);
      this.database.commit();
    } catch (error) {
      try {
        this.database.rollBack();
      } catch (rollbackError) {
        this.report(`Unable to roll back Expo BackgroundTask storage: ${String(rollbackError)}`);
      }

      throw new Error(`Unable to migrate Expo BackgroundTask storage: ${String(error)}`);
    }
  }

  async read(): Promise<StoredPendingWork[]> {
    const rows = await this.database.querySql('SELECT key, value FROM entries WHERE key LIKE ?', [`${PENDING_WORK_KEY_PREFIX}%`]);
    const works: StoredPendingWork[] = [];
    const invalid: string[] = [];

    try {
      while (rows.goToNextRow()) {
        const key = rows.getString(0);
        const work = decodePendingWork(rows.getString(1));
        if (work === undefined || pendingWorkKey(work.requestId) !== key) {
          invalid.push(key);
        } else if (work.bundleName === this.ownerKey && work.abilityName === WORK_SCHEDULER_EXTENSION_NAME) {
          works.push(work);
        }
      }
    } finally {
      rows.close();
    }

    for (const key of invalid) {
      await this.database.executeSql('DELETE FROM entries WHERE key = ?', [key]);
      this.report(`Removed invalid Expo BackgroundTask record '${key}'.`);
    }

    return works;
  }

  async save(work: StoredPendingWork): Promise<void> {
    await this.database.executeSql('INSERT OR REPLACE INTO entries (key, value) VALUES (?, ?)', [pendingWorkKey(work.requestId), JSON.stringify(work)]);
  }

  async remove(requestId: string): Promise<void> {
    await this.database.executeSql('DELETE FROM entries WHERE key = ?', [pendingWorkKey(requestId)]);
  }

  async enqueue(requestId: string, expiresAt: number): Promise<void> {
    await ExpoTaskManagerBackgroundQueue.enqueue(this.context, this.ownerKey, BACKGROUND_TASK_TYPE, expiresAt, requestId);
  }

  async requestExpiration(requestId: string): Promise<boolean> {
    return await ExpoTaskManagerBackgroundQueue.expireRequest(this.context, this.ownerKey, BACKGROUND_TASK_TYPE, requestId);
  }

  async stop(work: StoredPendingWork): Promise<void> {
    await finishWork(work, work.startedAt);
  }

  report(message: string): void {
    console.error(message);
  }
}

export class BackgroundTaskRuntime {
  private static mutation: Promise<void> = Promise.resolve();

  static async updateSchedule(context: common.Context, action: () => Promise<void>): Promise<void> {
    await BackgroundTaskRuntime.serialize(context, action);
  }

  static async start(
    context: common.Context,
    work: workScheduler.WorkInfo,
    startedAt: number,
    wasStopped: () => boolean,
  ): Promise<string | undefined> {
    let requestId: string | undefined;

    try {
      await BackgroundTaskRuntime.serialize(context, async (): Promise<void> => {
        if (wasStopped()) return;

        try {
          const works = await workScheduler.obtainAllWorks();
          const current = works.some(
            (value: workScheduler.WorkInfo): boolean =>
              value.workId === work.workId &&
              isBackgroundTaskWork(value, work.bundleName, work.abilityName) &&
              schedulerGenerationFromWork(value) === schedulerGenerationFromWork(work),
          );
          if (wasStopped()) return;
          if (!current) {
            console.warn(`Expo BackgroundTask ignored replaced or removed WorkScheduler work ${work.workId}.`);
            return;
          }
          // The execution window includes time spent waiting for the lock.
          if (startedAt + PENDING_WORK_MAXIMUM_AGE_MS <= Date.now()) {
            throw new Error('Expo BackgroundTask callback expired before it reached TaskManager.');
          }

          const id = createRequestId(work);

          await withState(context, work.bundleName, async (state: BackgroundTaskRuntimeState): Promise<void> => {
            requestId = await state.start(toScheduledWork(work), id, Date.now(), startedAt, wasStopped);
          });
        } catch (error) {
          if (!wasStopped()) await finishWorkBestEffort(work, startedAt);
          console.error(String(error));
        }
      });
    } catch (error) {
      console.error(String(error));
    }

    return requestId;
  }

  static stop(
    context: common.Context,
    work: workScheduler.WorkInfo,
    request: Promise<string | undefined> | undefined,
  ): void {
    Promise.resolve(request)
      .then(async (requestId: string | undefined): Promise<void> => {
        await BackgroundTaskRuntime.serialize(context, async (): Promise<void> => {
          await withState(context, work.bundleName, async (state: BackgroundTaskRuntimeState): Promise<void> => {
            await state.stop(toScheduledWork(work), requestId, Date.now());
          });
        });
      })
      .catch((error: Object): void => {
        console.error(`Unable to expire Expo BackgroundTask execution: ${String(error)}`);
      });
  }

  static async finish(context: common.Context, ownerKey: string, requestId?: string): Promise<void> {
    if (requestId === undefined) return;

    await BackgroundTaskRuntime.serialize(context, async (): Promise<void> => {
      await withState(context, ownerKey, (state: BackgroundTaskRuntimeState): Promise<void> => state.complete(requestId));
    });
  }

  static async expire(context: common.Context, ownerKey: string, requestId?: string): Promise<void> {
    if (requestId === undefined) return;

    await BackgroundTaskRuntime.serialize(context, async (): Promise<void> => {
      await withState(context, ownerKey, (state: BackgroundTaskRuntimeState): Promise<void> => state.expire(requestId));
    });
  }

  private static async serialize(context: common.Context, action: () => Promise<void>): Promise<void> {
    const next = BackgroundTaskRuntime.mutation
      .then(async (): Promise<void> => {
        const app = context.getApplicationContext();
        const file = await fs.open(`${app.filesDir}/ExpoBackgroundTask.lock`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);

        try {
          await file.lock(true);
          await action();
        } finally {
          fs.closeSync(file);
        }
      });

    BackgroundTaskRuntime.mutation = next.catch((): void => {});
    await next;
  }
}

async function withState(
  context: common.Context,
  ownerKey: string,
  operation: (state: BackgroundTaskRuntimeState) => Promise<void>,
): Promise<void> {
  const app = context.getApplicationContext();
  const database = await relationalStore.getRdbStore(app, { name: DATABASE_NAME, securityLevel: relationalStore.SecurityLevel.S2 });
  const store = new BackgroundTaskStore(context, database, ownerKey);

  try {
    await store.prepare(app);
    await operation(new BackgroundTaskRuntimeState(store));
  } finally {
    try {
      await database.close();
    } catch (error) {
      store.report(`Unable to close Expo BackgroundTask storage: ${String(error)}`);
    }
  }
}

function pendingWorkKey(requestId: string): string {
  return `${PENDING_WORK_KEY_PREFIX}${requestId}`;
}

function createRequestId(work: workScheduler.WorkInfo): string {
  return `${OWNER_PARAMETER_VALUE}:${work.workId}:${util.generateRandomUUID(true)}`;
}

export function isBackgroundTaskWork(
  work: workScheduler.WorkInfo,
  bundleName: string,
  abilityName: string,
  allowMissingGeneration: boolean = false,
): boolean {
  const parameters = ExpoTaskManagerWorkMetadata.parameters(work.parameters);
  const owner = ExpoTaskManagerWorkMetadata.owner(parameters, true);

  return (
    work.bundleName === bundleName &&
    work.abilityName === abilityName &&
    parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    owner === bundleName &&
    (allowMissingGeneration || schedulerGenerationFromWork(work).length > 0)
  );
}

function toScheduledWork(work: workScheduler.WorkInfo): ScheduledWork {
  return new ScheduledWork(work.workId, work.bundleName, work.abilityName, schedulerGenerationFromWork(work));
}

export function schedulerGenerationFromWork(work: workScheduler.WorkInfo): string {
  const value = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[SCHEDULER_GENERATION_PARAMETER];

  return typeof value === 'string' && value.length <= MAXIMUM_SCHEDULER_GENERATION_LENGTH ? value : '';
}

async function finishWorkBestEffort(work: workScheduler.WorkInfo, startedAt: number): Promise<void> {
  try {
    await finishWork(toScheduledWork(work), startedAt);
  } catch (error) {
    console.error(`Unable to finish Expo BackgroundTask execution: ${String(error)}`);
  }
}

async function finishWork(work: ScheduledWork, startedAt: number): Promise<void> {
  // After timeout, stopping this ID could stop a later run of the same periodic work.
  if (work.schedulerGeneration.length === 0 || !isWithinExecutionWindow(startedAt)) return;

  const works = await workScheduler.obtainAllWorks();
  const current = works.find((value: workScheduler.WorkInfo): boolean => {
    return (
      value.workId === work.workId &&
      isBackgroundTaskWork(value, work.bundleName, work.abilityName) &&
      schedulerGenerationFromWork(value) === work.schedulerGeneration
    );
  });

  if (current !== undefined && isWithinExecutionWindow(startedAt)) stopBackgroundTaskWork(current, false);
}

export function stopBackgroundTaskWork(work: workScheduler.WorkInfo, cancel: boolean): void {
  work.parameters = ExpoTaskManagerWorkMetadata.parameters(work.parameters);
  workScheduler.stopWork(work, cancel);
}

function isWithinExecutionWindow(startedAt: number): boolean {
  const elapsed = Date.now() - startedAt;
  return elapsed >= 0 && elapsed < WORK_SCHEDULER_EXECUTION_WINDOW_MS;
}
