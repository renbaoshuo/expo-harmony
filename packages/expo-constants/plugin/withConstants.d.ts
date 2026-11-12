/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ConfigPlugin } from 'expo/config-plugins';

declare const withConstants: ConfigPlugin & {
  refreshExpoConstantsResourceAsync(projectRoot: string, harmonyDirectory: string): Promise<string>;
};
export = withConstants;
