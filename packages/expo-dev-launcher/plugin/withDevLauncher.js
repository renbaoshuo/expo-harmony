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
  withHarmonyPermissions,
  withModuleJson,
} = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

const INTERNET_PERMISSION = 'ohos.permission.INTERNET';
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

function parseLaunchURL(value) {
  const authority = value.match(/^[a-z][a-z\d+.-]*:\/\/([^/?#]*)/i)?.[1];
  if (!authority || authority.includes('@') || value.includes('#')) {
    throw new TypeError('expo-dev-launcher defaultLaunchURL requires a host and cannot include credentials or fragments.');
  }
  decodeURIComponent(value);

  return new URL(value);
}

function updateManifest(mod, options = {}) {
  const ability = HarmonyManifest.getMainAbilityOrThrow(mod.modResults);

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

    const url = options.defaultLaunchURL.trim();
    const parsed = parseLaunchURL(url);
    const host = parsed.hostname.toLowerCase();
    const wrapped = parsed.protocol === `${DEEP_LINK_SCHEME}:` ? host === DEEP_LINK_HOST : host === EXPO_DEV_CLIENT_HOST;
    const inner = parsed.searchParams.get('url');
    if (wrapped && !inner) throw new TypeError('expo-dev-launcher defaultLaunchURL is missing its url parameter.');

    const resolved = wrapped ? parseLaunchURL(inner.trim()) : parsed;
    if (!['http:', 'https:', 'exp:', 'exps:'].includes(resolved.protocol) || !resolved.hostname) {
      throw new TypeError('expo-dev-launcher defaultLaunchURL must resolve to an HTTP(S) or exp(s) URL.');
    }

    metadata.push({ name: DEFAULT_URL_METADATA, value: url });
  }

  const skill = {
    entities: [BROWSABLE_ENTITY],
    actions: [VIEW_ACTION],
    uris: [{ scheme: DEEP_LINK_SCHEME, host: DEEP_LINK_HOST }],
  };
  HarmonyManifest.configureModuleMetadata(mod, metadata);
  HarmonyManifest.configureAbility(mod, ability, { skills: [skill] });
}

function withHarmonyDevLauncher(config, options = {}) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  config = registerHarmonyConfigPlugin(config, pkg.name);
  config = withHarmonyPermissions(config, [{ name: INTERNET_PERMISSION }]);

  const selected = {};
  for (const key of ['defaultLaunchURL', ...Object.keys(BOOLEAN_METADATA)]) {
    selected[key] = options.harmony?.[key] ?? options[key] ?? undefined;
  }
  selected.launchMode = options.harmony?.launchMode ?? options.launchMode
    ?? options.harmony?.launchModeExperimental ?? options.launchModeExperimental;

  config = withModuleJson(config, (mod) => {
    updateManifest(mod, selected);
    return mod;
  });

  return config;
}

module.exports = createRunOncePlugin(withHarmonyDevLauncher, pkg.name, pkg.version);
