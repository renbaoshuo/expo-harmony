/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { createRunOncePlugin } = require('expo/config-plugins');
const {
  HarmonyResources,
  registerHarmonyConfigPlugin,
  withStrings,
} = require('@expo-harmony/config-plugins');

const NAME = 'expo-harmony-demo-oaid-permission-reason';
const OAID_REASON = 'expo_harmony_demo_oaid_permission_reason';

function withOaidPermissionReason(config) {
  if (!config.harmony?.bundleName && !config.platforms?.includes('harmony')) return config;

  config = registerHarmonyConfigPlugin(config, NAME, {
    resources: { strings: { entry: [OAID_REASON] } },
  });

  return withStrings(config, (mod) => {
    HarmonyResources.setString(mod.modResults.entry ??= {}, {
      name: OAID_REASON,
      value: '经你同意后，在演示页面读取并显示广告标识（OAID）。',
    });

    return mod;
  });
}

module.exports = createRunOncePlugin(withOaidPermissionReason, NAME);
