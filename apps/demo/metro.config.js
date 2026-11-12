/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');
const path = require('node:path');

const projectRoot = __dirname;
const isHarmony = process.env.EXPO_METRO_TARGET === 'harmony';
if (isHarmony) process.env.EXPO_UNSTABLE_LOG_BOX ??= '1';

const config = getDefaultConfig(projectRoot);

if (isHarmony) {
  const enhance = config.server.enhanceMiddleware;
  const devtools = require('./metro/devtools');

  config.server.enhanceMiddleware = (middleware, server) => {
    const next = enhance ? enhance(middleware, server) : middleware;
    return (request, response, fallback) => devtools(request, response, () => next(request, response, fallback));
  };

  // Native HAR build trees contain copies of RNOH and are not JS source roots.
  const blockList = config.resolver.blockList;
  config.resolver.blockList = [
    ...(Array.isArray(blockList) ? blockList : blockList ? [blockList] : []),
    /[\\/]harmony[\\/]/,
  ];

  // Yarn keeps Router's native sidecars in its workspace node_modules.
  config.resolver.nodeModulesPaths = [
    ...config.resolver.nodeModulesPaths,
    path.join(path.dirname(require.resolve('@expo-harmony/expo-router/package.json')), 'node_modules'),
  ];
}

const harmonyConfig = withHarmonyConfig(config, {
  enabled: isHarmony,
  projectRoot,
});

module.exports = isHarmony ? require('@expo-harmony/expo__log-box/metro').withLogBox(harmonyConfig) : harmonyConfig;
