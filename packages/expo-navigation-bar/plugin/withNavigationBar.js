'use strict';

const normalizeColor = require('@react-native/normalize-colors');
const { createRunOncePlugin } = require('@expo/config-plugins');
const { withModuleJson } = require('@expo-harmony/config-plugins');
const pkg = require('../package.json');

const BUTTON_STYLES = new Set(['light', 'dark']);
const POSITIONS = new Set(['relative', 'absolute']);
const VISIBILITIES = new Set(['visible', 'hidden']);
// Keep these keys aligned with the constants in ExpoNavigationBarPackage.ets.
const METADATA = Object.freeze({
  backgroundColor: 'expo.harmony.navigationBar.backgroundColor',
  barStyle: 'expo.harmony.navigationBar.barStyle',
  position: 'expo.harmony.navigationBar.position',
  visibility: 'expo.harmony.navigationBar.visibility',
});
const LEGACY_BAR_STYLES = Object.freeze({
  'dark-content': 'dark',
  'light-content': 'light',
});

function normalizeHarmonyColor(value) {
  if (value == null) return null;

  const color = normalizeColor(value);
  if (color == null) {
    throw new TypeError('Harmony expo-navigation-bar backgroundColor must be a valid React Native color.');
  }

  const rgba = color.toString(16).padStart(8, '0').toUpperCase();

  return `#${rgba.slice(6, 8)}${rgba.slice(0, 6)}`;
}

function setMetadata(items, name, value) {
  const next = (Array.isArray(items) ? items : []).filter(item => item?.name !== name);
  if (value != null) next.push({ name, value });

  return next;
}

function validateValue(set, name, value) {
  if (value != null && !set.has(value)) {
    throw new TypeError(`Harmony expo-navigation-bar ${name} has invalid value '${String(value)}'.`);
  }
}

function resolveProps(config, props) {
  if (props != null) return props;

  const style = config.androidNavigationBar?.barStyle;

  return { barStyle: style == null ? undefined : LEGACY_BAR_STYLES[style] };
}

function withHarmonyNavigationBar(config, input) {
  const harmony = config.harmony || {};
  const enabled = harmony.bundleName || config.platforms?.includes('harmony');

  if (!enabled) return config;

  const props = resolveProps(config, input);

  validateValue(BUTTON_STYLES, 'barStyle', props.barStyle);
  validateValue(POSITIONS, 'position', props.position);
  validateValue(VISIBILITIES, 'visibility', props.visibility);

  return withModuleJson(config, (mod) => {
    const manifest = mod.modResults.module && typeof mod.modResults.module === 'object'
      ? mod.modResults.module
      : {};

    let metadata = manifest.metadata;
    metadata = setMetadata(metadata, METADATA.backgroundColor, normalizeHarmonyColor(props.backgroundColor));
    metadata = setMetadata(metadata, METADATA.barStyle, props.barStyle);
    metadata = setMetadata(metadata, METADATA.position, props.position);
    metadata = setMetadata(metadata, METADATA.visibility, props.visibility);

    mod.modResults = {
      ...mod.modResults,
      module: { ...manifest, metadata },
    };

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonyNavigationBar, pkg.name, pkg.version);
