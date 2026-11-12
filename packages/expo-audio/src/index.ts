/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import AudioModule from 'expo-audio/src/AudioModule';

export * from 'expo-audio/src/index';

// The upstream wrapper only exposes the notification request on Android.
export async function requestNotificationPermissionsAsync() {
  return await AudioModule.requestNotificationPermissionsAsync();
}
