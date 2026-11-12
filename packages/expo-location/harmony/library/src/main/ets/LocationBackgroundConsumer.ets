/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { abilityAccessCtrl, common, wantAgent } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';
import { ExpoAppLifecycleState, ExpoModuleContext, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { ExpoTaskConsumer, ExpoTaskManagerRegistry, ExpoTaskRecord } from '@expo-harmony/expo-task-manager';

import { LOCATION_OPTIONS, LocationRecord, locationRequest, message } from './LocationRecords';
import {
  BACKGROUND_TASK_TYPE,
  continuousLocationRequest,
  deliverLocationTask,
  hasBackgroundConfiguration,
  hasLocationTaskPermission,
} from './LocationTaskSupport';

const MAXIMUM_BATCH_SIZE: number = 100;
const LOCATION_NOTIFICATION_REQUEST_CODE: number = 24_005_701;
const BACKGROUND_PREFERENCES: string = 'ExpoLocationBackground';
const CANCELLED_TASKS_KEY: string = 'cancelledTasks';

class CancelledTask {
  name: string;
  generation: number;

  constructor(name: string, generation: number) {
    this.name = name;
    this.generation = generation;
  }
}

class BackgroundOptions {
  distance: number;
  interval: number;
  timeout: number;

  constructor(options: ESObject) {
    this.distance = deferredValue(options.deferredUpdatesDistance, 'deferredUpdatesDistance');
    this.interval = deferredValue(options.deferredUpdatesInterval, 'deferredUpdatesInterval');
    this.timeout = deferredValue(options.deferredUpdatesTimeout, 'deferredUpdatesTimeout');
  }
}

function deferredValue(value: ESObject, name: string): number {
  if (value === undefined || value === null) return 0;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', `${name} must be a finite nonnegative number.`);
  }

  return value as number;
}

export function validateBackgroundOptions(options: ESObject): void {
  LOCATION_OPTIONS.decode(options, 'options');
  new BackgroundOptions(options);
}

function distanceBetween(from: LocationRecord, to: LocationRecord): number {
  const radians = Math.PI / 180;
  const latitude = (to.coords.latitude - from.coords.latitude) * radians;
  const longitude = (to.coords.longitude - from.coords.longitude) * radians;
  const a = Math.sin(latitude / 2) ** 2 +
    Math.cos(from.coords.latitude * radians) * Math.cos(to.coords.latitude * radians) * Math.sin(longitude / 2) ** 2;
  return 12_742_000 * Math.asin(Math.min(1, Math.sqrt(a)));
}

class BackgroundWatch {
  readonly task: ExpoTaskRecord;
  readonly callback: (location: geoLocationManager.Location) => void;
  private readonly ability: common.UIAbilityContext;
  private readonly options: BackgroundOptions;
  private readonly hasPermission: () => boolean;
  private readonly shouldDefer: () => boolean;
  private active: boolean = false;
  private attached: boolean = false;
  private pending: LocationRecord[] = [];
  private previous?: LocationRecord;
  private distance: number = 0;
  private lastSent: number = 0;
  private timer: number = -1;
  private delivering: boolean = false;
  private forcePending: boolean = false;

  constructor(ability: common.UIAbilityContext, task: ExpoTaskRecord, hasPermission: () => boolean, shouldDefer: () => boolean) {
    this.ability = ability;
    this.task = task;
    this.options = new BackgroundOptions(task.options);
    this.hasPermission = hasPermission;
    this.shouldDefer = shouldDefer;
    this.callback = (value: geoLocationManager.Location): void => this.receive(value);
  }

  start(): void {
    this.attached = true;
    geoLocationManager.on('locationChange', locationRequest(LOCATION_OPTIONS.decode(this.task.options, 'options')), this.callback);
    this.active = true;
  }

  stop(): void {
    this.active = false;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    this.pending = [];

    if (this.attached) {
      geoLocationManager.off('locationChange', this.callback);
      this.attached = false;
    }
  }

  private receive(value: geoLocationManager.Location): void {
    if (!this.active || !this.hasPermission()) return;

    try {
      const location = new LocationRecord(value);
      if (this.pending.length >= MAXIMUM_BATCH_SIZE) this.pending.shift();
      this.pending.push(location);
      if (this.previous !== undefined) this.distance += distanceBetween(this.previous, location);
      this.previous = location;
      if (this.options.timeout > 0 && this.timer < 0) {
        this.timer = setTimeout((): void => {
          this.timer = -1;
          this.forcePending = true;
          this.flush();
        }, Math.min(this.options.timeout, 2_147_483_647));
      }
      this.flush();
    } catch (error) {
      console.warn(`Unable to read Expo background location: ${message(error)}`);
    }
  }

