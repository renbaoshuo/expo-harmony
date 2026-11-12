/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const { HarmonyManifest, withModuleJson } = require('@expo-harmony/config-plugins');
const pkg = require('../package.json');

const STYLES = new Set(['light', 'dark']);
const VISIBILITIES = new Set(['visible', 'hidden']);
const STYLE_METADATA = 'expo.harmony.navigationBar.style';
const HIDDEN_METADATA = 'expo.harmony.navigationBar.hidden';
const LEGACY_METADATA = ['backgroundColor', 'barStyle', 'position', 'visibility']
  .map(name => `expo.harmony.navigationBar.${name}`);

function withHarmonyNavigationBar(config, input = {}) {
  if (!config.harmony?.bundleName && !config.platforms?.includes('harmony')) return config;

  const props = input ?? {};
  for (const name of ['backgroundColor', 'borderColor', 'behavior', 'position', 'enforceContrast']) {
    if (props[name] != null) {
      throw new TypeError(`Harmony expo-navigation-bar does not support the '${name}' config plugin option.`);
    }
  }

  for (const name of ['style', 'barStyle']) {
    if (props[name] != null && !STYLES.has(props[name])) {
      throw new TypeError(`Harmony expo-navigation-bar ${name} must be 'light' or 'dark'.`);
    }
  }
  if (props.hidden != null && typeof props.hidden !== 'boolean') {
    throw new TypeError('Harmony expo-navigation-bar hidden must be a boolean.');
  }
  if (props.visibility != null && !VISIBILITIES.has(props.visibility)) {
    throw new TypeError('Harmony expo-navigation-bar visibility must be \'visible\' or \'hidden\'.');
  }

  if ('barStyle' in props) console.warn('expo-navigation-bar: Use `style` instead of the deprecated `barStyle`.');
  if ('visibility' in props) console.warn('expo-navigation-bar: Use `hidden` instead of the deprecated `visibility`.');

  const style = props.style ?? props.barStyle;
  const hidden = props.hidden ?? (props.visibility == null ? undefined : props.visibility === 'hidden');

  return withModuleJson(config, (mod) => {
    const manifest = mod.modResults.module ??= {};
    for (const name of LEGACY_METADATA) HarmonyManifest.removeMetadata(manifest, name);
    const metadata = [[STYLE_METADATA, style], [HIDDEN_METADATA, hidden]].flatMap(
      ([name, value]) => value == null ? [] : [{ name, value: String(value) }]
    );
    HarmonyManifest.configureModuleMetadata(mod, metadata);
    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonyNavigationBar, pkg.name, pkg.version);
