/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const path = require('node:path');
const { createRunOncePlugin } = require('expo/config-plugins');
const {
  HarmonyManifest, withModuleJson, withRawfile, parseHarmonySdkVersion, compareHarmonyApiVersions,
} = require('@expo-harmony/config-plugins');
const pkg = require('../package.json');

const PUSH_LISTENER_ACTION = 'action.ohos.push.listener';
const SLOT_METADATA = 'expo.modules.notifications.defaultSlotType';
const SLOT_TYPES = new Set(['service', 'social', 'content', 'other']);

function withNotifications(config, { defaultSlotType = 'service', sounds = [] } = {}) {
  if (!config.harmony?.bundleName && !config.platforms?.includes('harmony')) return config;
  if (!SLOT_TYPES.has(defaultSlotType)) throw new Error('Invalid expo-notifications defaultSlotType.');

  const configured = config.harmony?.compatibleSdkVersion;
  const sdk = parseHarmonySdkVersion(configured ?? 23, 'harmony.compatibleSdkVersion');
  if (compareHarmonyApiVersions(sdk.api, 23) < 0) {
    throw new Error('expo-notifications requires harmony.compatibleSdkVersion >= 23 (HarmonyOS 6.1.0).');
  }

  config.harmony = { ...config.harmony, compatibleSdkVersion: configured ?? 23 };

  if (!Array.isArray(sounds)) throw new Error('expo-notifications sounds must be an array of file paths.');

  const files = Object.create(null);
  for (const source of sounds) {
    if (typeof source !== 'string' || !source || !/\.(m4a|aac|mp3|ogg|wav|flac|amr)$/i.test(source)) {
      throw new Error(`Unsupported HarmonyOS notification sound: ${String(source)}.`);
    }
    const name = path.basename(source);
    if (Object.hasOwn(files, name)) throw new Error(`Duplicate HarmonyOS notification sound file name: ${name}.`);
    files[name] = { source };
  }

  config = withRawfile(config, { owner: pkg.name, files });

  return withModuleJson(config, (mod) => {
    const main = HarmonyManifest.getMainAbilityOrThrow(mod.modResults);
    const abilities = mod.modResults.module.abilities;
    const duplicate = abilities.some(ability => ability !== main
      && ability.skills?.some(skill => skill.actions?.includes(PUSH_LISTENER_ACTION)));

    if (duplicate) {
      throw new Error('Push Kit permits only one ability with action.ohos.push.listener; move it to the main Expo ability.');
    }

    main.launchType = 'singleton';
    // Push Kit's receiver skill must not inherit home/deep-link matching rules.
    main.skills = (main.skills ?? []).flatMap((skill) => {
      if (!skill.actions?.includes(PUSH_LISTENER_ACTION)) return [skill];

      const actions = skill.actions.filter(action => action !== PUSH_LISTENER_ACTION);

      return actions.length > 0 ? [{ ...skill, actions }] : [];
    });

    main.skills.push({ actions: [PUSH_LISTENER_ACTION] });
    HarmonyManifest.setMetadata(main, { name: PUSH_LISTENER_ACTION, value: 'true' });
    HarmonyManifest.setMetadata(main, { name: SLOT_METADATA, value: defaultSlotType });

    return mod;
  });
}

module.exports = createRunOncePlugin(withNotifications, pkg.name, pkg.version);
