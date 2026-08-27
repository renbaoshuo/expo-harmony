'use strict';

const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

const projectRoot = __dirname;

module.exports = withHarmonyConfig(getDefaultConfig(projectRoot), {
  enabled: process.env.EXPO_METRO_TARGET === 'harmony',
  projectRoot,
});
