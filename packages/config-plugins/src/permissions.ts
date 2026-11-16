/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { HarmonyPermission } from './config';
import { getModuleOrThrow, type HarmonyModuleJson } from './manifest';
import { withModuleJson } from './mods';
import { getDeclaredPermissions, mergePermissions } from './normalizeConfig';
import type { HarmonyConfigPlugin } from './pluginTypes';

export function ensurePermissions(
  manifest: HarmonyModuleJson,
  permissions: readonly HarmonyPermission[]
): HarmonyModuleJson {
  const module = getModuleOrThrow(manifest);
  module.requestPermissions = mergePermissions(module.requestPermissions ?? [], permissions);
  return manifest;
}

export function removePermissions(manifest: HarmonyModuleJson, names: readonly string[]): HarmonyModuleJson {
  const module = getModuleOrThrow(manifest);
  if (module.requestPermissions) {
    module.requestPermissions = module.requestPermissions.filter(permission => !names.includes(permission.name));
  }

  return manifest;
}

export const withHarmonyPermissions: HarmonyConfigPlugin<readonly HarmonyPermission[]> = (config, permissions) => {
  const additions = mergePermissions([], permissions);
  const names = new Set(additions.map(permission => permission.name));
  const merged = mergePermissions(getDeclaredPermissions(config) ?? [], additions);

  if (config.harmony) {
    config.harmony = { ...config.harmony, permissions: merged };
    if (config._internal) delete config._internal.harmonyPermissionDeclarations;
  } else {
    config._internal ??= {};
    config._internal.harmonyPermissionDeclarations = merged;
  }

  return withModuleJson(config, (mod) => {
    // Let the CNG journal record ownership of these declarations.
    if (mod._internal?.harmonyManagedModuleConfig) return mod;

    if (mod.modResults.module === undefined) mod.modResults.module = {};

    // Reverse mod order must not restore an earlier permission reason.
    const selected = (getDeclaredPermissions(mod.modRawConfig) ?? additions)
      .filter(permission => names.has(permission.name));

    ensurePermissions(mod.modResults, selected);

    return mod;
  });
};

export const HarmonyPermissions = Object.freeze({ ensurePermissions, mergePermissions, removePermissions });
