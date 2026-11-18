/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ConfigPlugin } from '@expo/config-plugins';

declare const withHarmonyFonts: ConfigPlugin<withHarmonyFonts.FontsPluginConfig | void>;

declare namespace withHarmonyFonts {
  interface HarmonyFontDefinition {
    path: string;
    weight?: 400;
    style?: 'normal';
  }

  type HarmonyFont
    = | string
      | {
        fontFamily: string;
        fontDefinitions: HarmonyFontDefinition[];
      };

  interface FontsPluginConfig {
    fonts?: HarmonyFont[];
    harmony?: { fonts?: HarmonyFont[] };
  }
}

export = withHarmonyFonts;
