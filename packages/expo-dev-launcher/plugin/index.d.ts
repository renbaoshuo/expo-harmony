/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export interface PluginConfigOptions {
  launchMode?: 'most-recent' | 'launcher';
  /** @deprecated Use launchMode. */
  launchModeExperimental?: 'most-recent' | 'launcher';
  defaultLaunchURL?: string;
  toolsButton?: boolean;
  embeddedBundle?: boolean;
  skipOnboarding?: boolean;
  showMenuAtLaunch?: boolean;
}

export type PluginConfigType = PluginConfigOptions & { harmony?: PluginConfigOptions };

export default function devLauncher(options?: PluginConfigType): ['@expo-harmony/expo-dev-launcher', PluginConfigType];
