/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ProjectConfig } from '@expo/config';
import { normalizeHarmonyConfig, type ExpoConfigWithHarmony } from '@expo-harmony/config-plugins';
import { getHarmonyProjectConfig, type EnvMode } from '@expo-harmony/expo__config/internal/project-config';

import { withHarmonyPrebuildConfig } from './withHarmonyPrebuildConfig';

export type HarmonyProjectConfig = Omit<ProjectConfig, 'exp'> & {
  exp: ExpoConfigWithHarmony;
};

export async function getPrebuildConfigAsync(root: string, mode?: EnvMode): Promise<HarmonyProjectConfig> {
  const project = getHarmonyProjectConfig(root, {
    skipSDKVersionRequirement: true,
    isModdedConfig: true,
  }, mode);
  const config = withHarmonyPrebuildConfig(project.exp);

  normalizeHarmonyConfig(config);

  return { ...project, exp: config };
}
