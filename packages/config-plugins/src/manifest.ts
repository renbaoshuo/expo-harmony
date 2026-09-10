import type { HarmonyPermission, HarmonySkill } from './config';
import { HarmonyConfigPluginError } from './errors';
import { stableJson } from './files';

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
