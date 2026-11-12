/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { HarmonyPermission, HarmonySkill } from './config';
import { HarmonyConfigPluginError } from './errors';
import { stableJson } from './files';
import type { HarmonyModConfig } from './pluginTypes';

export interface HarmonyMetadata extends Record<string, unknown> {
  name: string;
  value?: string;
  resource?: string;
}

export interface HarmonyAbility extends Record<string, unknown> {
  name: string;
  srcEntry?: string;
  exported?: boolean;
  skills?: HarmonySkill[];
  backgroundModes?: string[];
  metadata?: HarmonyMetadata[];
}

export interface HarmonyExtensionAbility extends HarmonyAbility {
  type: string;
}

export interface HarmonyModule extends Record<string, unknown> {
  name?: string;
  mainElement?: string;
  abilities?: HarmonyAbility[];
  extensionAbilities?: HarmonyExtensionAbility[];
  metadata?: HarmonyMetadata[];
  requestPermissions?: HarmonyPermission[];
  querySchemes?: string[];
}

export interface HarmonyModuleJson extends Record<string, unknown> {
  module?: HarmonyModule;
}

interface AbilityConfig {
  skills?: readonly HarmonySkill[];
  metadata?: readonly HarmonyMetadata[];
}

export interface ManagedManifestConfig {
  abilityName?: string;
  skills: HarmonySkill[];
  metadata: { before: HarmonyMetadata | null; after: HarmonyMetadata }[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isMetadata(value: unknown): value is HarmonyMetadata {
  return isRecord(value) && typeof value.name === 'string' && value.name.trim().length > 0;
}

export function isManagedManifestConfig(value: unknown): value is ManagedManifestConfig[] {
  return Array.isArray(value) && value.every(change => isRecord(change)
    && Array.isArray(change.skills) && change.skills.every(isRecord)
    && (change.abilityName === undefined
      ? change.skills.length === 0
      : typeof change.abilityName === 'string' && change.abilityName.trim().length > 0)
    && Array.isArray(change.metadata) && change.metadata.every(entry => isRecord(entry) && isMetadata(entry.after)
      && (entry.before === null || (isMetadata(entry.before) && entry.before.name === entry.after.name))));
}

export function configureAbility(
  mod: HarmonyModConfig<HarmonyModuleJson>, ability: HarmonyAbility, config: AbilityConfig
): void {
  const addedSkills: HarmonySkill[] = [];
  if (config.skills?.length) {
    const skills = ability.skills ?? [];
    if (!Array.isArray(skills)) {
      throw new HarmonyConfigPluginError('ERR_HARMONY_MANIFEST_INVALID', 'Ability skills must be an array.');
    }

    const keys = new Set(skills.map(stableJson));
    for (const skill of config.skills) {
      const key = stableJson(skill);
      if (keys.has(key)) continue;
      keys.add(key);
      addedSkills.push(skill);
    }
    if (addedSkills.length) ability.skills = [...skills, ...addedSkills];
  }
  const metadata = applyManagedMetadata(ability, config.metadata ?? []);
  recordManagedConfig(mod, { abilityName: ability.name, skills: addedSkills, metadata });
}

export function configureModuleMetadata(
  mod: HarmonyModConfig<HarmonyModuleJson>, items: readonly HarmonyMetadata[]
): void {
  const metadata = applyManagedMetadata(getModuleOrThrow(mod.modResults), items);
  recordManagedConfig(mod, { skills: [], metadata });
}

function applyManagedMetadata(
  target: { metadata?: HarmonyMetadata[] }, items: readonly HarmonyMetadata[]
): ManagedManifestConfig['metadata'] {
  const changes: ManagedManifestConfig['metadata'] = [];

  for (const item of items) {
    const before = Array.isArray(target.metadata)
      ? target.metadata.find(value => value?.name === item.name) ?? null
      : null;
    const after = { ...before, ...item };
    if (stableJson(before) === stableJson(after)) continue;

    setMetadata(target, item);
    changes.push({ before, after });
  }

  return changes;
}

function recordManagedConfig(mod: HarmonyModConfig<HarmonyModuleJson>, change: ManagedManifestConfig): void {
  const managed: ManagedManifestConfig[] | undefined = mod._internal?.harmonyManagedManifestConfig;
  if (change.skills.length || change.metadata.length) managed?.push(structuredClone(change));
}

export function restoreManagedManifestConfig(
  manifest: HarmonyModuleJson, changes: readonly ManagedManifestConfig[]
): void {
  const module = manifest.module;
  if (!module) return;

  for (const change of [...changes].reverse()) {
    const ability = change.abilityName !== undefined && Array.isArray(module.abilities)
      ? module.abilities.find(value => value?.name === change.abilityName)
      : undefined;
    const target = change.abilityName === undefined ? module : ability;
    if (!target) continue;

    if (Array.isArray(ability?.skills) && change.skills.length) {
      const generated = new Set(change.skills.map(stableJson));
      ability.skills = ability.skills.filter(skill => !generated.has(stableJson(skill)));
    }

    for (const { before, after } of [...change.metadata].reverse()) {
      if (!Array.isArray(target.metadata)) break;

      target.metadata = target.metadata.flatMap((item) => {
        if (item?.name !== after.name) return [item];
        if (stableJson(item) === stableJson(after)) return before ? [before] : [];

        // Restore owned fields still at the generated value. Keep other native edits.
        const restored: HarmonyMetadata = { ...item };
        for (const [key, value] of Object.entries(after)) {
          if (stableJson(value) === stableJson(before?.[key])
            || stableJson(value) !== stableJson(item[key])) continue;
          if (before && Object.hasOwn(before, key)) restored[key] = before[key];
          else delete restored[key];
        }
        restored.name = item.name;
        return [restored];
      });
    }
  }
}

export function getModuleOrThrow(manifest: HarmonyModuleJson): HarmonyModule {
  const module = manifest.module;
  if (!module || typeof module !== 'object' || Array.isArray(module)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony module.json5 must contain a module object.',
      { operation: 'edit-manifest' }
    );
  }

  return module;
}

export function getMainAbilityOrThrow(manifest: HarmonyModuleJson, name?: string): HarmonyAbility {
  const module = getModuleOrThrow(manifest);
  const abilities = module.abilities;
  if (!Array.isArray(abilities)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony module.json5 must declare an abilities array.',
      { operation: 'edit-manifest' }
    );
  }

