/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { PluginConfigType } from './pluginConfig';

function buildProperties(props: PluginConfigType = {}): [string, PluginConfigType] {
  return ['@expo-harmony/expo-build-properties', props];
}

// ESM imports the CommonJS module value, and transpiled callers can read .default.
export = Object.assign(buildProperties, { default: buildProperties });
