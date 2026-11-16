/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireNativeModule } from 'expo-modules-core';
import type { OrientationChangeListener, Subscription } from 'expo-screen-orientation';

import type { HarmonyPlatformOrientationInfo } from '..';

export * from 'expo-screen-orientation';

type ScreenOrientationModule = {
  lockPlatformAsync(orientation: number): Promise<void>;
  getPlatformOrientationLockAsync(): Promise<number>;
  addListener(event: 'expoDidUpdateDimensions', listener: OrientationChangeListener): Subscription;
};

const native = requireNativeModule<ScreenOrientationModule>('ExpoScreenOrientation');
const subscriptions = new Set<Subscription>();

export async function lockPlatformAsync(options: HarmonyPlatformOrientationInfo): Promise<void> {
  const orientation = options?.screenOrientationConstantHarmony;
  if (typeof orientation !== 'number' || !Number.isInteger(orientation)) {
    throw new TypeError('lockPlatformAsync requires an integer screenOrientationConstantHarmony.');
  }

  await native.lockPlatformAsync(orientation);
}

export async function getPlatformOrientationLockAsync(): Promise<HarmonyPlatformOrientationInfo> {
  return { screenOrientationConstantHarmony: await native.getPlatformOrientationLockAsync() };
}

export function addOrientationChangeListener(listener: OrientationChangeListener): Subscription {
  if (typeof listener !== 'function') {
    throw new TypeError(`addOrientationChangeListener cannot be called with ${listener}`);
  }

  let active = true;
  const binding = native.addListener('expoDidUpdateDimensions', (event) => {
    if (active) listener(event);
  });

  const subscription: Subscription = {
    remove() {
      if (!active) return;

      active = false;
      subscriptions.delete(subscription);
      binding.remove();
    },
  };
  subscriptions.add(subscription);

  return subscription;
}

export function removeOrientationChangeListener(subscription: Subscription): void {
  if (typeof subscription?.remove !== 'function') {
    throw new TypeError('Must pass in a valid subscription');
  }

  subscription.remove();
}

export function removeOrientationChangeListeners(): void {
  for (const subscription of subscriptions) subscription.remove();
}
