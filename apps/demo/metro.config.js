'use strict';

const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');
const path = require('node:path');

const projectRoot = __dirname;
const isHarmony = process.env.EXPO_METRO_TARGET === 'harmony';
const config = getDefaultConfig(projectRoot);

if (isHarmony) {
  // Yarn keeps Router's native sidecars in its workspace node_modules.
  config.resolver.nodeModulesPaths = [
    ...config.resolver.nodeModulesPaths,
    path.join(path.dirname(require.resolve('@expo-harmony/expo-router/package.json')), 'node_modules'),
  ];
}

module.exports = withHarmonyConfig(config, {
  enabled: isHarmony,
  projectRoot,
  // RNOH 0.84 and Expo SDK 55 use different React renderer versions.
  aliases: { react: 'react-harmony' },
});
