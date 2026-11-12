/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { createRunOncePlugin } = require('expo/config-plugins');
const { HarmonyManifest, withModuleJson } = require('@expo-harmony/config-plugins');
const pkg = require('./package.json');
const StatusBarStyleMetadata = 'expo.harmony.statusBar.style';
const StatusBarHiddenMetadata = 'expo.harmony.statusBar.hidden';

function withStatusBar(config, props) {
  if (!config.harmony?.bundleName && !config.platforms?.includes('harmony')) return config;

  const { style, hidden } = props ?? {};
  if (style != null && style !== 'light' && style !== 'dark') {
    throw new TypeError('Harmony expo-status-bar style must be \'light\' or \'dark\'.');
  }
  if (hidden != null && typeof hidden !== 'boolean') {
    throw new TypeError('Harmony expo-status-bar hidden must be a boolean.');
  }

  const metadata = [];
  if (style != null) metadata.push({ name: StatusBarStyleMetadata, value: style });
  if (hidden != null) metadata.push({ name: StatusBarHiddenMetadata, value: String(hidden) });

  return withModuleJson(config, (mod) => {
    HarmonyManifest.configureModuleMetadata(mod, metadata);
    return mod;
  });
}

module.exports = createRunOncePlugin(withStatusBar, pkg.name, pkg.version);
