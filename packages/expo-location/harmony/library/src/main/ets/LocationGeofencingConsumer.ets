/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';
import { ExpoModuleContext, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { ExpoTaskConsumer, ExpoTaskManagerRegistry, ExpoTaskRecord } from '@expo-harmony/expo-task-manager';

import { message, validCoordinate } from './LocationRecords';
import { FENCES_KEY, GEOFENCE_EVENT_EXPIRY_MS, takeGeofenceTransitions, withGeofenceStore } from './LocationFenceIngress';
import { FENCE_EXTENSION_NAME, GEOFENCE_TASK_TYPE, deliverLocationTask, hasGeofenceConfiguration, hasLocationTaskPermission } from './LocationTaskSupport';

const MAXIMUM_FENCES: number = 100;
const FENCE_LIFETIME_MS: number = 31_536_000_000;
const DUPLICATE_WINDOW_MS: number = 2000;

// These values are part of Expo Location's JS event and region contracts.
enum GeofencingEventType {
  Enter = 1,
  Exit = 2,
}

enum GeofencingRegionState {
  Inside = 1,
  Outside = 2,
}

class Region {
  identifier: string;
  latitude: number;
  longitude: number;
  radius: number;
  notifyOnEnter: boolean;
  notifyOnExit: boolean;
  state?: GeofencingRegionState;

  constructor(input: ESObject) {
    if (input === null || typeof input !== 'object' || Array.isArray(input) ||
      typeof input.latitude !== 'number' || typeof input.longitude !== 'number' ||
      !validCoordinate(input.latitude, input.longitude) ||
      typeof input.radius !== 'number' || !Number.isFinite(input.radius) || input.radius <= 0) {
      throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', 'Every geofence needs valid WGS-84 coordinates and a positive radius.');
    }

    if ((input.identifier !== undefined && (typeof input.identifier !== 'string' || input.identifier.length === 0)) ||
      (input.notifyOnEnter !== undefined && typeof input.notifyOnEnter !== 'boolean') ||
      (input.notifyOnExit !== undefined && typeof input.notifyOnExit !== 'boolean') ||
      (input.notifyOnEnter === false && input.notifyOnExit === false)) {
      throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', 'Every geofence needs a nonempty identifier, if supplied, and at least one transition.');
    }

    this.identifier = input.identifier ?? util.generateRandomUUID();
    this.latitude = input.latitude;
    this.longitude = input.longitude;
    this.radius = input.radius;
    this.notifyOnEnter = input.notifyOnEnter ?? true;
    this.notifyOnExit = input.notifyOnExit ?? true;
  }
}

class GeofenceOptions {
  regions: Region[];

  constructor(regions: Region[]) {
    this.regions = regions;
  }
}

export function geofenceOptions(input: ESObject): ESObject {
  return new GeofenceOptions(readRegions(input));
}

function readRegions(input: ESObject): Region[] {
  if (!Array.isArray(input.regions) || input.regions.length === 0 || input.regions.length > MAXIMUM_FENCES) {
    throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', `Geofencing requires 1–${MAXIMUM_FENCES} regions per app.`);
  }

  const regions = (input.regions as ESObject[]).map((item: ESObject): Region => new Region(item));
  if (new Set<string>(regions.map((region: Region): string => region.identifier)).size !== regions.length) {
    throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', 'Geofence identifiers must be unique within a task.');
  }

  return regions;
}

class Fence {
  id: number;
  owner: string;
  taskName: string;
  generation: number;
  region: Region;
  lastTransition?: number;
  lastDeliveredAt?: number;

  constructor(id: number, task: ExpoTaskRecord, region: Region) {
    this.id = id;
    this.owner = task.ownerKey;
    this.taskName = task.taskName;
    this.generation = task.registrationGeneration;
    this.region = region;
  }
}

class FenceTarget {
  task: ExpoTaskRecord;
  region: Region;

  constructor(task: ExpoTaskRecord, region: Region) {
    this.task = task;
    this.region = region;
  }
}

function sameFence(fence: geoLocationManager.Geofence, region: Region): boolean {
  return fence.latitude === region.latitude && fence.longitude === region.longitude && fence.radius === region.radius &&
    (fence.coordinateSystemType === undefined || fence.coordinateSystemType === geoLocationManager.CoordinateSystemType.WGS84);
}

function targetsMatch(target: FenceTarget, fence: Fence): boolean {
  const region = target.region;
  return target.task.ownerKey === fence.owner && target.task.taskName === fence.taskName &&
    region.identifier === fence.region.identifier && region.latitude === fence.region.latitude &&
    region.longitude === fence.region.longitude && region.radius === fence.region.radius &&
    region.notifyOnEnter === fence.region.notifyOnEnter && region.notifyOnExit === fence.region.notifyOnExit;
}

class FenceStore {
  private readonly store: preferences.Preferences;
  readonly fences: Fence[];

  constructor(store: preferences.Preferences, fences: Fence[]) {
    this.store = store;
    this.fences = fences;
  }

  static async withLock(context: common.Context, action: (store: FenceStore) => Promise<void>): Promise<void> {
    await withGeofenceStore(context, async (store: preferences.Preferences): Promise<void> => {
      const raw = await store.get(FENCES_KEY, '[]');
      if (typeof raw !== 'string') throw new Error('Invalid Expo geofence storage.');

      const fences: ESObject = JSON.parse(raw);
      if (!Array.isArray(fences)) throw new Error('Invalid Expo geofence storage.');

      await action(new FenceStore(store, fences as Fence[]));
    });
  }

  async save(): Promise<void> {
    await this.store.put(FENCES_KEY, JSON.stringify(this.fences));
    await this.store.flush();
  }
}

export class LocationGeofencingConsumer implements ExpoTaskConsumer {
  readonly taskType: string = GEOFENCE_TASK_TYPE;
  readonly consumerId: string = 'expo-location-geofencing';
  readonly consumerVersion: number = 1;
  private runtime?: ExpoModuleContext;

  canExecute(context: ExpoModuleContext): boolean {
    return hasLocationTaskPermission(context, true);
  }

  async onTasksChanged(context: ExpoModuleContext, tasks: ExpoTaskRecord[]): Promise<void> {
    if (!context.isValid || !hasGeofenceConfiguration(context.uiAbilityContext)) return;
    if (!context.isHeadless) this.runtime = context;

    await FenceStore.withLock(context.uiAbilityContext, async (store: FenceStore): Promise<void> => {
      if (tasks.length === 0 && store.fences.length === 0) return;

      const targets: FenceTarget[] = [];

      for (const task of tasks) {
        for (const region of readRegions(task.options)) targets.push(new FenceTarget(task, region));
      }

      if (targets.length > MAXIMUM_FENCES) {
        throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', `HarmonyOS supports at most ${MAXIMUM_FENCES} geofences per app.`);
      }

      if (!hasLocationTaskPermission(context, true)) {
        // Keep the OS ID when a revoked permission prevents fence cleanup.
        let changed = false;

        for (const fence of store.fences) {
          if (fence.generation === 0 || targets.some((target: FenceTarget): boolean => targetsMatch(target, fence))) continue;

          fence.generation = 0;
          changed = true;
        }

        if (changed) await store.save();
        if (targets.some((target: FenceTarget): boolean =>
          !store.fences.some((fence: Fence): boolean => targetsMatch(target, fence) && target.task.registrationGeneration === fence.generation))) {
          throw new ExpoModuleError('ERR_LOCATION_BACKGROUND_UNAUTHORIZED', 'Grant precise location and choose Always allow in system settings.');
        }
        return;
      }

      const active = await geoLocationManager.getActiveGeoFences();

      for (let i = store.fences.length - 1; i >= 0; i -= 1) {
        const fence = store.fences[i];
        const current = active.get(fence.id);
        if (current !== undefined && sameFence(current, fence.region)) {
          const index = targets.findIndex((target: FenceTarget): boolean => targetsMatch(target, fence));
          if (index >= 0) {
            const generation = targets[index].task.registrationGeneration;
            targets.splice(index, 1);
            if (generation !== fence.generation) {
              fence.generation = generation;
              fence.lastTransition = undefined;
              fence.lastDeliveredAt = undefined;
              await store.save();
            }
            continue;
          }

          try {
            await geoLocationManager.removeGnssGeofence(fence.id);
          } catch (error) {
            if (Number((error as BusinessError).code) !== 3301602) {
              throw new ExpoModuleError('ERR_LOCATION_GEOFENCING_STOP', message(error), error);
            }
          }

          active.delete(fence.id);
        }
        store.fences.splice(i, 1);
        await store.save();
      }

      if (targets.length === 0 || context.isHeadless) return;
      if (active.size + targets.length > MAXIMUM_FENCES) {
        throw new ExpoModuleError('ERR_LOCATION_GEOFENCING_UNAVAILABLE', 'The application has reached the HarmonyOS GNSS geofence limit.');
      }

      for (const target of targets) {
        const region = target.region;
        const transitions: geoLocationManager.GeofenceTransitionEvent[] = [];
        if (region.notifyOnEnter) transitions.push(geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER);
        if (region.notifyOnExit) transitions.push(geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_EXIT);

        const ability = context.uiAbilityContext;
        const id = await geoLocationManager.addGnssGeofence({
          geofence: {
            latitude: region.latitude,
            longitude: region.longitude,
            radius: region.radius,
            coordinateSystemType: geoLocationManager.CoordinateSystemType.WGS84,
            expiration: FENCE_LIFETIME_MS,
          },
          monitorTransitionEvents: transitions,
          fenceExtensionAbilityName: FENCE_EXTENSION_NAME,
          geofenceTransitionCallback: (error: BusinessError, transition: geoLocationManager.GeofenceTransition): void => {
            if (error) {
              console.warn(`Unable to read Expo geofence transition: ${message(error)}`);
              return;
            }
            if (transition) this.deliverTransition(ability, transition).catch(reportDeliveryFailure);
          },
        });
        store.fences.push(new Fence(id, target.task, region));
        try {
          await store.save();
        } catch (error) {
          await geoLocationManager.removeGnssGeofence(id);
          throw new ExpoModuleError('ERR_LOCATION_GEOFENCING_STORAGE', message(error), error);
        }
      }
    });
  }

  refresh(context: ExpoModuleContext): void {
    if (context.isHeadless || !hasGeofenceConfiguration(context.uiAbilityContext)) return;

    ExpoTaskManagerRegistry.withRegisteredTasks(
      context.uiAbilityContext, ExpoTaskManagerRegistry.ownerKey(context), this.taskType,
      (tasks: ExpoTaskRecord[]): Promise<void> => this.onTasksChanged(context, tasks),
    ).then(async (): Promise<void> => {
      for (const transition of await takeGeofenceTransitions(context.uiAbilityContext)) {
        await this.deliverTransition(context.uiAbilityContext, transition, transition.receivedAt, transition.generation)
          .catch(reportDeliveryFailure);
      }
    }).catch((error: Object): void => console.warn(`Unable to restore Expo geofences: ${message(error)}`));
  }

  private async deliverTransition(
    context: common.UIAbilityContext,
    transition: geoLocationManager.GeofenceTransition,
    receivedAt: number = Date.now(),
    generation?: number,
  ): Promise<void> {
    const event = transition.transitionEvent;
    const entering = event === geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER;
    if (!entering && event !== geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_EXIT) return;

    await FenceStore.withLock(context, async (store: FenceStore): Promise<void> => {
      const fence = store.fences.find((value: Fence): boolean =>
        value.id === transition.geofenceId && value.owner === context.applicationInfo.name);
      if (fence === undefined || fence.generation === 0 || (entering ? !fence.region.notifyOnEnter : !fence.region.notifyOnExit)) return;
      if (generation !== undefined && generation !== fence.generation) return;

      const expiresAt = receivedAt + GEOFENCE_EVENT_EXPIRY_MS;
      if (expiresAt <= Date.now()) return;

      const previous = fence.lastDeliveredAt ?? 0;
      if (receivedAt < previous || (fence.lastTransition === event && receivedAt - previous < DUPLICATE_WINDOW_MS)) return;

      const runtime = this.runtime;
      if (runtime === undefined || !runtime.isValid || !this.canExecute(runtime)) return;

      const task = new ExpoTaskRecord(fence.taskName, this.taskType, {}, fence.owner, this.consumerId, this.consumerVersion, fence.generation);
      const region = new Region(fence.region);
      region.state = entering ? GeofencingRegionState.Inside : GeofencingRegionState.Outside;
      const eventType = entering ? GeofencingEventType.Enter : GeofencingEventType.Exit;
      await deliverLocationTask(context, task, { eventType, region }, null, expiresAt);
      fence.lastTransition = event;
      fence.lastDeliveredAt = receivedAt;
      await store.save();
    });
  }
}

function reportDeliveryFailure(error: Object): void {
  console.warn(`Unable to queue Expo geofence transition: ${message(error)}`);
}
