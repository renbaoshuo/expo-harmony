'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  HarmonyConfigPluginError,
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
const DEFAULT_MAX_FILES = 50;

function createSharingSkill(options) {
  const values = options.utds ?? DEFAULT_SHARED_TYPES;
  if (!Array.isArray(values) || values.some(value => typeof value !== 'string' || !value)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_CONFIG_INVALID',
      '@expo-harmony/expo-sharing utds must be an array of non-empty UTD strings.',
      { operation: 'configure-incoming-sharing' }
    );
  }

  const limit = options.maxFileSupported ?? DEFAULT_MAX_FILES;
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > DEFAULT_MAX_FILES) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_CONFIG_INVALID',
      `@expo-harmony/expo-sharing maxFileSupported must be between 1 and ${DEFAULT_MAX_FILES}.`,
      { operation: 'configure-incoming-sharing' }
    );
  }

  const actions = options.allowMultiple === false ? [SEND_ACTIONS[0]] : SEND_ACTIONS;
  const utds = [...new Set(values)].sort();

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

function isSharingSkill(skill) {
  return skill && typeof skill === 'object' && Array.isArray(skill.actions)
    && skill.actions.some(action => SEND_ACTIONS.includes(action));
}

function updateEntryAbility(json, options = {}) {
  const module = json.module;
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

  const target = module.abilities.find(ability => ability?.name === name);
  if (!target) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_ABILITY_NOT_FOUND',
      `Incoming sharing target Ability '${name}' does not exist.`,
      { operation: 'configure-incoming-sharing' }
    );
  }
  if (target.exported !== true) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_SHARING_ABILITY_NOT_EXPORTED',
      `Incoming sharing target Ability '${name}' must set exported: true.`,
      { operation: 'configure-incoming-sharing' }
    );
  }

  const skill = createSharingSkill(options);
  const abilities = module.abilities.map((ability) => {
    if (!ability || typeof ability !== 'object') return ability;
    if (ability.name !== name) return ability;

    const skills = Array.isArray(ability.skills) ? ability.skills : [];

    return {
      ...ability,
      skills: [...skills.filter(value => !isSharingSkill(value)), skill],
    };
  });

  return { ...json, module: { ...module, abilities } };
}

function withHarmonySharing(config, options = {}) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, pkg.name);

  return withModuleJson(config, (mod) => {
    mod.modResults = updateEntryAbility(mod.modResults, {
      ...options,
      abilityName: options.abilityName ?? mod.modRawConfig.harmony?.abilityName,
    });

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonySharing, pkg.name, pkg.version);
