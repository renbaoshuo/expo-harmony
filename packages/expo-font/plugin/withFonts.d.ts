import type { ConfigPlugin } from '@expo/config-plugins';

declare const withHarmonyFonts: ConfigPlugin<withHarmonyFonts.FontsPluginConfig | void>;

declare namespace withHarmonyFonts {
  interface HarmonyFontDefinition {
    path: string;
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