  flush(): void {
    if (!this.active || this.delivering || this.pending.length === 0 || !this.hasPermission()) return;

    const now = Date.now();
    if (!this.forcePending && this.shouldDefer() && this.lastSent > 0 && this.pending.length < MAXIMUM_BATCH_SIZE &&
      (now - this.lastSent < this.options.interval || this.distance < this.options.distance)) return;

    const locations = this.pending;
    this.pending = [];
    this.forcePending = false;
    this.lastSent = now;
    this.distance = 0;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    this.delivering = true;
    deliverLocationTask(this.ability, this.task, { locations })
      .catch((error: Object): void => console.warn(`Unable to queue Expo background location: ${message(error)}`))
      .finally((): void => {
        this.delivering = false;
        this.flush();
      });
  }
}

export class LocationBackgroundConsumer implements ExpoTaskConsumer {
  readonly taskType: string = BACKGROUND_TASK_TYPE;
  readonly consumerId: string = 'expo-location-background';
  readonly consumerVersion: number = 1;
  private context?: ExpoModuleContext;
  private ability?: common.UIAbilityContext;
  private id?: number;
  private mutation: Promise<void> = Promise.resolve();
  private readonly watches: Map<string, BackgroundWatch> = new Map();
  private readonly retired: Set<BackgroundWatch> = new Set();
  private readonly cancelled: Map<string, number> = new Map();
  private cancelledStore?: preferences.Preferences;
  private permissionObserver?: abilityAccessCtrl.AtManager;
  private readonly permissionChanged = (_info: abilityAccessCtrl.PermissionStateChangeInfo): void => {
    const context = this.context;
    if (context !== undefined && context.isValid) this.refresh(context);
  };
  private readonly taskCancelled = (event: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (event.id !== this.id) return;

    this.serialize(async (): Promise<void> => {
      if (event.id !== this.id) return;

      this.id = undefined;
      for (const watch of this.watches.values()) {
        this.cancelled.set(watch.task.taskName, watch.task.registrationGeneration);
      }

      try {
        await this.persistCancelled();
      } finally {
        await this.release();
      }
    }).catch(reportBackgroundFailure);
  };

  canExecute(context: ExpoModuleContext): boolean {
    return hasLocationTaskPermission(context);
  }

