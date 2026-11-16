/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { PlatformOrientationInfo } from 'expo-screen-orientation';

export type HarmonyPlatformOrientationInfo = PlatformOrientationInfo & {
  /** HarmonyOS `window.Orientation` value. */
  screenOrientationConstantHarmony?: number;
};
