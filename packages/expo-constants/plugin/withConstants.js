'use strict';

const { getConfig } = require('@expo/config');
const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  atomicWrite,
  HarmonyConfigPluginError,
  HarmonyPaths,
  normalizeHarmonyConfig,
  recordManagedFile,
  registerHarmonyConfigPlugin,
  withHarmonyDangerousMod,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

class ExpoConstantsPluginError extends HarmonyConfigPluginError {
  constructor(code, message, options = {}) {
    super(code, message, { ...options, operation: 'generate-constants' });
    this.name = 'ExpoConstantsPluginError';
  }
}

function removeHarmonyPrivateConfig(config) {
  const value = { ...config };
  if (value.harmony) {
    value.harmony = { ...value.harmony };
    delete value.harmony.signingConfigFile;
  }
  return value;
}

async function writeExpoConstantsResourceAsync(root, harmony, config) {
  const file = await HarmonyPaths.resolveHarmonyPath(
    root,
    'entry/src/main/resources/rawfile/app.config'
  );

  const app = removeHarmonyPrivateConfig(config);
  app.version ??= harmony.versionName;
  app.harmony = {
    ...(app.harmony || {}),
    bundleName: harmony.bundleName,
    versionCode: harmony.versionCode,
    versionName: harmony.versionName,
    targetApiVersion: harmony.targetApiVersion,
  };

  const content = JSON.stringify(app);

  try {
    await atomicWrite(file, content);
  } catch (cause) {
    throw new ExpoConstantsPluginError(
      'ERR_HARMONY_CONSTANTS_WRITE_FAILED',
      `Unable to write the generated Expo Constants app config: ${file}`,
      { cause, file }
    );
  }

  return file;
}

async function refreshExpoConstantsResourceAsync(projectRoot, harmonyRoot) {
  const publicConfig = getConfig(projectRoot, {
    isPublicConfig: true,
    skipPlugins: true,
  }).exp;
  const harmony = normalizeHarmonyConfig(publicConfig);

  return writeExpoConstantsResourceAsync(harmonyRoot, harmony, publicConfig);
}

function withHarmonyConstants(config) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, pkg.name);

  return withHarmonyDangerousMod(config, async (mod) => {
    const file = await refreshExpoConstantsResourceAsync(
      mod.modRequest.projectRoot,
      mod.modRequest.platformProjectRoot
    );

    recordManagedFile(mod, file, pkg.name);

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonyConstants, pkg.name, pkg.version);
module.exports.removeHarmonyPrivateConfig = removeHarmonyPrivateConfig;
module.exports.refreshExpoConstantsResourceAsync = refreshExpoConstantsResourceAsync;
module.exports.withHarmonyConstants = withHarmonyConstants;
module.exports.writeExpoConstantsResourceAsync = writeExpoConstantsResourceAsync;
