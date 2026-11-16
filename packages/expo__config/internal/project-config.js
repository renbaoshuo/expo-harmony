/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { realpathSync } = require('node:fs');
const { createRequire } = require('node:module');
const path = require('node:path');
const { getOriginalEnv, loadProjectEnv } = require('@expo/env');

function requireProjectConfig(root) {
  const load = createRequire(path.resolve(root, 'package.json'));
  for (const specifier of ['expo/config', '@expo/config']) {
    let resolved;
    try {
      resolved = load.resolve(specifier);
    } catch (error) {
      if (error.code !== 'MODULE_NOT_FOUND') throw error;
      continue;
    }
    return load(resolved);
  }
  return require('@expo/config');
}

function applyEnvironment(target, source) {
  for (const key of Object.keys(target)) {
    if (!Object.hasOwn(source, key)) delete target[key];
  }
  for (const [key, value] of Object.entries(source)) {
    if (target[key] !== value) target[key] = value;
  }
}

function stripPrivateHarmonyConfig(config) {
  if (!config.harmony || !Object.hasOwn(config.harmony, 'signingConfigFile')) return config;
  const harmony = { ...config.harmony };
  delete harmony.signingConfigFile;
  return { ...config, harmony };
}

function resetProjectConfigCache(root, entry) {
  const roots = [...new Set([path.resolve(root), realpathSync(root)])];
  const entries = new Set([entry, require.resolve(entry)]);
  const isProjectModule = filename => entries.has(filename) || roots.some((dir) => {
    const relative = path.relative(dir, filename);

    return relative !== '..'
      && !relative.startsWith(`..${path.sep}`)
      && !path.isAbsolute(relative)
      && !relative.split(path.sep).includes('node_modules');
  });

  // Project imports may capture dotenv values when they are loaded.
  const saved = new Map();
  for (const [filename, module] of Object.entries(require.cache)) {
    if (!isProjectModule(filename)) continue;

    saved.set(filename, module);
    if (module?.loaded) delete require.cache[filename];
  }

  return () => {
    for (const filename of Object.keys(require.cache)) {
      if (isProjectModule(filename) && !saved.has(filename)) delete require.cache[filename];
    }

    for (const [filename, module] of saved) require.cache[filename] = module;
  };
}

function getHarmonyProjectConfig(root, options, mode = 'development') {
  const processEnv = process.env;
  const originalEnv = { ...processEnv };
  const systemEnv = getOriginalEnv(processEnv);

  systemEnv.NODE_ENV ||= mode;
  systemEnv.BABEL_ENV ||= systemEnv.NODE_ENV;
  loadProjectEnv(root, { mode: systemEnv.NODE_ENV, systemEnv, silent: true });

  // Dynamic Expo config is evaluated synchronously. Keep project variables out
  // of other projects and native tool invocations in this process.
  const previousDev = Object.getOwnPropertyDescriptor(globalThis, '__DEV__');
  let restore;

  try {
    applyEnvironment(processEnv, systemEnv);
    globalThis.__DEV__ = systemEnv.NODE_ENV !== 'production';

    const { getConfig, getConfigFilePaths } = requireProjectConfig(root);
    const { dynamicConfigPath } = getConfigFilePaths(root);
    if (dynamicConfigPath) restore = resetProjectConfigCache(root, dynamicConfigPath);

    const config = getConfig(root, options);
    if (options?.isPublicConfig) config.exp = stripPrivateHarmonyConfig(config.exp);

    return config;
  } finally {
    restore?.();

    if (process.env !== processEnv) process.env = processEnv;
    applyEnvironment(processEnv, originalEnv);

    if (previousDev) Object.defineProperty(globalThis, '__DEV__', previousDev);
    else delete globalThis.__DEV__;
  }
}

module.exports = { getHarmonyProjectConfig, stripPrivateHarmonyConfig };
