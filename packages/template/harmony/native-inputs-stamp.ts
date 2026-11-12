/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { writeHarmonyNativeInputsStampSync } from '@expo-harmony/expo-modules-autolinking/native-inputs';

export function writeStamp(projectRoot: string, harmonyRoot: string): void {
  writeHarmonyNativeInputsStampSync({ projectRoot, harmonyRoot });
}
