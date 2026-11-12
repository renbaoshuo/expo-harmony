/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ExpoConfig } from '@expo/config-types';

export type HarmonyPlatform = 'harmony';
export type ExpoKnownPlatform = NonNullable<ExpoConfig['platforms']>[number];
export type ExpoHarmonyPlatform = ExpoKnownPlatform | HarmonyPlatform;
export type HarmonyDeviceType = string;
export type HarmonyOrientation = string;

export interface HarmonyPermission extends Record<string, unknown> {
  name: string;
  reason?: string;
  usedScene?: Record<string, unknown> & { abilities?: string[]; when?: 'inuse' | 'always' };
}

export type HarmonySkillUri = Record<string, string | number | boolean>;

export interface HarmonySkill {
  entities?: string[];
  actions?: string[];
  uris?: HarmonySkillUri[];
}

export interface HarmonyConfig {
  bundleName: string;
  moduleName?: string;
  abilityName?: string;
  productName?: string;
  vendor?: string;
  versionCode?: number;
  versionName?: string;
  runtimeVersion?: string | {
    policy: 'nativeVersion' | 'sdkVersion' | 'appVersion' | 'fingerprint';
  };
  /** @deprecated Configure targetSdkVersion in @expo-harmony/expo-build-properties. */
  targetApiVersion?: number;
  targetSdkVersion?: number | string;
  compatibleSdkVersion?: number | string;
  deviceTypes?: HarmonyDeviceType[];
  permissions?: HarmonyPermission[];
  skills?: HarmonySkill[];
  querySchemes?: string[];
  icon?: string;
  label?: string;
  backgroundColor?: string;
  orientation?: HarmonyOrientation;
  userInterfaceStyle?: 'light' | 'dark' | 'automatic';
  jsEngine?: 'hermes';
  abiFilters?: string[];
  signingConfigFile?: string;
  /** Native module build options supplied by config plugins. */
  moduleBuilds?: Record<string, Record<string, string | number | boolean>>;
}

export type ExpoConfigWithHarmony = Omit<ExpoConfig, 'platforms'> & {
  platforms?: ExpoHarmonyPlatform[];
  harmony?: HarmonyConfig;
};

export function defineExpoHarmonyConfig<
  T extends { expo: ExpoConfigWithHarmony } | ExpoConfigWithHarmony,
>(config: T): T {
  return config;
}
