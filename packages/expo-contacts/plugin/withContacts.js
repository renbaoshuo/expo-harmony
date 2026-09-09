'use strict';

const { createRunOncePlugin } = require('@expo/config-plugins');
const { registerHarmonyConfigPlugin, withStrings } = require('@expo-harmony/config-plugins');

const pkg = require('../package.json');

function withHarmonyContacts(config, options = {}) {
  const enabled = config.harmony?.bundleName || config.platforms?.includes('harmony');
  if (!enabled) return config;

  for (const name of ['contactsPermission', 'readContactsPermission', 'writeContactsPermission']) {
    const value = options[name];
    if (value !== undefined && (typeof value !== 'string' || value.trim().length === 0)) {
      throw new TypeError(`${name} must be a non-empty string.`);
    }
  }

  const reasons = {
    expo_contacts_read_permission_reason: options.readContactsPermission ?? options.contactsPermission,
    expo_contacts_write_permission_reason: options.writeContactsPermission ?? options.contactsPermission,
  };
  const names = Object.keys(reasons);

  config = registerHarmonyConfigPlugin(config, pkg.name, {
    resources: { strings: { entry: names } },
  });

  return withStrings(config, (mod) => {
    const current = mod.modResults.entry?.string;
    const strings = (Array.isArray(current) ? current : []).filter(resource => !names.includes(resource?.name));

    for (const [name, value] of Object.entries(reasons)) {
      if (value !== undefined) strings.push({ name, value });
    }

    if (Array.isArray(current) || strings.length > 0) {
      mod.modResults.entry ??= {};
      mod.modResults.entry.string = strings;
    }

    return mod;
  });
}

module.exports = createRunOncePlugin(withHarmonyContacts, pkg.name, pkg.version);
