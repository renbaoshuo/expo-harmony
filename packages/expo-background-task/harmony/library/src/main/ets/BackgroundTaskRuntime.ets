import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { ExpoTaskManagerBackgroundQueue, ExpoTaskManagerWorkMetadata } from '@expo-harmony/expo-task-manager';

import { BACKGROUND_TASK_TYPE, OWNER_PARAMETER, OWNER_PARAMETER_VALUE } from './BackgroundTaskConstants';
import {
  BackgroundTaskRuntimeDriver,
  BackgroundTaskRuntimeState,
  decodePendingWork,
  PENDING_WORK_MAXIMUM_AGE_MS,
  ScheduledWork,
  StoredPendingWork,
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
    return await readPendingWorks(this.store);
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

  async stop(work: ScheduledWork): Promise<void> {
    finishWork(toWorkInfo(work));
  }

  report(message: string): void {
    console.error(message);
  }
}

export class BackgroundTaskRuntime {
  private static mutation: Promise<void> = Promise.resolve();

  static async start(context: common.Context, work: workScheduler.WorkInfo, bundleName: string, abilityName: string): Promise<string | undefined> {
    if (!isOwnedWork(work, bundleName, abilityName)) return undefined;

    let requestId: string | undefined;
    try {
      await BackgroundTaskRuntime.serialize(async (): Promise<void> => {
        const state = await createState(context, taskManagerOwnerFromWork(work));
        const id = createRequestId(work);

        requestId = await state.start(toScheduledWork(work), id, Date.now());
      });
    } catch (error) {
      finishWorkBestEffort(work);
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

    BackgroundTaskRuntime.serialize(async (): Promise<void> => {
      const requestId = request === undefined ? undefined : await request;
      const state = await createState(context, taskManagerOwnerFromWork(work));

      await state.stop(toScheduledWork(work), requestId, Date.now());
    }).catch((error: Object): void => {
      console.error(`Unable to expire Expo BackgroundTask execution: ${String(error)}`);
    });
  }

  static async finish(context: common.Context, ownerKey: string, requestId?: string): Promise<void> {
    await BackgroundTaskRuntime.serialize(async (): Promise<void> => {
      const state = await createState(context, ownerKey);

      await state.complete(requestId);
    });
  }

  static async expire(context: common.Context, ownerKey: string, requestId?: string): Promise<void> {
    await BackgroundTaskRuntime.serialize(async (): Promise<void> => {
      const state = await createState(context, ownerKey);

      await state.expire(requestId);
    });
  }

  private static async serialize(action: () => Promise<void>): Promise<void> {
    const next = BackgroundTaskRuntime.mutation.catch((): void => {}).then(action);

    BackgroundTaskRuntime.mutation = next.catch((): void => {});
    await next;
  }
}

async function createState(context: common.Context, ownerKey: string): Promise<BackgroundTaskRuntimeState> {
  const store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });

  return new BackgroundTaskRuntimeState(new PreferencesRuntimeDriver(context, store, ownerKey));
}

function taskManagerOwnerFromWork(work: workScheduler.WorkInfo): string {
  const value = ExpoTaskManagerWorkMetadata.owner(work.parameters, true);
  if (value === undefined) {
    throw new Error('Expo BackgroundTask work is missing its TaskManager owner.');
  }
  return value;
}

async function readPendingWorks(store: preferences.Preferences): Promise<StoredPendingWork[]> {
  const raw = await store.getAll();
  const values = raw as Record<string, ESObject>;
  const works: StoredPendingWork[] = [];
  let changed = false;

  for (const key of Object.keys(values)) {
    if (!key.startsWith(PENDING_WORK_KEY_PREFIX)) continue;

    const pending = decodePendingWork(values[key]);
    if (pending !== undefined) {
      works.push(pending);
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
  const taskManagerOwner = ExpoTaskManagerWorkMetadata.owner(work.parameters, true);
  return (
    work.bundleName === bundleName &&
    work.abilityName === abilityName &&
    work.parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    typeof taskManagerOwner === 'string' &&
    taskManagerOwner.length > 0
  );
}

function toScheduledWork(work: workScheduler.WorkInfo): ScheduledWork {
  return new ScheduledWork(work.workId, work.bundleName, work.abilityName);
}

function toWorkInfo(work: ScheduledWork): workScheduler.WorkInfo {
  return {
    workId: work.workId,
    bundleName: work.bundleName,
    abilityName: work.abilityName,
  };
}

function finishWorkBestEffort(work: workScheduler.WorkInfo): void {
  try {
    finishWork(work);
  } catch (error) {
    console.error(`Unable to finish Expo BackgroundTask execution: ${String(error)}`);
  }
}

function finishWork(work: workScheduler.WorkInfo): void {
  workScheduler.stopWork(work, false);
}
