import type { HarmonyPermission } from './config';
import { getModuleOrThrow, type HarmonyModuleJson } from './manifest';
import { withModuleJson } from './mods';
import { normalizePermission } from './normalizeConfig';
import type { HarmonyConfigPlugin } from './pluginTypes';

export function mergePermissions(
  current: readonly HarmonyPermission[],
  additions: readonly HarmonyPermission[]
): HarmonyPermission[] {
  const result = new Map<string, HarmonyPermission>();
  for (const input of [...current, ...additions]) {
    const permission = normalizePermission(input);
    const existing = result.get(permission.name);
    const scene = existing?.usedScene || permission.usedScene;
    const abilities = [...new Set([
      ...(existing?.usedScene?.abilities ?? []),
      ...(permission.usedScene?.abilities ?? []),
    ])];
    result.set(permission.name, {
      ...existing,
      ...permission,
      ...(scene
        ? {
            usedScene: {
              ...(abilities.length ? { abilities } : {}),
              when: existing?.usedScene?.when === 'always' || permission.usedScene?.when === 'always' ? 'always' : 'inuse',
            },
          }
        : {}),
    });
  }

  return [...result.values()];
}

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
  if (config.harmony) {
    config.harmony = { ...config.harmony, permissions: mergePermissions(config.harmony.permissions ?? [], additions) };
  }

  return withModuleJson(config, (mod) => {
    if (mod.modResults.module === undefined) mod.modResults.module = {};
    ensurePermissions(mod.modResults, additions);
    return mod;
  });
};

export const HarmonyPermissions = Object.freeze({ ensurePermissions, mergePermissions, removePermissions });
