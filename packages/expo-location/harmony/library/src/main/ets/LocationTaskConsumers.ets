/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAbilityLifecycleSubscriber, ExpoAppLifecycleSubscriber } from '@expo-harmony/expo-modules-core';
import { ExpoTaskManagerRegistry } from '@expo-harmony/expo-task-manager';
import { LocationBackgroundConsumer } from './LocationBackgroundConsumer';
import { LocationGeofencingConsumer } from './LocationGeofencingConsumer';

export const backgroundLocationConsumer = new LocationBackgroundConsumer();
export const geofencingConsumer = new LocationGeofencingConsumer();

function registerLocationConsumers(): void {
  if (ExpoTaskManagerRegistry.consumer(backgroundLocationConsumer.taskType) === undefined) {
    ExpoTaskManagerRegistry.registerConsumer(backgroundLocationConsumer);
  }
  if (ExpoTaskManagerRegistry.consumer(geofencingConsumer.taskType) === undefined) {
    ExpoTaskManagerRegistry.registerConsumer(geofencingConsumer);
  }
}

export class ExpoLocationLifecycleSubscriber extends ExpoAppLifecycleSubscriber {
  override onCreate(): void {
    registerLocationConsumers();
  }
}

export class ExpoLocationAbilityLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  override onForeground(): void {
    backgroundLocationConsumer.refreshAbility(this.context);
  }

  override onDestroy(): void {
    backgroundLocationConsumer.destroyAbility(this.context);
  }
}

