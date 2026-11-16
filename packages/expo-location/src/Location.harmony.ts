/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type {
  LocationCallback,
  LocationErrorCallback,
  LocationHeadingCallback,
  LocationHeadingObject,
  LocationOptions,
  LocationSubscription,
  MotionActivityCallback,
  MotionActivityObject,
} from 'expo-location';
import ExpoLocation from 'expo-location/build/ExpoLocation';
import {
  HeadingSubscriber,
  LocationSubscriber,
  MotionActivitySubscriber,
} from 'expo-location/build/LocationSubscribers';
import type { EventSubscription } from 'expo-modules-core';

export * from 'expo-location/build/Location';

async function startWatch<Callback>(
  subscriber: {
    registerCallback(callback: Callback): number;
    forgetCallback(id: number): void;
    unregisterCallback(id: number): void;
  },
  start: (id: number) => Promise<void>,
  callback: Callback,
  errorHandler?: LocationErrorCallback
): Promise<LocationSubscription> {
  const id = subscriber.registerCallback(callback);
  let errors: EventSubscription | undefined;
  let started = false;

  try {
    if (errorHandler) {
      // Upstream's error subscriber removes unmatched native watches, including polyfill watches.
      errors = ExpoLocation.addListener('Expo.locationError', (event: { watchId: number; reason: string }) => {
        if (event.watchId === id) errorHandler(event.reason);
      });
    }

    await start(id);
    started = true;
  } finally {
    if (!started) {
      subscriber.forgetCallback(id);
      errors?.remove();
    }
  }

  return {
    remove() {
      errors?.remove();
      errors = undefined;
      subscriber.unregisterCallback(id);
    },
  };
}

export function watchPositionAsync(
  options: LocationOptions,
  callback: LocationCallback,
  errorHandler?: LocationErrorCallback
): Promise<LocationSubscription> {
  return startWatch(
    LocationSubscriber,
    id => ExpoLocation.watchPositionImplAsync(id, options),
    callback,
    errorHandler
  );
}

export function watchHeadingAsync(
  callback: LocationHeadingCallback,
  errorHandler?: LocationErrorCallback
): Promise<LocationSubscription> {
  return startWatch(HeadingSubscriber, id => ExpoLocation.watchDeviceHeading(id), callback, errorHandler);
}

function firstWatchUpdate<Value>(
  watch: (callback: (value: Value) => void, errorHandler: LocationErrorCallback) => Promise<LocationSubscription>,
  accepts: (value: Value) => boolean,
  wrapError = false
): Promise<Value> {
  return new Promise((resolve, reject) => {
    let settled = false;
    let subscription: LocationSubscription | undefined;

    const stop = () => {
      settled = true;
      subscription?.remove();
    };

    watch((value) => {
      if (!settled && accepts(value)) {
        stop();
        resolve(value);
      }
    }, (reason) => {
      if (!settled) {
        stop();
        reject(wrapError ? new Error(reason) : reason);
      }
    }).then((current) => {
      subscription = current;
      if (settled) current.remove();
    }, reject);
  });
}

export function getHeadingAsync(): Promise<LocationHeadingObject> {
  let tries = 0;

  return firstWatchUpdate<LocationHeadingObject>(
    watchHeadingAsync, heading => heading.accuracy > 1 || tries++ > 5
  );
}

export function watchMotionActivityAsync(
  callback: MotionActivityCallback,
  errorHandler?: LocationErrorCallback
): Promise<LocationSubscription> {
  return startWatch(MotionActivitySubscriber, id => ExpoLocation.watchMotionActivityImplAsync(id), callback, errorHandler);
}

export function getMotionActivityAsync(): Promise<MotionActivityObject> {
  return firstWatchUpdate<MotionActivityObject>(watchMotionActivityAsync, () => true, true);
}
