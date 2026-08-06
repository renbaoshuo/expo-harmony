'use strict';

const { createWithHarmonyConfig } = require('./src/createWithHarmonyConfig');

let withHarmonyConfigImplementation;

function loadPeerDependency(moduleName) {
  try {
    return require(moduleName);
  } catch (cause) {
    const error = new Error(
      `@expo-harmony/metro-config could not load its peer dependency "${moduleName}". `
      + 'Install it in the app that owns the Metro configuration.',
      { cause }
    );
    error.code = 'ERR_EXPO_HARMONY_MISSING_PEER_DEPENDENCY';
    throw error;
  }
}

function getWithHarmonyConfigImplementation() {
  if (!withHarmonyConfigImplementation) {
    const { mergeConfig } = loadPeerDependency('metro-config');
    const { createHarmonyMetroConfig } = loadPeerDependency('@react-native-oh/react-native-harmony/metro.config');

    withHarmonyConfigImplementation = createWithHarmonyConfig({
      createHarmonyMetroConfig,
      mergeConfig,
    });
  }

  return withHarmonyConfigImplementation;
}

/**
 * Add the RNOH Metro configuration to an existing Expo/Metro configuration.
 *
 * Dependencies are loaded lazily so a shared metro.config.js can leave Harmony
 * disabled on machines where the optional RNOH toolchain is not installed.
 */
function withHarmonyConfig(config, options = {}) {
  if (options?.enabled === false) {
    return config;
  }

  return getWithHarmonyConfigImplementation()(config, options);
}

module.exports = { withHarmonyConfig };