  const selected = name ?? module.mainElement ?? abilities[0]?.name;
  const matches = abilities.filter(ability => ability && typeof ability.name === 'string' && ability.name === selected);
  if (matches.length !== 1) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MANIFEST_INVALID',
      `Expected exactly one Harmony Ability '${selected ?? ''}', found ${matches.length}.`,
      { operation: 'edit-manifest' }
    );
  }

  return matches[0];
}

export function setMetadata(target: { metadata?: HarmonyMetadata[] }, item: HarmonyMetadata): void {
  if (!item || typeof item.name !== 'string' || !item.name.trim()) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Metadata must have a non-empty name.',
      { operation: 'edit-manifest' }
    );
  }
  if (target.metadata !== undefined && !Array.isArray(target.metadata)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'metadata must be an array.',
      { operation: 'edit-manifest' }
    );
  }

  const items = target.metadata ?? [];
  const existing = items.find(value => value?.name === item.name);
  target.metadata = [...items.filter(value => value?.name !== item.name), { ...existing, ...item }];
}

export function removeMetadata(target: { metadata?: HarmonyMetadata[] }, name: string): void {
  if (target.metadata !== undefined && !Array.isArray(target.metadata)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'metadata must be an array.',
      { operation: 'edit-manifest' }
    );
  }

  if (target.metadata) target.metadata = target.metadata.filter(item => item?.name !== name);
}

export function ensureExtensionAbility(manifest: HarmonyModuleJson, ability: HarmonyExtensionAbility): void {
  if (!ability || typeof ability.name !== 'string' || !ability.name.trim()
    || typeof ability.type !== 'string' || !ability.type.trim()) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'An extension Ability must have a non-empty name and type.',
      { operation: 'edit-manifest' }
    );
  }

  const module = getModuleOrThrow(manifest);
  if (module.extensionAbilities !== undefined && !Array.isArray(module.extensionAbilities)) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'module.extensionAbilities must be an array.',
      { operation: 'edit-manifest' }
    );
  }

  const abilities = module.extensionAbilities ?? [];
  const matches = abilities.filter(value => value?.name === ability.name);
  if (matches.length > 1) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_MANIFEST_INVALID',
      `Harmony module declares ${ability.name} more than once.`,
      { operation: 'edit-manifest' }
    );
  }
  if (matches.length === 1) {
    for (const [key, value] of Object.entries(ability)) {
      if (stableJson(matches[0][key]) !== stableJson(value)) {
        throw new HarmonyConfigPluginError(
          'ERR_HARMONY_MANIFEST_INVALID',
          `Harmony extension Ability '${ability.name}' has an incompatible ${key}.`,
          { operation: 'edit-manifest' }
        );
      }
    }

    return;
  }

  module.extensionAbilities = [...abilities, structuredClone(ability)];
}
