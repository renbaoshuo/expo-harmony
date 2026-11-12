/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as TaskManager from 'expo-task-manager';

export const LOCATION_TASK = 'expo-demo-location';
export const GEOFENCING_TASK = 'expo-demo-geofencing';

const events = new Map<string, TaskManager.TaskManagerTaskBody>();
const listeners = new Set<() => void>();

for (const name of [LOCATION_TASK, GEOFENCING_TASK]) {
  TaskManager.defineTask(name, async (event) => {
    events.set(name, event);
    listeners.forEach(listener => listener());
  });
}

export function getLocationEvent(name: string) {
  return events.get(name);
}

export function subscribeToLocationEvents(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