  async onTasksChanged(context: ExpoModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      const current = context.isHeadless ? this.context : context;

      for (const watch of this.watches.values()) {
        if (!tasks.some((task: ExpoTaskRecord): boolean =>
          task.taskName === watch.task.taskName && task.registrationGeneration === watch.task.registrationGeneration)) this.removeWatch(watch);
      }

      if (current === undefined || !current.isValid) {
        if (tasks.length === 0) await this.release();
        return;
      }

      this.context = current;
      const ability = current.uiAbilityContext;
      if (!hasBackgroundConfiguration(ability)) {
        await this.release();
        return;
      }

      await this.loadCancelled(ability);
      let pruned = false;

      for (const name of this.cancelled.keys()) {
        if (tasks.some((task: ExpoTaskRecord): boolean => task.taskName === name)) continue;

        this.cancelled.delete(name);
        pruned = true;
      }

      if (pruned) await this.persistCancelled();
      const active = tasks.filter((task: ExpoTaskRecord): boolean => this.cancelled.get(task.taskName) !== task.registrationGeneration);
      if (active.length === 0 || !hasLocationTaskPermission(current)) {
        await this.release();
        return;
      }
      if (this.ability !== undefined && this.ability !== ability) await this.release();
      if (this.id === undefined) {
        if (context.isHeadless || current.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) return;
        await this.start(ability);
      }

      this.releaseRetiredWatches();
      for (const watch of this.watches.values()) {
        if (active.some((task: ExpoTaskRecord): boolean =>
          task.taskName === watch.task.taskName && task.registrationGeneration === watch.task.registrationGeneration)) continue;
        this.removeWatch(watch);
      }
      for (const task of active) {
        const existing = this.watches.get(task.taskName);
        if (existing !== undefined) {
          existing.flush();
          continue;
        }

        const watch = new BackgroundWatch(
          ability,
          task,
          (): boolean => {
            const runtime = this.context;
            return runtime !== undefined && runtime.isValid && hasLocationTaskPermission(runtime);
          },
          (): boolean => this.context?.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND,
        );
        this.watches.set(task.taskName, watch);
        try {
          watch.start();
        } catch (error) {
          this.removeWatch(watch);
          throw new ExpoModuleError('ERR_LOCATION_BACKGROUND_UNAVAILABLE', message(error), error);
        }
      }
    });
  }

  refresh(context: ExpoModuleContext): void {
    if (context.isHeadless || !hasBackgroundConfiguration(context.uiAbilityContext)) return;

    ExpoTaskManagerRegistry.withRegisteredTasks(
      context.uiAbilityContext, ExpoTaskManagerRegistry.ownerKey(context), this.taskType,
      (tasks: ExpoTaskRecord[]): Promise<void> => this.onTasksChanged(context, tasks),
    ).catch(reportBackgroundFailure);
  }

  refreshAbility(ability: common.UIAbilityContext): void {
    const context = this.context;
    if (context !== undefined && context.isValid && context.uiAbilityContext === ability) this.refresh(context);
  }

  destroyAbility(ability: common.UIAbilityContext): void {
    this.serialize(async (): Promise<void> => {
      if (this.ability !== ability) return;

      this.context = undefined;
      await this.release();
    }).catch(reportBackgroundFailure);
  }

  private async start(ability: common.UIAbilityContext): Promise<void> {
    const info = ability.abilityInfo;
    const agent = await wantAgent.getWantAgent({
      wants: [{ bundleName: info.bundleName, moduleName: info.moduleName, abilityName: info.name }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: LOCATION_NOTIFICATION_REQUEST_CODE,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    });
    const request = continuousLocationRequest();
    request.wantAgent = agent;
    if (!request.isModeSupported()) {
      throw new ExpoModuleError('ERR_LOCATION_BACKGROUND_UNAVAILABLE', 'Continuous location tasks are unavailable on this device.');
    }

    this.ability = ability;
    backgroundTaskManager.on('continuousTaskCancel', this.taskCancelled);
    try {
      const task = await backgroundTaskManager.startBackgroundRunning(ability, request);
      if (task.continuousTaskId === undefined || task.continuousTaskId < 0) {
        throw new ExpoModuleError('ERR_LOCATION_BACKGROUND_UNAVAILABLE', 'HarmonyOS did not return a continuous location task ID.');
      }

      this.id = task.continuousTaskId;
      const observer = abilityAccessCtrl.createAtManager();
      observer.on('selfPermissionStateChange', ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION_IN_BACKGROUND'], this.permissionChanged);
      this.permissionObserver = observer;
    } catch (error) {
      await this.release();
      throw new ExpoModuleError('ERR_LOCATION_BACKGROUND_UNAVAILABLE', message(error), error);
    }
  }

  private removeWatch(watch: BackgroundWatch): void {
    this.watches.delete(watch.task.taskName);
    this.retired.add(watch);
    this.releaseWatch(watch);
  }

  private releaseWatch(watch: BackgroundWatch): void {
    try {
      watch.stop();
      this.retired.delete(watch);
    } catch (error) {
      // If revocation blocks off(), retain the inert callback for a later cleanup attempt.
      if (Number((error as BusinessError).code) === 401) this.retired.delete(watch);
      reportBackgroundFailure(error);
    }
  }

  private releaseRetiredWatches(): void {
    for (const watch of this.retired) this.releaseWatch(watch);
  }

  private async release(): Promise<void> {
    this.releaseRetiredWatches();
    for (const watch of this.watches.values()) this.removeWatch(watch);

    if (this.ability === undefined) return;

    if (this.id !== undefined) {
      const id = this.id;

      try {
        await backgroundTaskManager.stopBackgroundRunning(this.ability, id);
      } catch (error) {
        const tasks = await backgroundTaskManager.getAllContinuousTasks(this.ability, true);
        if (tasks.some((task: backgroundTaskManager.ContinuousTaskInfo): boolean => task.continuousTaskId === id)) {
          throw new ExpoModuleError('ERR_LOCATION_BACKGROUND_STOP', message(error), error);
        }
      }

      this.id = undefined;
    }
    this.permissionObserver?.off(
      'selfPermissionStateChange', ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION_IN_BACKGROUND'], this.permissionChanged,
    );
    this.permissionObserver = undefined;
    backgroundTaskManager.off('continuousTaskCancel', this.taskCancelled);
    this.ability = undefined;
  }

  private async serialize(action: () => Promise<void>): Promise<void> {
    const next = this.mutation.then(action);
    this.mutation = next.catch((): void => {});
    await next;
  }

  private async loadCancelled(ability: common.UIAbilityContext): Promise<void> {
    if (this.cancelledStore !== undefined) return;

    const store = await preferences.getPreferences(ability.getApplicationContext(), { name: BACKGROUND_PREFERENCES });
    const raw = await store.get(CANCELLED_TASKS_KEY, '[]');
    if (typeof raw === 'string') {
      try {
        const tasks = JSON.parse(raw) as CancelledTask[];
        for (const task of tasks) {
          if (typeof task.name === 'string' && Number.isSafeInteger(task.generation)) this.cancelled.set(task.name, task.generation);
        }
      } catch (_) {}
    }
    this.cancelledStore = store;
  }

  private async persistCancelled(): Promise<void> {
    const store = this.cancelledStore;
    if (store === undefined) return;

    const tasks: CancelledTask[] = [];
    this.cancelled.forEach((generation: number, name: string): void => {
      tasks.push(new CancelledTask(name, generation));
    });
    await store.put(CANCELLED_TASKS_KEY, JSON.stringify(tasks));
    await store.flush();
  }
}

function reportBackgroundFailure(error: Object): void {
  console.warn(`Unable to update Expo continuous location: ${message(error)}`);
}
