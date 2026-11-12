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
import { decodePendingWorks, PENDING_WORK_SCHEMA_VERSION } from './BackgroundFetchStorageCodec.ts';

const PREFERENCES_NAME: string = 'ExpoBackgroundFetch';
const PENDING_WORKS_KEY: string = 'pendingWorks';
const CORRUPTED_PENDING_WORKS_KEY: string = 'corruptedPendingWorks';
const MAXIMUM_CORRUPTION_DIAGNOSTICS: number = 20;

export enum BackgroundFetchState {
  Background,
  Foreground,
  Terminated,
  Rebooted,
}

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
    registrationGeneration: number,
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

  toWorkInfo(): workScheduler.WorkInfo {
    return { workId: this.workId, bundleName: this.bundleName, abilityName: this.abilityName };
  }

  belongsTo(bundleName: string): boolean {
    return this.bundleName === bundleName && this.ownerKey === bundleName && this.abilityName === WORK_SCHEDULER_EXTENSION_NAME;
  }

  matches(work: workScheduler.WorkInfo): boolean {
    return this.belongsTo(work.bundleName) && this.workId === work.workId && this.schedulerGeneration === schedulerGenerationFromWork(work);
  }
}

export class BackgroundFetchRuntime {
  private static mutation: Promise<void> = Promise.resolve();

  static async updateSchedule(context: common.Context, action: () => Promise<void>): Promise<void> {
    await BackgroundFetchRuntime.serialize(context, action);
  }

