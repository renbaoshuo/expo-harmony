/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
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
  PENDING_WORK_MAXIMUM_AGE_MS,
  ScheduledWork,
  StoredPendingWork,
  WORK_SCHEDULER_EXECUTION_WINDOW_MS,
} from './BackgroundTaskRuntimeState.ts';

const PREFERENCES_NAME: string = 'ExpoBackgroundTask';
const PENDING_WORK_KEY_PREFIX: string = 'pendingWork.';
const CORRUPTED_PENDING_WORKS_KEY: string = 'corruptedPendingWorks';
const MAXIMUM_CORRUPTION_DIAGNOSTICS: number = 20;

class PreferencesRuntimeDriver implements BackgroundTaskRuntimeDriver {
  private readonly context: common.Context;
  private readonly store: preferences.Preferences;
  private readonly ownerKey: string;

  constructor(context: common.Context, store: preferences.Preferences, ownerKey: string) {
    this.context = context;
    this.store = store;
    this.ownerKey = ownerKey;
  }

  async read(): Promise<StoredPendingWork[]> {
    return await readPendingWorks(this.store, this.ownerKey);
  }

  async save(work: StoredPendingWork): Promise<void> {
    await this.store.put(pendingWorkKey(work.requestId), JSON.stringify(work));
    await this.store.flush();
  }

