/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { fork } = require('node:child_process');
const { once } = require('node:events');
const { readFile } = require('node:fs/promises');
const path = require('node:path');
const { createRunOncePlugin } = require('expo/config-plugins');
const { mergeContents } = require('@expo/config-plugins/build/utils/generateCode');
const {
  atomicWrite,
  HarmonyConfigPluginError,
  HarmonyPaths,
  recordManagedFile,
  registerHarmonyConfigPlugin,
  withHarmonyDangerousMod,
  withRootHvigor,
} = require('@expo-harmony/config-plugins');
const { getHarmonyProjectConfig } = require('@expo-harmony/expo__config/internal/project-config');

const pkg = require('../package.json');

class ExpoConstantsPluginError extends HarmonyConfigPluginError {
  constructor(code, message, options = {}) {
    super(code, message, { ...options, operation: 'generate-constants' });
    this.name = 'ExpoConstantsPluginError';
  }
}

async function writeResourceAsync(root, config) {
  const file = await HarmonyPaths.resolveHarmonyPath(
    root,
    'entry/src/main/resources/rawfile/app.config'
  );
  const content = JSON.stringify(config);

  try {
    const previous = await readFile(file, 'utf8').catch((cause) => {
      if (cause.code === 'ENOENT') return undefined;
      throw cause;
    });

    if (previous !== content) await atomicWrite(file, content);
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
  root = path.resolve(root);
  directory = path.resolve(directory);

  // Hvigor can reuse a process across builds, while Expo's config loader caches
  // app.config.js and its imports. Evaluate in a fresh process rooted at the app.
  let config;
  try {
    const child = fork(__filename, [], { cwd: root, execArgv: [] });
    child.once('message', (value) => {
      config = value;
    });
    const [code, signal] = await once(child, 'close');
    if (code !== 0 || !config) throw new Error(signal ?? `exit ${code}`);
  } catch (cause) {
    throw new ExpoConstantsPluginError(
      'ERR_HARMONY_CONSTANTS_CONFIG_FAILED',
      `Unable to evaluate the public Expo config in ${root}.`,
      { cause, file: root }
    );
  }

  return writeResourceAsync(directory, config);
}

function withConstants(config) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, pkg.name);

  config = withRootHvigor(config, (mod) => {
    mod.modResults = mergeContents({
      src: mod.modResults,
      newSrc: `require('@ohos/hvigor').hvigor.nodesEvaluated(async (hvigor) => {
  const path = require('node:path');
  const harmony = hvigor.getRootNode().getNodePath();
  const root = path.dirname(harmony);
  const load = require('node:module').createRequire(path.join(root, 'package.json'));

  await load('@expo-harmony/expo-constants/plugin/withConstants')
    .refreshExpoConstantsResourceAsync(root, harmony);
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

if (require.main === module && process.send) {
  process.send(getHarmonyProjectConfig(process.cwd(), {
    isPublicConfig: true,
    skipSDKVersionRequirement: true,
  }).exp);
}
