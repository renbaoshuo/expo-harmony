/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { AudioModule } from 'expo-audio/build/ExpoAudio';
import type { AudioSource } from 'expo-audio';
import { resolveSource } from 'expo-audio/build/utils/resolveSource';

export * from 'expo-audio/build/ExpoAudio';

const add = AudioModule.AudioPlaylist.prototype.add;
AudioModule.AudioPlaylist.prototype.add = function (source: AudioSource) {
  const resolved = resolveSource(source);
  if (resolved !== null) add.call(this, resolved);
};

const insert = AudioModule.AudioPlaylist.prototype.insert;
AudioModule.AudioPlaylist.prototype.insert = function (source: AudioSource, index: number) {
  const resolved = resolveSource(source);
  if (resolved !== null) insert.call(this, resolved, index);
};

// The upstream wrapper only exposes the notification request on Android.
export async function requestNotificationPermissionsAsync() {
  return AudioModule.requestNotificationPermissionsAsync();
}
