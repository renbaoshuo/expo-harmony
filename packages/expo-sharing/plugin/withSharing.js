'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const { registerHarmonyConfigPlugin, withModuleJson } = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

const SEND_ACTIONS = [
  'ohos.want.action.sendData',
  'ohos.want.action.sendMultipleData',
];
const SHARED_TYPES = [
  'general.text',
  'general.image',
  'general.video',
  'general.audio',
  'general.file',
];
const SHARING_SKILL = Object.freeze({
  actions: SEND_ACTIONS,
  uris: [
    ...SHARED_TYPES.map(utd => ({
      scheme: 'file',
      utd,
      maxFileSupported: 500,
    })),
    { scheme: 'http', utd: 'general.hyperlink' },
    { scheme: 'https', utd: 'general.hyperlink' },
  ],
});

function sameSkill(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function updateEntryAbility(json) {
  const module = json.module;
  if (!module || typeof module !== 'object' || !Array.isArray(module.abilities)) {
    return json;
  }

  const main = module.mainElement;
  const abilities = module.abilities.map((ability, index) => {
    if (!ability || typeof ability !== 'object') return ability;

    const selected = typeof main === 'string' ? ability.name === main : index === 0;
    if (!selected) return ability;

    const skills = Array.isArray(ability.skills) ? ability.skills : [];
    if (skills.some(skill => sameSkill(skill, SHARING_SKILL))) return ability;

    return { ...ability, skills: [...skills, SHARING_SKILL] };
  });

  return { ...json, module: { ...module, abilities } };
}

function withHarmonySharing(config) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, pkg.name);

  return withModuleJson(config, (mod) => {
    mod.modResults = updateEntryAbility(mod.modResults);
    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonySharing, pkg.name, pkg.version);
