import { createRunOncePlugin } from '@expo/config-plugins';

import { PackageMetadata } from './packageMetadata';
import { withHarmonyPrebuildConfig } from './withHarmonyPrebuildConfig';

export const HarmonyPrebuildPlugin
  = createRunOncePlugin(withHarmonyPrebuildConfig, PackageMetadata.name, PackageMetadata.version);
