/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { geoLocationManager } from '@kit.LocationKit';

const FENCE_PREFERENCES: string = 'ExpoLocationGeofences';
const PENDING_TRANSITIONS_KEY: string = 'pendingTransitions.v1';
const MAX_PENDING_TRANSITIONS: number = 100;
export const GEOFENCE_EVENT_EXPIRY_MS: number = 60_000;
export const FENCES_KEY: string = 'fences.v1';

interface FenceIdentity {
  id: number;
  owner: string;
  generation: number;
}

export class PendingFenceTransition implements geoLocationManager.GeofenceTransition {
  geofenceId: number;
  transitionEvent: geoLocationManager.GeofenceTransitionEvent;
  generation: number;
  receivedAt: number;

  constructor(transition: geoLocationManager.GeofenceTransition, generation: number) {
    this.geofenceId = transition.geofenceId;
    this.transitionEvent = transition.transitionEvent;
    this.generation = generation;
    this.receivedAt = Date.now();
  }
}

export async function withGeofenceStore(context: common.Context, action: (store: preferences.Preferences) => Promise<void>): Promise<void> {
  const app = context.getApplicationContext();
  const file = await fileIo.open(`${app.filesDir}/ExpoLocationGeofences.lock`, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);

  try {
    await file.lock(true);
    await preferences.removePreferencesFromCache(app, FENCE_PREFERENCES);
    const store = await preferences.getPreferences(app, { name: FENCE_PREFERENCES });
    await action(store);
  } finally {
    fileIo.closeSync(file);
  }
}

async function pendingTransitions(store: preferences.Preferences): Promise<PendingFenceTransition[]> {
  const raw = await store.get(PENDING_TRANSITIONS_KEY, '[]');
  if (typeof raw !== 'string') return [];

  try {
    const values: ESObject = JSON.parse(raw);
    if (!Array.isArray(values)) return [];

    const now = Date.now();
    return (values as PendingFenceTransition[]).filter((item: PendingFenceTransition): boolean =>
      item !== null && Number.isSafeInteger(item.geofenceId) && Number.isSafeInteger(item.generation) && item.generation > 0 &&
      Number.isFinite(item.receivedAt) && item.receivedAt <= now && item.receivedAt + GEOFENCE_EVENT_EXPIRY_MS > now,
    );
  } catch (_) {
    return [];
  }
}

export async function takeGeofenceTransitions(context: common.Context): Promise<PendingFenceTransition[]> {
  let pending: PendingFenceTransition[] = [];
  await withGeofenceStore(context, async (store: preferences.Preferences): Promise<void> => {
    if (!(await store.has(PENDING_TRANSITIONS_KEY))) return;

    pending = await pendingTransitions(store);
    await store.delete(PENDING_TRANSITIONS_KEY);
    await store.flush();
  });
  return pending;
}

// Imported directly by the generated FenceExtensionAbility. This entry may
// load only APIs that HarmonyOS allows inside that extension.
export function deliverExpoGeofenceEvent(context: common.ExtensionContext, transition: geoLocationManager.GeofenceTransition): void {
  if (transition.transitionEvent !== geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER &&
    transition.transitionEvent !== geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_EXIT) return;

  withGeofenceStore(context, async (store: preferences.Preferences): Promise<void> => {
    const token = context.applicationInfo.accessTokenId;
    const permissions = abilityAccessCtrl.createAtManager();
    const granted = abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    if (permissions.checkAccessTokenSync(token, 'ohos.permission.APPROXIMATELY_LOCATION') !== granted ||
      permissions.checkAccessTokenSync(token, 'ohos.permission.LOCATION') !== granted ||
      permissions.checkAccessTokenSync(token, 'ohos.permission.LOCATION_IN_BACKGROUND') !== granted) return;

    const raw = await store.get(FENCES_KEY, '[]');
    if (typeof raw !== 'string') return;

    const fences: ESObject = JSON.parse(raw);
    if (!Array.isArray(fences)) return;

    const fence = (fences as FenceIdentity[]).find((item: FenceIdentity): boolean =>
      item !== null && item.id === transition.geofenceId && item.owner === context.applicationInfo.name &&
      Number.isSafeInteger(item.generation) && item.generation > 0,
    );
    if (fence === undefined) return;

    const pending = await pendingTransitions(store);
    pending.push(new PendingFenceTransition(transition, fence.generation));
    await store.put(PENDING_TRANSITIONS_KEY, JSON.stringify(pending.slice(-MAX_PENDING_TRANSITIONS)));
    await store.flush();
  }).catch((error: Object): void => console.warn(`Unable to save Expo geofence transition: ${String(error)}`));
}
