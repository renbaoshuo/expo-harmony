/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  HarmonyConfigPluginError,
  HarmonyManifest,
  registerHarmonyConfigPlugin,
  withModuleJson,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

const SEND_ACTIONS = [
  'ohos.want.action.sendData',
  'ohos.want.action.sendMultipleData',
];
const DEFAULT_SHARED_TYPES = [
  'general.text',
  'general.file',
];
// SharedData supports up to 500 records (Share Kit API reference).
const MAX_SHARED_RECORDS = 500;
const DEFAULT_MAX_FILES = MAX_SHARED_RECORDS;
const SHARE_SCHEME_METADATA = 'expo.sharing.scheme';

function createSharingSkill(options) {
  const values = options.utds ?? DEFAULT_SHARED_TYPES;
  if (!Array.isArray(values) || values.some(value => typeof value !== 'string' || !value.trim())) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_CONFIG_INVALID',
      '@expo-harmony/expo-sharing utds must be an array of non-empty UTD strings.',
      { operation: 'configure-incoming-sharing' }
    );
  }

  if (options.allowMultiple !== undefined && typeof options.allowMultiple !== 'boolean') {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_CONFIG_INVALID',
      '@expo-harmony/expo-sharing allowMultiple must be a boolean.',
      { operation: 'configure-incoming-sharing' }
    );
  }

  const limit = options.maxFileSupported ?? DEFAULT_MAX_FILES;
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > MAX_SHARED_RECORDS) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_CONFIG_INVALID',
      `@expo-harmony/expo-sharing maxFileSupported must be between 1 and ${MAX_SHARED_RECORDS}.`,
      { operation: 'configure-incoming-sharing' }
    );
  }

  const actions = options.allowMultiple === false ? [SEND_ACTIONS[0]] : SEND_ACTIONS;
  const utds = [...new Set(values.map(value => value.trim()))].sort();

  return {
    actions,
    uris: [
      ...utds.map(utd => ({
        scheme: 'file',
        utd,
        maxFileSupported: limit,
      })),
      { scheme: 'http', utd: 'general.hyperlink' },
      { scheme: 'https', utd: 'general.hyperlink' },
    ],
  };
}

function updateEntryAbility(mod, options, scheme) {
  const module = mod.modResults.module;
  if (!module || typeof module !== 'object' || !Array.isArray(module.abilities)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_ABILITY_NOT_FOUND',
      '@expo-harmony/expo-sharing requires module.json5 to declare an abilities array.',
      { operation: 'configure-incoming-sharing' }
    );
  }

  const name = options.abilityName ?? module.mainElement;
  if (typeof name !== 'string' || !name) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_ABILITY_NOT_FOUND',
      'Set harmony.abilityName or module.mainElement before enabling incoming sharing.',
      { operation: 'configure-incoming-sharing' }
    );
  }

  const targets = module.abilities.filter(ability => ability?.name === name);
  if (targets.length !== 1) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_ABILITY_NOT_FOUND',
      `Expected exactly one incoming sharing target Ability '${name}', found ${targets.length}.`,
      { operation: 'configure-incoming-sharing' }
    );
  }

  const [target] = targets;
  if (target.exported !== true) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_ABILITY_NOT_EXPORTED',
      `Incoming sharing target Ability '${name}' must set exported: true.`,
      { operation: 'configure-incoming-sharing' }
    );
  }

  HarmonyManifest.configureAbility(mod, target, {
    skills: [createSharingSkill(options)],
    metadata: scheme === undefined ? [] : [{ name: SHARE_SCHEME_METADATA, value: scheme }],
  });
}

function withHarmonySharing(config, options = {}) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, pkg.name);

  return withModuleJson(config, (mod) => {
    const { scheme } = mod.modRawConfig;
    const shareScheme = (Array.isArray(scheme) ? scheme : [scheme])
      .find(value => typeof value === 'string' && /^[a-z][a-z0-9+.-]*$/i.test(value));
    updateEntryAbility(mod, {
      ...options,
      abilityName: options.abilityName ?? mod.modRawConfig.harmony?.abilityName,
    }, shareScheme);

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonySharing, pkg.name, pkg.version);
