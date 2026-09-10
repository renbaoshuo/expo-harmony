'use strict';

const normalizeColor = require('@react-native/normalize-colors');
const { createRunOncePlugin } = require('@expo/config-plugins');
const { HarmonyManifest, HarmonyResources, withModuleJson } = require('@expo-harmony/config-plugins');
const pkg = require('../package.json');

const BUTTON_STYLES = new Set(['light', 'dark']);
const POSITIONS = new Set(['relative', 'absolute']);
const VISIBILITIES = new Set(['visible', 'hidden']);
const METADATA = Object.freeze({
  backgroundColor: 'expo.harmony.navigationBar.backgroundColor',
  barStyle: 'expo.harmony.navigationBar.barStyle',
  position: 'expo.harmony.navigationBar.position',
  visibility: 'expo.harmony.navigationBar.visibility',
});
const ANDROID_BAR_STYLES = Object.freeze({
  'dark-content': 'dark',
  'light-content': 'light',
});

function toArgb(value) {
  if (value == null) return null;

  const color = normalizeColor(value);
  if (color == null) {
    throw new TypeError('Harmony expo-navigation-bar backgroundColor must be a valid React Native color.');
  }

  return HarmonyResources.toArgb(color);
}

function validateValue(set, name, value) {
  if (value != null && !set.has(value)) {
    throw new TypeError(`Harmony expo-navigation-bar ${name} has invalid value '${String(value)}'.`);
  }
}

function resolveProps(config, props) {
  if (props != null) return props;

  const style = config.androidNavigationBar?.barStyle;

  return { barStyle: style == null ? undefined : ANDROID_BAR_STYLES[style] };
}

function withHarmonyNavigationBar(config, input) {
  const harmony = config.harmony || {};
  const enabled = harmony.bundleName || config.platforms?.includes('harmony');

  if (!enabled) return config;

  const props = resolveProps(config, input);

  for (const name of ['behavior', 'borderColor', 'enforceContrast']) {
    if (props[name] != null) {
      throw new TypeError(
        `Harmony expo-navigation-bar does not support the '${name}' config plugin option.`
      );
    }
  }

  validateValue(BUTTON_STYLES, 'barStyle', props.barStyle);
  validateValue(POSITIONS, 'position', props.position);
  validateValue(VISIBILITIES, 'visibility', props.visibility);

  return withModuleJson(config, (mod) => {
    const manifest = mod.modResults.module && typeof mod.modResults.module === 'object'
      ? mod.modResults.module
      : {};

    const target = { metadata: manifest.metadata };
    for (const [name, value] of [
      [METADATA.backgroundColor, toArgb(props.backgroundColor)],
      [METADATA.barStyle, props.barStyle],
      [METADATA.position, props.position],
      [METADATA.visibility, props.visibility],
    ]) {
      if (value == null) HarmonyManifest.removeMetadata(target, name);
      else HarmonyManifest.setMetadata(target, { name, value });
    }

    mod.modResults = {
      ...mod.modResults,
      module: { ...manifest, metadata: target.metadata },
    };

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonyNavigationBar, pkg.name, pkg.version);
