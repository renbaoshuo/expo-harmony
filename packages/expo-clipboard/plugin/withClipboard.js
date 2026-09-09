'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const { registerHarmonyConfigPlugin, withStrings } = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

const READ_PERMISSION_REASON = 'expo_clipboard_read_permission_reason';

function withHarmonyClipboard(config, { clipboardPermission } = {}) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  if (clipboardPermission !== undefined
    && (typeof clipboardPermission !== 'string' || clipboardPermission.trim().length === 0)) {
    throw new TypeError('clipboardPermission must be a non-empty string.');
  }

  config = registerHarmonyConfigPlugin(config, pkg.name, {
    resources: { strings: { entry: [READ_PERMISSION_REASON] } },
  });

  return withStrings(config, (mod) => {
    const current = mod.modResults.entry?.string;
    const strings = (Array.isArray(current) ? current : [])
      .filter(resource => resource?.name !== READ_PERMISSION_REASON);

    if (clipboardPermission !== undefined) {
      strings.push({ name: READ_PERMISSION_REASON, value: clipboardPermission });
    }

    if (Array.isArray(current) || strings.length > 0) {
      mod.modResults.entry ??= {};
      mod.modResults.entry.string = strings;
    }

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonyClipboard, pkg.name, pkg.version);
