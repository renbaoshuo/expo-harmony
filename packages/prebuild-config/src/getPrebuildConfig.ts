import { getConfig, type ProjectConfig } from '@expo/config';
import { normalizeHarmonyConfig, type ExpoConfigWithHarmony } from '@expo-harmony/config-plugins';

import { withHarmonyPrebuildConfig } from './withHarmonyPrebuildConfig';

export type HarmonyProjectConfig = Omit<ProjectConfig, 'exp'> & {
  exp: ExpoConfigWithHarmony;
};

export async function getPrebuildConfigAsync(root: string): Promise<HarmonyProjectConfig> {
  const project = getConfig(root, {
    skipSDKVersionRequirement: true,
    isModdedConfig: true,
  });
  const config = withHarmonyPrebuildConfig(project.exp);

  normalizeHarmonyConfig(config);

  return { ...project, exp: config };
}
