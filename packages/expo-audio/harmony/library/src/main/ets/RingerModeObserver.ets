/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { audio } from '@kit.AudioKit';
import deviceInfo from '@ohos.deviceInfo';

type RingerListener = (mode: audio.AudioRingMode) => void;
const legacyListeners: Set<RingerListener> = new Set<RingerListener>();
let legacyManager: audio.AudioVolumeGroupManager | undefined = undefined;

function notifyLegacyListeners(mode: audio.AudioRingMode): void {
  Array.from(legacyListeners).forEach((listener: RingerListener): void => {
    try { listener(mode); } catch (_) { /* One runtime cannot interrupt another's notification. */ }
  });
}

/** AudioVolumeGroupManager.off is only available since API 18. */
export function observeDefaultRingerMode(manager: audio.AudioVolumeGroupManager, listener: RingerListener): () => void {
  if (deviceInfo.sdkApiVersion >= 18) {
    manager.on('ringerModeChange', listener);
    return (): void => { manager.off('ringerModeChange', listener); };
  }
  // Keep a single process subscription on older systems. The native callback
  // only retains this removable set, never a destroyed Expo runtime.
  if (legacyManager === undefined) {
    manager.on('ringerModeChange', notifyLegacyListeners);
    legacyManager = manager;
  }
  legacyListeners.add(listener);

  return (): void => { legacyListeners.delete(listener); };
}
