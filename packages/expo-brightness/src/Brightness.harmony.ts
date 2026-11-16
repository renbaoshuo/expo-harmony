/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { BrightnessMode } from 'expo-brightness';
import nativeModule from 'expo-brightness/build/ExpoBrightness';

export * from 'expo-brightness';

type HarmonyBrightnessModule = {
  isAvailableAsync(): Promise<boolean>;
  getSystemBrightnessAsync(): Promise<number>;
  getSystemBrightnessModeAsync(): Promise<BrightnessMode>;
  restoreSystemBrightnessAsync(): Promise<void>;
  isUsingSystemBrightnessAsync(): Promise<boolean>;
};

const native: HarmonyBrightnessModule = nativeModule;

export async function isAvailableAsync(): Promise<boolean> {
  return await native.isAvailableAsync();
}

export async function getSystemBrightnessAsync(): Promise<number> {
  return await native.getSystemBrightnessAsync();
}

export async function getSystemBrightnessModeAsync(): Promise<BrightnessMode> {
  return await native.getSystemBrightnessModeAsync();
}

export async function restoreSystemBrightnessAsync(): Promise<void> {
  await native.restoreSystemBrightnessAsync();
}

export async function isUsingSystemBrightnessAsync(): Promise<boolean> {
  return await native.isUsingSystemBrightnessAsync();
}
