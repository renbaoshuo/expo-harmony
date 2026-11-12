/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');

const { createRunOncePlugin, WarningAggregator } = require('@expo/config-plugins');
const { HarmonyConfigPluginError, withRawfile } = require('@expo-harmony/config-plugins');

const pkg = require('./package.json');

const AssetExtensions = new Set(['.png', '.jpg', '.gif', '.mp4', '.mp3', '.lottie', '.riv', '.glb', '.json', '.db']);

function assetPaths(props) {
  const assets = props?.assets ?? [];
  if (!Array.isArray(assets) || assets.some(asset => typeof asset !== 'string' || !asset)) {
    throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', 'expo-asset assets must be an array of non-empty paths.');
  }
  return assets;
}

function expandAssetPaths(root, assets) {
  return assets.flatMap((asset) => {
    const source = path.resolve(root, asset);
    if (!fs.statSync(source).isDirectory()) return [source];

    return fs.readdirSync(source).sort()
      .map(name => path.join(source, name))
      .filter(file => fs.statSync(file).isFile());
  });
}

function withHarmonyAssets(config, props) {
  if (!config.harmony?.bundleName && !config.platforms?.includes('harmony')) return config;

  const assets = [...assetPaths(props)];

  for (const plugin of config.plugins ?? []) {
    if (Array.isArray(plugin) && plugin[0] === 'expo-asset') {
      assets.push(...assetPaths(plugin[1]));
    }
  }

  if (!assets.length) return config;

  const root = config._internal?.projectRoot;
  if (!root) {
    throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', 'Expo Asset requires an Expo project root to resolve Harmony assets.');
  }

  const files = {};
  const sourcesByName = new Map();

  for (const source of expandAssetPaths(root, assets)) {
    const name = path.basename(source);
    const ext = path.extname(name);
    if (!AssetExtensions.has(ext)) {
      const hint = ext === '.ttf' || ext === '.otf' ? ' Use expo-font for fonts.' : '';
      WarningAggregator.addWarningForPlatform('harmony', 'expo-asset', `Ignoring unsupported Harmony asset '${name}'.${hint}`);
      continue;
    }

    if (!fs.statSync(source).isFile()) {
      throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `Harmony asset is not a file: ${source}`, { file: source });
    }

    const realSource = fs.realpathSync(source);
    const key = name.normalize('NFC').toLowerCase();
    const previous = sourcesByName.get(key);
    if (previous === realSource) continue;
    if (previous !== undefined) {
      throw new HarmonyConfigPluginError('ERR_HARMONY_CONFIG_INVALID', `Multiple Harmony assets use the filename '${name}'.`, { file: source });
    }

    sourcesByName.set(key, realSource);
    files[`expo-asset/${name}`] = { source: realSource };
  }

  return withRawfile(config, { owner: pkg.name, files });
}

module.exports = createRunOncePlugin(withHarmonyAssets, pkg.name, pkg.version);