  async remove(requestId: string): Promise<void> {
    await this.store.delete(pendingWorkKey(requestId));
    await this.store.flush();
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
    bundleName: string,
    abilityName: string,
    startedAt: number,
    wasStopped: () => boolean,
  ): Promise<string | undefined> {
    if (!isOwnedWork(work, bundleName, abilityName)) {
      console.warn(`Expo BackgroundTask ignored WorkScheduler work ${work.workId} with invalid ownership metadata.`);
      return undefined;
    }

    let requestId: string | undefined;

    try {
      await BackgroundTaskRuntime.serialize(context, async (): Promise<void> => {
        if (wasStopped()) return;

        try {
          const works = await workScheduler.obtainAllWorks();
          const current = works.some(
            (value: workScheduler.WorkInfo): boolean =>
              value.workId === work.workId &&
              isOwnedWork(value, bundleName, abilityName) &&
              schedulerGenerationFromWork(value) === schedulerGenerationFromWork(work),
          );
          if (wasStopped()) return;
          if (!current) {
            console.warn(`Expo BackgroundTask ignored replaced or removed WorkScheduler work ${work.workId}.`);
            return;
          }
          // The system execution window includes the time spent waiting for the lock.
          if (startedAt + PENDING_WORK_MAXIMUM_AGE_MS <= Date.now()) {
            throw new Error('Expo BackgroundTask callback expired before it reached TaskManager.');
          }

          const state = await createState(context, taskManagerOwnerFromWork(work));
          const id = createRequestId(work);

          requestId = await state.start(toScheduledWork(work), id, Date.now(), startedAt, wasStopped);
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
    bundleName: string,
    abilityName: string,
    request: Promise<string | undefined> | undefined,
  ): void {
    if (!isOwnedWork(work, bundleName, abilityName)) return;

    Promise.resolve(request)
      .then(async (requestId: string | undefined): Promise<void> => {
        await BackgroundTaskRuntime.serialize(context, async (): Promise<void> => {
          const state = await createState(context, taskManagerOwnerFromWork(work));

          await state.stop(toScheduledWork(work), requestId, Date.now());
        });
      })
      .catch((error: Object): void => {
        console.error(`Unable to expire Expo BackgroundTask execution: ${String(error)}`);
      });
  }

  static async finish(context: common.Context, ownerKey: string, requestId?: string): Promise<void> {
    await BackgroundTaskRuntime.serialize(context, async (): Promise<void> => {
      const state = await createState(context, ownerKey);

      await state.complete(requestId);
    });
  }

  static async expire(context: common.Context, ownerKey: string, requestId?: string): Promise<void> {
    await BackgroundTaskRuntime.serialize(context, async (): Promise<void> => {
      const state = await createState(context, ownerKey);

      await state.expire(requestId);
    });
  }

  private static async serialize(context: common.Context, action: () => Promise<void>): Promise<void> {
    const next = BackgroundTaskRuntime.mutation
      .catch((): void => {})
      .then(async (): Promise<void> => {
        const app = context.getApplicationContext();
        const file = await fs.open(`${app.filesDir}/ExpoBackgroundTask.lock`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);

        try {
          await file.lock(true);
          await preferences.removePreferencesFromCache(app, PREFERENCES_NAME);
          await action();
        } finally {
          fs.closeSync(file);
        }
      });

    BackgroundTaskRuntime.mutation = next.catch((): void => {});
    await next;
  }
}

async function createState(context: common.Context, ownerKey: string): Promise<BackgroundTaskRuntimeState> {
  const store = await preferences.getPreferences(context.getApplicationContext(), { name: PREFERENCES_NAME });

  return new BackgroundTaskRuntimeState(new PreferencesRuntimeDriver(context, store, ownerKey));
}

function taskManagerOwnerFromWork(work: workScheduler.WorkInfo): string {
  const owner = ExpoTaskManagerWorkMetadata.owner(ExpoTaskManagerWorkMetadata.parameters(work.parameters), true);
  if (owner === undefined) {
    throw new Error('Expo BackgroundTask work is missing its TaskManager owner.');
  }

  return owner;
}

async function readPendingWorks(store: preferences.Preferences, ownerKey: string): Promise<StoredPendingWork[]> {
  const raw = await store.getAll();
  const values = raw as Record<string, ESObject>;
  const works: StoredPendingWork[] = [];
  let changed = false;

  for (const key of Object.keys(values)) {
    if (!key.startsWith(PENDING_WORK_KEY_PREFIX)) continue;

    const pending = decodePendingWork(values[key]);
    if (pending !== undefined && key === pendingWorkKey(pending.requestId)) {
      if (pending.bundleName === ownerKey && pending.abilityName === WORK_SCHEDULER_EXTENSION_NAME) works.push(pending);
      continue;
    }

    await recordCorruptionDiagnostic(store, key, values[key]);
    await store.delete(key);
    changed = true;
  }

  if (changed) {
    await store.flush();
    console.error('Expo BackgroundTask repaired corrupted pending work storage.');
  }

  return works;
}

function pendingWorkKey(requestId: string): string {
  return `${PENDING_WORK_KEY_PREFIX}${requestId}`;
}

async function recordCorruptionDiagnostic(store: preferences.Preferences, key: string, value: ESObject): Promise<void> {
  const raw = await store.get(CORRUPTED_PENDING_WORKS_KEY, '[]');
  let diagnostics: ESObject[] = [];
  if (typeof raw === 'string') {
    try {
      const parsed: ESObject = JSON.parse(raw);
      if (Array.isArray(parsed)) diagnostics = parsed.slice(-MAXIMUM_CORRUPTION_DIAGNOSTICS + 1);
    } catch (_) {}
  }
  diagnostics.push({ key, valueType: value === null ? 'null' : typeof value, recoveredAt: Date.now() });
  await store.put(CORRUPTED_PENDING_WORKS_KEY, JSON.stringify(diagnostics));
}

function createRequestId(work: workScheduler.WorkInfo): string {
  return `${OWNER_PARAMETER_VALUE}:${work.workId}:${util.generateRandomUUID(true)}`;
}

function isOwnedWork(work: workScheduler.WorkInfo, bundleName: string, abilityName: string): boolean {
  const parameters = ExpoTaskManagerWorkMetadata.parameters(work.parameters);
  const taskManagerOwner = ExpoTaskManagerWorkMetadata.owner(parameters, true);
  return (
    work.bundleName === bundleName &&
    work.abilityName === abilityName &&
    parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    taskManagerOwner === bundleName &&
    schedulerGenerationFromWork(work).length > 0
  );
}

function toScheduledWork(work: workScheduler.WorkInfo): ScheduledWork {
  return new ScheduledWork(work.workId, work.bundleName, work.abilityName, schedulerGenerationFromWork(work));
}

function schedulerGenerationFromWork(work: workScheduler.WorkInfo): string {
  const value = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[SCHEDULER_GENERATION_PARAMETER];

  return typeof value === 'string' ? value : '';
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
      isOwnedWork(value, work.bundleName, work.abilityName) &&
      schedulerGenerationFromWork(value) === work.schedulerGeneration
    );
  });

  if (current !== undefined && isWithinExecutionWindow(startedAt)) workScheduler.stopWork(current, false);
}

function isWithinExecutionWindow(startedAt: number): boolean {
  const elapsed = Date.now() - startedAt;
  return elapsed >= 0 && elapsed < WORK_SCHEDULER_EXECUTION_WINDOW_MS;
}
