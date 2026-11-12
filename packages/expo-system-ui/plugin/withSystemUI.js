/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const { HarmonyManifest, HarmonyResources, withModuleJson } = require('@expo-harmony/config-plugins');
const pkg = require('../package.json');

const STYLES = new Set(['light', 'dark', 'automatic']);

function normalizeHarmonyColor(value) {
  if (value == null) return null;

  const color = HarmonyResources.toArgb(value);

  return color.length === 7 ? `#FF${color.slice(1)}` : color;
}

function withHarmonySystemUI(config) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');

  if (!enabled) return config;

  return withModuleJson(config, (mod) => {
    const { harmony, backgroundColor, userInterfaceStyle } = mod.modRawConfig;
    const background = normalizeHarmonyColor(harmony?.backgroundColor || backgroundColor || null);
    const style = harmony?.userInterfaceStyle ?? userInterfaceStyle ?? 'light';

    if (!STYLES.has(style)) {
      throw new TypeError('Harmony expo-system-ui userInterfaceStyle must be light, dark, or automatic.');
    }

    const metadata = [];
    if (background !== null) metadata.push({ name: 'expo.harmony.rootViewBackgroundColor', value: background });
    metadata.push({ name: 'expo.harmony.userInterfaceStyle', value: style });
    HarmonyManifest.configureModuleMetadata(mod, metadata);

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonySystemUI, pkg.name, pkg.version);
