import {
  createRunOncePlugin,
  withHarmonyBaseMods,
  type HarmonyConfigPlugin,
} from '@expo-harmony/config-plugins';

import { HarmonyPrebuildError } from './errors';
import { withAutolinkingMods } from './mods/withAutolinkingMods';
import { withEntryMods } from './mods/withEntryMods';
import { withPreparationMod } from './mods/withPreparationMod';
import { withProjectMods } from './mods/withProjectMods';
import { withSourceMods } from './mods/withSourceMods';
import { PackageMetadata } from './packageMetadata';

interface HarmonyPrebuildOptions {
  buildType?: 'debug' | 'release';
}

const withDefaults: HarmonyConfigPlugin<HarmonyPrebuildOptions | void> = (config, props) => {
  const options = props ?? {};
  if (typeof options !== 'object' || Array.isArray(options)
    || Object.keys(options).some(key => key !== 'buildType')
    || (options.buildType !== undefined && !['debug', 'release'].includes(options.buildType))) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_CONFIG_INVALID',
      'Harmony prebuild options only accept buildType: "debug" or "release".',
      { operation: 'configure-prebuild' }
    );
  }

  config = withPreparationMod(config);
  config = withProjectMods(config);
  config = withEntryMods(config);
  config = withSourceMods(config);
  config = withAutolinkingMods(config, options);

  return withHarmonyBaseMods(config);
};

const withHarmonyPrebuildConfig = createRunOncePlugin(withDefaults, PackageMetadata.name, PackageMetadata.version);

export { withHarmonyPrebuildConfig };
export type { HarmonyPrebuildOptions };
