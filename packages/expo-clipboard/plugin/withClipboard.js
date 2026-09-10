'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const { HarmonyResources, registerHarmonyConfigPlugin, withStrings } = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

const READ_PERMISSION_REASON = 'expo_clipboard_read_permission_reason';

function withHarmonyClipboard(config, { clipboardPermission: permission } = {}) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  if (permission !== undefined
    && (typeof permission !== 'string' || permission.trim().length === 0)) {
    throw new TypeError('clipboardPermission must be a non-empty string.');
  }

  config = registerHarmonyConfigPlugin(config, pkg.name, {
    resources: { strings: { entry: [READ_PERMISSION_REASON] } },
  });

  return withStrings(config, (mod) => {
    const entry = mod.modResults.entry ??= {};
    HarmonyResources.removeString(entry, READ_PERMISSION_REASON);
    if (permission !== undefined) {
      HarmonyResources.setString(entry, { name: READ_PERMISSION_REASON, value: permission });
    }

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonyClipboard, pkg.name, pkg.version);