  static setState(context: common.Context, owner: string, state: BackgroundFetchState): void {
    const path = statePath(context, owner);
    const temporary = `${path}.${util.generateRandomUUID(true)}`;
    const value = `${bootCount(context)}:${state}`;

    try {
      const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);

      try {
        fs.writeSync(file.fd, value);
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }

      fs.renameSync(temporary, path);
    } finally {
      if (fs.accessSync(temporary)) fs.unlinkSync(temporary);
    }
  }

  static async getState(context: common.Context, owner: string): Promise<BackgroundFetchState> {
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

    try {
      await BackgroundFetchRuntime.serialize(context, async (): Promise<void> => {
        if (isStopped()) return;

        const taskName = taskNameFromWork(work);
        const generation = registrationGenerationFromWork(work);
        const current = (await workScheduler.obtainAllWorks()).find(
          (value: workScheduler.WorkInfo): boolean =>
            value.workId === work.workId &&
            isOwnedWork(value, owner) &&
            schedulerGenerationFromWork(value) === schedulerGenerationFromWork(work) &&
            taskNameFromWork(value) === taskName &&
            registrationGenerationFromWork(value) === generation,
        );
        if (current === undefined || isStopped()) return;

        const stopAt = startedAt + WORK_SCHEDULER_EXECUTION_WINDOW_MS;
        if (taskName === undefined) {
          await finishWorkBestEffort(work, schedulerGenerationFromWork(work), stopAt);
          console.error('Expo Background Fetch ignored a scheduler callback without a task name.');
          return;
        }
        if (generation === undefined) {
          await finishWorkBestEffort(work, schedulerGenerationFromWork(work), stopAt);
          return;
        }

        const store = await openStore(context);
        let works = await readPendingWorks(store);
        const stale = works.filter((pending: PendingWork): boolean => pending.belongsTo(owner) && workStopDeadline(pending) <= startedAt);
        if (stale.length > 0) {
          try {
            await expirePendingWorks(context, store, works, stale);
          } catch (error) {
            console.error(String(error));
          }

          works = await readPendingWorks(store);
        }
        if (isStopped()) return;

        const pending = new PendingWork(
          createRequestId(work),
          work.workId,
          work.bundleName,
          work.abilityName,
          taskName,
          owner,
          schedulerGenerationFromWork(work),
          stopAt - WORK_SCHEDULER_CLEANUP_MARGIN_MS,
          generation,
        );
        const state = readState(context, pending.ownerKey);
        const parameters = ExpoTaskManagerWorkMetadata.parameters(current.parameters);
        const stopOnTerminate = parameters?.[STOP_ON_TERMINATE_PARAMETER];
        const startOnBoot = parameters?.[START_ON_BOOT_PARAMETER];
        if (
          pending.expiresAt <= Date.now() ||
          state === BackgroundFetchState.Foreground ||
          (state === BackgroundFetchState.Terminated && stopOnTerminate !== false && stopOnTerminate !== 'false') ||
          (state === BackgroundFetchState.Rebooted && startOnBoot !== true && startOnBoot !== 'true')
        ) {
          await finishPendingWorkIfIdle(pending, works);
          return;
        }

        works.push(pending);
        try {
          await writePendingWorks(store, works);
          if (isStopped()) {
            await writePendingWorks(store, works.filter((item: PendingWork): boolean => item.requestId !== pending.requestId));
            return;
          }

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
          await expirePendingWorks(context, store, works, [pending]);
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
          const store = await openStore(context);
          const works = await readPendingWorks(store);
          const matching = works.filter((pending: PendingWork): boolean =>
            pending.matches(work) &&
            (requestId === undefined ? pending.expiresAt <= stoppedAt : pending.requestId === requestId),
          );
          await expirePendingWorks(context, store, works, matching);
        });
      })
      .catch((error: Object): void => {
        console.error(`Unable to expire Expo Background Fetch execution: ${String(error)}`);
      });
  }

  static async expire(context: common.UIAbilityContext, work: workScheduler.WorkInfo): Promise<void> {
    if (!isOwnedWork(work, context.abilityInfo.bundleName)) return;

    await BackgroundFetchRuntime.serialize(context, async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);
      const matching = works.filter((pending: PendingWork): boolean => pending.matches(work));
      await expirePendingWorks(context, store, works, matching);
    });
  }

  static async expireAll(context: common.UIAbilityContext): Promise<void> {
    await BackgroundFetchRuntime.serialize(context, async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);
      const owned = works.filter((pending: PendingWork): boolean => pending.belongsTo(context.abilityInfo.bundleName));
      await expirePendingWorks(context, store, works, owned);
    });
  }

  static async finish(context: common.UIAbilityContext, requestId?: string): Promise<void> {
    if (requestId === undefined) {
      console.error('Expo Background Fetch ignored a completion without a TaskManager request id.');
      return;
    }

    await BackgroundFetchRuntime.serialize(context, async (): Promise<void> => {
      const store = await openStore(context);
      const works = await readPendingWorks(store);
      const pending = works.find((work: PendingWork): boolean => work.requestId === requestId && work.belongsTo(context.abilityInfo.bundleName));
      if (pending === undefined) return;

      const remaining = works.filter((work: PendingWork): boolean => work.requestId !== requestId);
      await writePendingWorks(store, remaining);
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
          await preferences.removePreferencesFromCache(app, PREFERENCES_NAME);
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
  const count = deviceInfo.sdkApiVersion >= 21 ? deviceInfo.bootCount : Number(settings.getValueSync(context, settings.general.BOOT_COUNTING, '-1'));

  if (!Number.isSafeInteger(count) || count < 0) {
    throw new Error('Unable to read the system boot count for Expo Background Fetch.');
  }

  return count;
}

function statePath(context: common.Context, owner: string): string {
  return `${context.getApplicationContext().filesDir}/ExpoBackgroundFetch.${encodeURIComponent(owner)}.state`;
}

function readState(context: common.Context, owner: string): BackgroundFetchState {
  const path = statePath(context, owner);
  const value = fs.accessSync(path) ? fs.readTextSync(path) : '';
  const boot = bootCount(context);

  if (value === `${boot}:${BackgroundFetchState.Foreground}`) return BackgroundFetchState.Foreground;
  if (value === `${boot}:${BackgroundFetchState.Terminated}`) return BackgroundFetchState.Terminated;
  if (value !== '' && value !== `${boot}:${BackgroundFetchState.Background}`) return BackgroundFetchState.Rebooted;

  return BackgroundFetchState.Background;
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
    const remaining = all.filter((pending: PendingWork): boolean => !remove.has(pending.requestId));
    await writePendingWorks(store, remaining);
    for (const pending of matching) {
      if (remove.has(pending.requestId)) await finishPendingWorkIfIdle(pending, remaining);
    }
  }
  if (failures > 0) throw new Error(`Unable to expire ${failures} Expo Background Fetch execution request(s).`);
}

async function finishPendingWorkIfIdle(work: PendingWork, remaining: PendingWork[]): Promise<void> {
  const workInfo = work.toWorkInfo();
  const active = remaining.some(
    (pending: PendingWork): boolean =>
      pending.belongsTo(work.bundleName) && pending.workId === work.workId &&
      pending.schedulerGeneration === work.schedulerGeneration && isWithinExecutionWindow(workStopDeadline(pending)),
  );
  if (!active) await finishWorkBestEffort(workInfo, work.schedulerGeneration, workStopDeadline(work));
}

async function openStore(context: common.Context): Promise<preferences.Preferences> {
  return await preferences.getPreferences(context.getApplicationContext(), { name: PREFERENCES_NAME });
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
        pending.registrationGeneration,
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

function isOwnedWork(work: workScheduler.WorkInfo, bundleName: string): boolean {
  const parameters = ExpoTaskManagerWorkMetadata.parameters(work.parameters);
  return (
    work.bundleName === bundleName &&
    work.abilityName === WORK_SCHEDULER_EXTENSION_NAME &&
    parameters?.[OWNER_PARAMETER] === OWNER_PARAMETER_VALUE &&
    ExpoTaskManagerWorkMetadata.owner(parameters, true) === bundleName &&
    schedulerGenerationFromWork(work).length > 0
  );
}

function taskNameFromWork(work: workScheduler.WorkInfo): string | undefined {
  const value = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[TASK_NAME_PARAMETER];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function schedulerGenerationFromWork(work: workScheduler.WorkInfo): string {
  const value = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[SCHEDULER_GENERATION_PARAMETER];
  return typeof value === 'string' ? value : '';
}

function registrationGenerationFromWork(work: workScheduler.WorkInfo): number | undefined {
  const raw = ExpoTaskManagerWorkMetadata.parameters(work.parameters)?.[REGISTRATION_GENERATION_PARAMETER];
  const value = typeof raw === 'string' && /^[1-9][0-9]*$/.test(raw) ? Number(raw) : raw;
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 ? value : undefined;
}

function createRequestId(work: workScheduler.WorkInfo): string {
  return `${OWNER_PARAMETER_VALUE}:${work.workId}:${util.generateRandomUUID(true)}`;
}

function workStopDeadline(work: PendingWork): number {
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
