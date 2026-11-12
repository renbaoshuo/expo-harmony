/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  HarmonyResources,
  normalizeHarmonyConfig,
  registerHarmonyConfigPlugin,
  withModuleJson,
  withStrings,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

const BACKGROUND_PERMISSION = 'ohos.permission.KEEP_BACKGROUND_RUNNING';
const MICROPHONE_PERMISSION = 'ohos.permission.MICROPHONE';
const MICROPHONE_REASON = '$string:expo_audio_default_microphone_permission_reason';
const CUSTOM_MICROPHONE_REASON = 'expo_audio_microphone_permission_reason';
const PLAYBACK_MODE = 'audioPlayback';
const RECORDING_MODE = 'audioRecording';

function isPermissionReasonText(reason) {
  // Harmony permission reasons accept string resources or build placeholders, not literal text.
  return typeof reason === 'string'
    && !/^(?:[$]string:[0-9a-zA-Z_.]+|[$]?(?=.*[{])(?=.*[}])[0-9a-zA-Z_.{}]+)$/.test(reason);
}

function selectedAbilityName(module) {
  if (typeof module.mainElement === 'string' && module.mainElement.length > 0) return module.mainElement;
  if (!Array.isArray(module.abilities)) return undefined;

  return module.abilities.find(ability => ability && typeof ability.name === 'string')?.name;
}

function microphoneDeclaration(permission, ability, reason) {
  const current = permission && typeof permission === 'object' ? permission : {};
  const scene = current.usedScene && typeof current.usedScene === 'object' ? current.usedScene : {};

  const fallback = typeof current.reason === 'string'
    && !isPermissionReasonText(current.reason)
    && current.reason !== `$string:${CUSTOM_MICROPHONE_REASON}`
    ? current.reason
    : MICROPHONE_REASON;

  return {
    ...current,
    name: MICROPHONE_PERMISSION,
    reason: isPermissionReasonText(reason)
      ? `$string:${CUSTOM_MICROPHONE_REASON}`
      : (typeof reason === 'string' ? reason : fallback),
    ...(ability
      ? {
          usedScene: {
            ...scene,
            abilities: [...new Set([...(Array.isArray(scene.abilities) ? scene.abilities : []), ability])],
            when: scene.when === 'always' ? 'always' : 'inuse',
          },
        }
      : {}),
  };
}

function upsertMicrophonePermission(permissions, ability, enabled, reason) {
  if (!enabled) return permissions;

  const index = permissions.findIndex(permission => permission?.name === MICROPHONE_PERMISSION);
  const declaration = microphoneDeclaration(index >= 0 ? permissions[index] : undefined, ability, reason);

  if (index < 0) return [...permissions, declaration];

  return permissions.map((permission, position) => (position === index ? declaration : permission));
}

function addBackgroundPermission(permissions, enabled) {
  if (!enabled || permissions.some(permission => permission?.name === BACKGROUND_PERMISSION)) return permissions;

  return [...permissions, { name: BACKGROUND_PERMISSION }];
}

function updateHarmonyPermissions(config, options = {}) {
  const harmony = config.harmony;
  if (!harmony || typeof harmony !== 'object' || Array.isArray(harmony)) return config;

  const playback = options.enableBackgroundPlayback !== false;
  const recording = options.enableBackgroundRecording === true;
  const microphone = options.recordAudioAndroid !== false && options.microphonePermission !== false;
  const ability = normalizeHarmonyConfig(config).abilityName;
  const current = Array.isArray(harmony.permissions) ? harmony.permissions : [];
  const permissions = addBackgroundPermission(
    upsertMicrophonePermission(current, ability, microphone, options.microphonePermission),
    playback || recording
  );

  return { ...config, harmony: { ...harmony, permissions } };
}

function updateManifest(json, options = {}) {
  const module = json.module;
  if (!module || typeof module !== 'object') return json;

  const playback = options.enableBackgroundPlayback !== false;
  const recording = options.enableBackgroundRecording === true;
  const microphone = options.recordAudioAndroid !== false && options.microphonePermission !== false;
  const name = selectedAbilityName(module);

  const current = Array.isArray(module.requestPermissions) ? module.requestPermissions : [];
  const permissions = addBackgroundPermission(
    upsertMicrophonePermission(current, name, microphone, options.microphonePermission),
    playback || recording
  );

  const abilities = Array.isArray(module.abilities)
    ? module.abilities.map((ability) => {
        if (!ability || typeof ability !== 'object' || name === undefined || ability.name !== name) return ability;

        const modes = new Set(Array.isArray(ability.backgroundModes) ? ability.backgroundModes : []);
        if (playback) modes.add(PLAYBACK_MODE);
        if (recording) modes.add(RECORDING_MODE);

        return playback || recording ? { ...ability, backgroundModes: [...modes] } : ability;
      })
    : module.abilities;

  return { ...json, module: { ...module, abilities, requestPermissions: permissions } };
}

function withHarmonyAudio(config, options = {}) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = updateHarmonyPermissions(config, options);
  config = registerHarmonyConfigPlugin(config, pkg.name, {
    resources: { strings: { entry: [CUSTOM_MICROPHONE_REASON] } },
  });

  config = withModuleJson(config, (mod) => {
    mod.modResults = updateManifest(mod.modResults, options);

    return mod;
  });

  return withStrings(config, (mod) => {
    const entry = mod.modResults.entry ??= {};
    HarmonyResources.removeString(entry, CUSTOM_MICROPHONE_REASON);
    if (options.recordAudioAndroid !== false && isPermissionReasonText(options.microphonePermission)) {
      HarmonyResources.setString(entry, { name: CUSTOM_MICROPHONE_REASON, value: options.microphonePermission });
    }

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonyAudio, pkg.name, pkg.version);
