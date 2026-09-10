import {
  createRunOncePlugin as expoCreateRunOncePlugin,
  withPlugins as expoWithPlugins,
  withRunOnce as expoWithRunOnce,
  withStaticPlugin as expoWithStaticPlugin,
  type ConfigPlugin,
} from '@expo/config-plugins';

import type { HarmonyConfigPlugin } from './pluginTypes';
import type { ExpoConfigWithHarmony } from './config';

// Expo plugins accept the narrower platform union. Method variance allows them
// alongside Harmony plugins without losing contextual types for inline callbacks.
type CompatiblePlugin<Props = void> = {
  apply(config: ExpoConfigWithHarmony, props: Props): ExpoConfigWithHarmony;
}['apply'];

export type HarmonyPluginReference = string | CompatiblePlugin<never>;
export type HarmonyStaticPlugin = HarmonyPluginReference | [HarmonyPluginReference, unknown];

export const withPlugins = expoWithPlugins as unknown as HarmonyConfigPlugin<HarmonyStaticPlugin[]>;
export const withRunOnce = expoWithRunOnce as unknown as HarmonyConfigPlugin<{
  plugin: CompatiblePlugin;
  name: string;
  version?: string;
}>;
export const withStaticPlugin = expoWithStaticPlugin as unknown as HarmonyConfigPlugin<{
  plugin: HarmonyStaticPlugin;
  projectRoot?: string;
  fallback?: CompatiblePlugin<{ _resolverError: Error } & Record<string, unknown>>;
}>;

export function createRunOncePlugin<Props>(
  plugin: HarmonyConfigPlugin<Props>, name: string, version?: string
): HarmonyConfigPlugin<Props>;
export function createRunOncePlugin<Props>(
  plugin: ConfigPlugin<Props>, name: string, version?: string
): HarmonyConfigPlugin<Props>;
export function createRunOncePlugin(
  plugin: ConfigPlugin<never> | HarmonyConfigPlugin<never>,
  name: string,
  version?: string
): HarmonyConfigPlugin<never> {
  return expoCreateRunOncePlugin(plugin as ConfigPlugin<never>, name, version) as HarmonyConfigPlugin<never>;
}
