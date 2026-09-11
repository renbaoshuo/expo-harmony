'use strict';

const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

module.exports = withHarmonyConfig(getDefaultConfig(__dirname), {
  projectRoot: __dirname,
});
