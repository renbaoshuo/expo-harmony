/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const {
  HarmonyManifest,
  createRunOncePlugin,
  registerHarmonyConfigPlugin,
  withModuleJson,
} = require('@expo-harmony/config-plugins');
const withDevLauncher = require('@expo-harmony/expo-dev-launcher/app.plugin');
const pkg = require('./package.json');

const DEV_CLIENT_HOST = 'expo-development-client';

function withDevClient(config, options = {}) {
  if (!config.harmony?.bundleName && !config.platforms?.includes('harmony')) return config;

  const generate = options?.harmony?.addGeneratedScheme ?? options?.addGeneratedScheme ?? true;
  if (typeof generate !== 'boolean') {
    throw new TypeError('expo-dev-client addGeneratedScheme must be a boolean.');
  }

  const scheme = generate ? require('expo-dev-client/getDefaultScheme')(config) : undefined;

  config = withDevLauncher(config, options ?? {});
  config = registerHarmonyConfigPlugin(config, pkg.name);
  if (scheme === undefined) return config;

  return withModuleJson(config, (mod) => {
    const ability = HarmonyManifest.getMainAbilityOrThrow(mod.modResults);

    HarmonyManifest.configureAbility(mod, ability, {
      skills: [{
        actions: ['ohos.want.action.viewData'],
        entities: ['entity.system.browsable'],
        uris: [{ scheme, host: DEV_CLIENT_HOST }],
      }],
    });

    return mod;
  });
}

module.exports = createRunOncePlugin(withDevClient, pkg.name, pkg.version);
