/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const {
  HarmonyManifest,
  registerHarmonyConfigPlugin,
  withModuleJson,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

const INTERNET_PERMISSION = 'ohos.permission.INTERNET';
const NETWORK_INFO_PERMISSION = 'ohos.permission.GET_NETWORK_INFO';
const LAUNCH_MODE_METADATA = 'expo.devLauncher.launchMode';
const BOOLEAN_METADATA = {
  toolsButton: 'EXDevMenuShowFloatingActionButton',
  embeddedBundle: 'EXDevClientEmbeddedBundle',
  skipOnboarding: 'EXDevMenuIsOnboardingFinished',
  showMenuAtLaunch: 'EXDevMenuShowsAtLaunch',
};
const DEFAULT_URL_METADATA = 'DEV_CLIENT_DEFAULT_LAUNCHER_URL';
const AUTO_LAUNCH_METADATA = 'DEV_CLIENT_TRY_TO_LAUNCH_LAST_BUNDLE';
const DEEP_LINK_SCHEME = 'expo-harmony';
const DEEP_LINK_HOST = 'open';
const EXPO_DEV_CLIENT_HOST = 'expo-development-client';
const VIEW_ACTION = 'ohos.want.action.viewData';
const BROWSABLE_ENTITY = 'entity.system.browsable';

function launchMode(options) {
  const value = options.launchMode ?? options.launchModeExperimental ?? 'most-recent';
  if (value !== 'most-recent' && value !== 'launcher') {
    throw new TypeError('expo-dev-launcher launchMode must be \'most-recent\' or \'launcher\'.');
  }
  return value;
}

function selectedAbility(module) {
  const name = module.mainElement;
  return Array.isArray(module.abilities)
    ? module.abilities.find((ability, index) => ability?.name === name || (!name && index === 0))
    : undefined;
}

function parseLaunchURL(value) {
  const authority = value.match(/^[a-z][a-z\d+.-]*:\/\/([^/?#]*)/i)?.[1];
  if (!authority || authority.includes('@') || value.includes('#')) {
    throw new TypeError('expo-dev-launcher defaultLaunchURL requires a host and cannot include credentials or fragments.');
  }
  decodeURIComponent(value);

  return new URL(value);
}

function updateManifest(mod, options = {}) {
  const module = mod.modResults.module;
  if (!module || typeof module !== 'object') throw new TypeError('expo-dev-launcher requires a Harmony module manifest.');

  const ability = selectedAbility(module);
  if (!ability) throw new TypeError('expo-dev-launcher requires an entry UIAbility.');

  const mode = launchMode(options);
  const metadata = [
    { name: LAUNCH_MODE_METADATA, value: mode },
    { name: AUTO_LAUNCH_METADATA, value: String(mode === 'most-recent') },
  ];

  for (const [option, name] of Object.entries(BOOLEAN_METADATA)) {
    if (options[option] !== undefined && typeof options[option] !== 'boolean') {
      throw new TypeError(`expo-dev-launcher ${option} must be a boolean.`);
    }
    if (options[option] !== undefined) metadata.push({ name, value: String(options[option]) });
  }
  if (options.defaultLaunchURL !== undefined) {
    if (typeof options.defaultLaunchURL !== 'string' || !options.defaultLaunchURL.trim()) {
      throw new TypeError('expo-dev-launcher defaultLaunchURL must be a non-empty URL string.');
    }

    const defaultURL = options.defaultLaunchURL.trim();
    const parsed = parseLaunchURL(defaultURL);
    const host = parsed.hostname.toLowerCase();
    const isWrapper = parsed.protocol === `${DEEP_LINK_SCHEME}:` ? host === DEEP_LINK_HOST : host === EXPO_DEV_CLIENT_HOST;
    const innerURL = parsed.searchParams.get('url');
    if (isWrapper && !innerURL) throw new TypeError('expo-dev-launcher defaultLaunchURL is missing its url parameter.');

    const resolved = isWrapper ? parseLaunchURL(innerURL.trim()) : parsed;
    if (!['http:', 'https:', 'exp:', 'exps:'].includes(resolved.protocol) || !resolved.hostname) {
      throw new TypeError('expo-dev-launcher defaultLaunchURL must resolve to an HTTP(S) or exp(s) URL.');
    }
    metadata.push({ name: DEFAULT_URL_METADATA, value: defaultURL });
  }

  const permissions = Array.isArray(module.requestPermissions) ? module.requestPermissions : [];
  const managedPermissions = new Set([INTERNET_PERMISSION, NETWORK_INFO_PERMISSION]);
  module.requestPermissions = [
    ...permissions.filter(permission => !managedPermissions.has(permission?.name)),
    permissions.find(permission => permission?.name === INTERNET_PERMISSION) ?? { name: INTERNET_PERMISSION },
    permissions.find(permission => permission?.name === NETWORK_INFO_PERMISSION) ?? { name: NETWORK_INFO_PERMISSION },
  ];
  const launcherSkill = {
    entities: [BROWSABLE_ENTITY],
    actions: [VIEW_ACTION],
    uris: [{ scheme: DEEP_LINK_SCHEME, host: DEEP_LINK_HOST }],
  };
  HarmonyManifest.configureModuleMetadata(mod, metadata);
  HarmonyManifest.configureAbility(mod, ability, { skills: [launcherSkill] });
}

function withHarmonyDevLauncher(config, options = {}) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, pkg.name);
  const selected = {};
  for (const key of ['defaultLaunchURL', ...Object.keys(BOOLEAN_METADATA)]) {
    selected[key] = options.harmony?.[key] ?? options[key] ?? undefined;
  }
  // Like upstream, a common launchMode takes precedence over deprecated options.
  selected.launchMode = options.harmony?.launchMode ?? options.launchMode
    ?? options.harmony?.launchModeExperimental ?? options.launchModeExperimental;
  config = withModuleJson(config, (mod) => {
    updateManifest(mod, selected);
    return mod;
  });

  return config;
}

module.exports = createRunOncePlugin(withHarmonyDevLauncher, pkg.name, pkg.version);
