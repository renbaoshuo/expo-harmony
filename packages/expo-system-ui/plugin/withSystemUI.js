'use strict';

const normalizeColor = require('@react-native/normalize-colors');
const { createRunOncePlugin } = require('@expo/config-plugins');
const { withModuleJson } = require('@expo-harmony/config-plugins');
const pkg = require('../package.json');

const STYLES = new Set(['light', 'dark', 'automatic']);

function normalizeHarmonyColor(value) {
  if (value == null) return null;

  const color = normalizeColor(value);

  if (color == null) {
    throw new TypeError('Harmony expo-system-ui backgroundColor must be a valid React Native color.');
  }

  const rgba = color.toString(16).padStart(8, '0').toUpperCase();

  return `#${rgba.slice(6, 8)}${rgba.slice(0, 6)}`;
}

function setMetadata(items, name, value) {
  const metadata = (Array.isArray(items) ? items : []).filter(item => item?.name !== name);
  if (value != null) metadata.push({ name, value });
  return metadata;
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

    let metadata = setMetadata(manifest.metadata, 'expo.harmony.rootViewBackgroundColor', background);
    metadata = setMetadata(metadata, 'expo.harmony.userInterfaceStyle', style);

    mod.modResults = {
      ...mod.modResults,
      module: { ...manifest, metadata },
    };

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonySystemUI, pkg.name, pkg.version);
