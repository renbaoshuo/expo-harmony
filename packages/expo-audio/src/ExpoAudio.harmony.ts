/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { AudioModule } from 'expo-audio/build/ExpoAudio';

export * from 'expo-audio/build/ExpoAudio';

// The upstream wrapper only exposes the notification request on Android.
export async function requestNotificationPermissionsAsync() {
  return AudioModule.requestNotificationPermissionsAsync();
}
