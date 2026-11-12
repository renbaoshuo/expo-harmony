/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const { HarmonyManifest, withHarmonyPermissions, withModuleJson } = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');
const permission = 'ohos.permission.KEEP_BACKGROUND_RUNNING';

function withVideo(config, { supportsBackgroundPlayback = false } = {}) {
  if (!supportsBackgroundPlayback || (!config.harmony?.bundleName && !config.platforms?.includes('harmony'))) return config;

  return withModuleJson(withHarmonyPermissions(config, [{ name: permission }]), (mod) => {
    const ability = HarmonyManifest.getMainAbilityOrThrow(mod.modResults);
    const modes = ability.backgroundModes ?? [];
    if (!modes.includes('audioPlayback')) ability.backgroundModes = [...modes, 'audioPlayback'];

    return mod;
  });
}

module.exports = createRunOncePlugin(withVideo, pkg.name, pkg.version);
