/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { PluginConfigType } from '@expo-harmony/expo-dev-launcher/plugin';

interface GeneratedSchemeOptions {
  addGeneratedScheme?: boolean;
}

export type DevClientPluginConfigType = PluginConfigType & GeneratedSchemeOptions & {
  harmony?: GeneratedSchemeOptions;
};

export default function devClient(options?: DevClientPluginConfigType): ['@expo-harmony/expo-dev-client', DevClientPluginConfigType];
