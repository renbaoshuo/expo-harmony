/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { FontsPluginConfig } from './withFonts';

declare function fonts(
  props?: FontsPluginConfig
): ['@expo-harmony/expo-font', FontsPluginConfig];

export = fonts;
