import type { ExpoConfig } from '@expo/config-types';

export type HarmonyPlatform = 'harmony';
export type ExpoKnownPlatform = NonNullable<ExpoConfig['platforms']>[number];
export type ExpoHarmonyPlatform = ExpoKnownPlatform | HarmonyPlatform;
export type HarmonyDeviceType = 'phone' | 'tablet' | '2in1';
export type HarmonyOrientation
  = | 'default'
    | 'portrait'
    | 'landscape'
    | 'portrait_inverted'
    | 'landscape_inverted'
    | 'auto_rotation';

export interface HarmonyPermission {
  name: string;
  reason?: string;
  usedScene?: { abilities?: string[]; when?: 'inuse' | 'always' };
}

export interface HarmonySkill {
  entities?: string[];
  actions?: string[];
  uris?: Array<Record<string, string>>;
}

export interface HarmonyFontDefinition {
  path: string;
  weight?: number;
  style?: 'normal' | 'italic';
}

export type HarmonyFont
  = | string
    | {
      fontFamily: string;
      fontDefinitions: HarmonyFontDefinition[];
    };

export interface HarmonyConfig {
  bundleName: string;
  moduleName?: string;
  abilityName?: string;
  productName?: string;
  vendor?: string;
  versionCode?: number;
  versionName?: string;
  targetApiVersion?: number;
  /** Harmony SDK label written to build-profile.json5, e.g. 6.0.0(20). Its API must match targetApiVersion. */
  targetSdkVersion?: number | string;
  /** API number, or a full Harmony SDK label ending in the API number. */
  compatibleSdkVersion?: number | string;
  deviceTypes?: HarmonyDeviceType[];
  permissions?: HarmonyPermission[];
  skills?: HarmonySkill[];
  /** URL schemes the app may inspect with Linking.canOpenURL. http, https, and expo.scheme are added automatically. */
  querySchemes?: string[];
  icon?: string;
  label?: string;
  backgroundColor?: string;
  orientation?: HarmonyOrientation;
  userInterfaceStyle?: 'light' | 'dark' | 'automatic';
  jsEngine?: 'hermes';
  abiFilters?: string[];
  signingConfigFile?: string;
  /** Fonts bundled when the `@expo-harmony/expo-font` config plugin is registered. */
  fonts?: HarmonyFont[];
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
