'use strict';

const { getConfig } = require('@expo/config');
const { createRunOncePlugin } = require('@expo/config-plugins');
const { mergeContents } = require('@expo/config-plugins/build/utils/generateCode');
const {
  atomicWrite,
  HarmonyConfigPluginError,
  HarmonyPaths,
  normalizeHarmonyConfig,
  recordManagedFile,
  registerHarmonyConfigPlugin,
  withHarmonyDangerousMod,
  withRootHvigor,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

class ExpoConstantsPluginError extends HarmonyConfigPluginError {
  constructor(code, message, options = {}) {
    super(code, message, { ...options, operation: 'generate-constants' });
    this.name = 'ExpoConstantsPluginError';
  }
}

async function writeResourceAsync(root, harmony, config) {
  const file = await HarmonyPaths.resolveHarmonyPath(
    root,
    'entry/src/main/resources/rawfile/app.config'
  );

  const app = {
    ...config,
    version: config.version ?? harmony.versionName,
    harmony: {
      ...config.harmony,
      bundleName: harmony.bundleName,
      versionCode: harmony.versionCode,
      versionName: harmony.versionName,
      targetApiVersion: harmony.targetApiVersion,
    },
  };
  delete app.harmony.signingConfigFile;

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

async function refreshExpoConstantsResourceAsync(root, directory) {
  const config = getConfig(root, {
    isPublicConfig: true,
    skipPlugins: true,
  }).exp;

  const harmony = normalizeHarmonyConfig(config);

  return writeResourceAsync(directory, harmony, config);
}

function withConstants(config) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, pkg.name);

  config = withRootHvigor(config, (mod) => {
    mod.modResults = mergeContents({
      src: mod.modResults,
      newSrc: `require('@ohos/hvigor').hvigor.nodesEvaluated(async () => {
  const path = require('node:path');
  const root = path.resolve('..');
  const load = require('node:module').createRequire(path.join(root, 'package.json'));

  await load('@expo-harmony/expo-constants/plugin/withConstants')
    .refreshExpoConstantsResourceAsync(root, path.join(root, 'harmony'));
});`,
      tag: 'expo-harmony-constants',
      anchor: /^export default\b/m,
      offset: 0,
      comment: '//',
    }).contents;

    return mod;
  });

  return withHarmonyDangerousMod(config, async (mod) => {
    const file = await refreshExpoConstantsResourceAsync(
      mod.modRequest.projectRoot,
      mod.modRequest.platformProjectRoot
    );

    recordManagedFile(mod, file, pkg.name);

    return mod;
  });
}

module.exports = createRunOncePlugin(withConstants, pkg.name, pkg.version);
module.exports.refreshExpoConstantsResourceAsync = refreshExpoConstantsResourceAsync;
