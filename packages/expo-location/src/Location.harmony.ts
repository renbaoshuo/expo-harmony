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
import { HeadingSubscriber, LocationSubscriber } from 'expo-location/build/LocationSubscribers';
import { CodedError, type EventSubscription } from 'expo-modules-core';

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

  try {
    if (errorHandler) {
      errors = ExpoLocation.addListener('Expo.locationError', (event: { watchId: number; reason: string }) => {
        if (event.watchId === id) errorHandler(event.reason);
      });
    }

    await start(id);
  } catch (error) {
    subscriber.forgetCallback(id);
    errors?.remove();

    throw error;
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

export function getHeadingAsync(): Promise<LocationHeadingObject> {
  return new Promise((resolve, reject) => {
    let tries = 0;
    let settled = false;
    let subscription: LocationSubscription | undefined;

    const stop = () => {
      settled = true;
      subscription?.remove();
    };

    watchHeadingAsync((heading) => {
      if (!settled && (heading.accuracy > 1 || tries++ > 5)) {
        stop();
        resolve(heading);
      }
    }, (reason) => {
      if (!settled) {
        stop();
        reject(reason);
      }
    }).then((watch) => {
      subscription = watch;
      if (settled) watch.remove();
    }, reject);
  });
}

const MOTION_UNAVAILABLE = 'Motion activity recognition is not available on HarmonyOS.';

export async function getMotionActivityAsync(): Promise<MotionActivityObject> {
  throw new CodedError('ERR_MOTION_ACTIVITY_UNAVAILABLE', MOTION_UNAVAILABLE);
}

// Fail before upstream allocates callbacks that would outlive the rejected watch.
export async function watchMotionActivityAsync(
  _callback: MotionActivityCallback,
  _errorHandler?: LocationErrorCallback
): Promise<LocationSubscription> {
  throw new CodedError('ERR_MOTION_ACTIVITY_UNAVAILABLE', MOTION_UNAVAILABLE);
}
