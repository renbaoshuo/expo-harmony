'use strict';

const normalizeColor = require('@react-native/normalize-colors');
const { createRunOncePlugin } = require('@expo/config-plugins');
const { HarmonyManifest, HarmonyResources, withModuleJson } = require('@expo-harmony/config-plugins');
const pkg = require('../package.json');

const STYLES = new Set(['light', 'dark', 'automatic']);

function normalizeHarmonyColor(value) {
  if (value == null) return null;

  const color = normalizeColor(value);

  if (color == null) {
    throw new TypeError('Harmony expo-system-ui backgroundColor must be a valid React Native color.');
  }

  return HarmonyResources.toArgb(color);
}

function withHarmonySystemUI(config) {
  const harmony = config.harmony || {};
  const enabled = harmony.bundleName || config.platforms?.includes('harmony');

  if (!enabled) return config;

  return withModuleJson(config, (mod) => {
    const background = normalizeHarmonyColor(harmony.backgroundColor || config.backgroundColor || null);
    const style = harmony.userInterfaceStyle ?? config.userInterfaceStyle ?? 'light';

    if (!STYLES.has(style)) {
      throw new TypeError('Harmony expo-system-ui userInterfaceStyle must be light, dark, or automatic.');
    }

    const manifest = mod.modResults.module && typeof mod.modResults.module === 'object'
      ? mod.modResults.module
      : {};

    const target = { metadata: manifest.metadata };
    if (background == null) HarmonyManifest.removeMetadata(target, 'expo.harmony.rootViewBackgroundColor');
    else HarmonyManifest.setMetadata(target, { name: 'expo.harmony.rootViewBackgroundColor', value: background });
    HarmonyManifest.setMetadata(target, { name: 'expo.harmony.userInterfaceStyle', value: style });

    mod.modResults = {
      ...mod.modResults,
      module: { ...manifest, metadata: target.metadata },
    };

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonySystemUI, pkg.name, pkg.version);
