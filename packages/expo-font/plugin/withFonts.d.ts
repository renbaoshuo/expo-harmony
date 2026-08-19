import type { ConfigPlugin } from '@expo/config-plugins';

declare const withHarmonyFonts: ConfigPlugin<{
  fonts?: unknown[];
  harmony?: { fonts?: unknown[] };
}>;

export = withHarmonyFonts;
