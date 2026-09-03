import {
  normalizeHarmonyConfig,
  withHarmonyBaseMods,
  type NormalizedHarmonyConfig,
} from '@expo-harmony/config-plugins';
import type { ConfigPlugin } from '@expo/config-plugins';

import { HarmonyPrebuildError } from './errors';
import { withAutolinkingMods } from './mods/withAutolinkingMods';
import { withEntryMods } from './mods/withEntryMods';
import { withPreparationMod } from './mods/withPreparationMod';
import { withProjectMods } from './mods/withProjectMods';
import { withSourceMods } from './mods/withSourceMods';

interface HarmonyPrebuildOptions {
  autolinking?: boolean;
  buildType?: 'debug' | 'release';
}

function applyHarmonyMods(config, harmony: NormalizedHarmonyConfig, options: HarmonyPrebuildOptions) {
  config = withPreparationMod(config, harmony);
  config = withProjectMods(config, harmony);
  config = withEntryMods(config, harmony);
  config = withSourceMods(config, harmony);
  config = withAutolinkingMods(config, harmony, options);

  return config;
}

const withHarmonyPrebuildConfig: ConfigPlugin<HarmonyPrebuildOptions> = (config, options = {}) => {
  if (options.autolinking === false) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_CONFIG_INVALID',
      'Harmony autolinking cannot be disabled because the generated RNOH and Expo native project requires its outputs.',
      { operation: 'configure-autolinking' }
    );
  }

  const harmony = normalizeHarmonyConfig(config);

  config = applyHarmonyMods(config, harmony, options);

  return withHarmonyBaseMods(config);
};

export { withHarmonyPrebuildConfig };
export type { HarmonyPrebuildOptions };
