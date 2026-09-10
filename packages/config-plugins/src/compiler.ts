import { compileModsAsync, type ExportedConfig, type ModPlatform } from '@expo/config-plugins';

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
  return await compileModsAsync(withHarmonyBaseMods(config) as ExportedConfig, {
    ...options,
    platforms: ['harmony' as ModPlatform],
    assertMissingModProviders: true,
  }) as Config;
}
