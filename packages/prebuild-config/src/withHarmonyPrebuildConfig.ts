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

function applyHarmonyMods(config, harmonyConfig: NormalizedHarmonyConfig, options: HarmonyPrebuildOptions) {
  config = withPreparationMod(config, harmonyConfig);
  config = withProjectMods(config, harmonyConfig);
  config = withEntryMods(config, harmonyConfig);
  config = withSourceMods(config, harmonyConfig);
  config = withAutolinkingMods(config, harmonyConfig, options);
  return config;
}

const withHarmonyPrebuildConfig: ConfigPlugin<HarmonyPrebuildOptions> = (config, options = {}) => {
  if (options.autolinking === false) {
    throw new HarmonyPrebuildError('ERR_HARMONY_CONFIG_INVALID', 'Harmony autolinking cannot be disabled because the generated RNOH and Expo native project requires its outputs.', { operation: 'configure-autolinking' });
  }

  const normalized = normalizeHarmonyConfig(config);
  config = applyHarmonyMods(config, normalized, options);
  return withHarmonyBaseMods(config);
};

export { withHarmonyPrebuildConfig };
export type { HarmonyPrebuildOptions };
