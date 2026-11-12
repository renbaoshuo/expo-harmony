/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ExpoConfigWithHarmony } from '@expo-harmony/config-plugins';

import { getBuildProperties } from './pluginConfig';

export { createBuildPropertiesReconciler, isManagedBuildProperties } from './reconcile';
export type { ManagedBuildProperties } from './reconcile';

export function getBuildPropertiesInputFiles(config: Pick<ExpoConfigWithHarmony, '_internal'>): readonly string[] {
  return getBuildProperties(config)?.release?.obfuscation?.files ?? [];
}
