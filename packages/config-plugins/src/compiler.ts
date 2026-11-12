/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { evalModsAsync, type ExportedConfig, type Mod, type ModPlatform } from '@expo/config-plugins';

import type { ExpoConfigWithHarmony } from './config';
import { withHarmonyBaseMods } from './mods';

export interface HarmonyCompileOptions {
  projectRoot: string;
  introspect?: boolean;
  ignoreExistingNativeFiles?: boolean;
}

export async function compileHarmonyModsAsync<Config extends ExpoConfigWithHarmony>(
  config: Config,
  options: HarmonyCompileOptions
): Promise<Config> {
  const base = withHarmonyBaseMods(config) as ExportedConfig;
  const mods = base.mods as Record<string, Record<string, Mod>>;

  // Expo's full compiler installs Android/iOS providers and prunes its mod table in place.
  const input = options.introspect
    ? {
        ...base,
        mods: {
          harmony: Object.fromEntries(Object.entries(mods.harmony).filter(([, mod]) => mod.isIntrospective)),
        } as ExportedConfig['mods'],
      }
    : base;

  const result = await evalModsAsync(input, {
    ...options,
    platforms: ['harmony' as ModPlatform],
    assertMissingModProviders: true,
  });
  if (options.introspect) result.mods = base.mods;

  return result as Config;
}
