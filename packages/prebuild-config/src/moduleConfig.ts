/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { isDeepStrictEqual } from 'node:util';

import { HarmonyPermissions, stableHarmonyJson, type HarmonyPermission, type HarmonySkill } from '@expo-harmony/config-plugins';
import { isManagedManifestConfig, type ManagedManifestConfig } from '@expo-harmony/config-plugins/internal';

import { appendUnique } from './reconcile';

interface PermissionChange {
  before: HarmonyPermission | null;
  after: HarmonyPermission;
}

interface ManagedModuleConfig {
  pluginChanges?: ManagedManifestConfig[];
  permissions: PermissionChange[];
  querySchemes: string[];
  skills: HarmonySkill[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isPermissionRecord(value: unknown): value is Record<string, unknown> {
  return isRecord(value) && isNonEmptyString(value.name)
    && (value.usedScene === undefined || (isRecord(value.usedScene)
      && (value.usedScene.abilities === undefined || (Array.isArray(value.usedScene.abilities)
        && value.usedScene.abilities.every(isNonEmptyString)))));
}

function isManagedModuleConfig(value: unknown): value is ManagedModuleConfig {
  return isRecord(value)
    && (value.pluginChanges === undefined || isManagedManifestConfig(value.pluginChanges))
    && Array.isArray(value.permissions)
    && value.permissions.every(change => isRecord(change) && isPermissionRecord(change.after)
      && (change.before === null || (isPermissionRecord(change.before) && change.before.name === change.after.name)))
    && Array.isArray(value.querySchemes) && value.querySchemes.every(isNonEmptyString)
    && Array.isArray(value.skills) && value.skills.every(isRecord);
}

function reconcileModuleList<T>(current: unknown, previous: readonly T[], configured: readonly T[]) {
  const previousKeys = new Set(previous.map(stableHarmonyJson));
  const authored = (Array.isArray(current) ? current : [])
    .filter(value => !previousKeys.has(stableHarmonyJson(value)));
  const authoredKeys = new Set(authored.map(stableHarmonyJson));
  const managed: T[] = appendUnique([], configured)
    .filter(value => !authoredKeys.has(stableHarmonyJson(value)));

  return { values: [...authored, ...managed], managed };
}

function restoreFields(
  current: Record<string, unknown>, before: Record<string, unknown>, after: Record<string, unknown>
) {
  // Retain edits made to native values after the last generation.
  return Object.fromEntries(Object.entries(current).flatMap(([key, value]) => {
    if (!Object.hasOwn(after, key) || !isDeepStrictEqual(after[key], value)) return [[key, value]];
    return Object.hasOwn(before, key) ? [[key, before[key]]] : [];
  }));
}

function restorePermission(current: HarmonyPermission, change: PermissionChange): HarmonyPermission | null {
  if (isDeepStrictEqual(current, change.after)) return change.before;

  const { usedScene, ...fields } = current;
  const baseline: Partial<HarmonyPermission> = change.before ?? {};
  const { usedScene: beforeScene, ...before } = baseline;
  const { usedScene: afterScene, ...after } = change.after;
  const permission: HarmonyPermission = { ...restoreFields(fields, before, after), name: current.name };

  if (!usedScene || !afterScene) {
    if (usedScene) permission.usedScene = usedScene;
    return permission;
  }

  const scene = restoreFields(usedScene, beforeScene ?? {}, afterScene) as NonNullable<HarmonyPermission['usedScene']>;
  // The permission merge adds scene abilities individually.
  if (Array.isArray(usedScene.abilities) && Array.isArray(afterScene.abilities)) {
    const inserted = afterScene.abilities.filter(ability => !beforeScene?.abilities?.includes(ability));
    const abilities = usedScene.abilities.filter(ability => !inserted.includes(ability));
    if (abilities.length || beforeScene?.abilities) scene.abilities = abilities;
    else delete scene.abilities;
  }
  if (Object.keys(scene).length) permission.usedScene = scene;
  return permission;
}

function reconcileModulePermissions(
  current: unknown,
  previous: readonly PermissionChange[],
  configured: readonly HarmonyPermission[]
) {
  const byName = new Map(previous.map(change => [change.after.name, change]));
  const authored: HarmonyPermission[] = (Array.isArray(current) ? current : []).flatMap((permission) => {
    const change = byName.get(permission?.name);
    const retained = change ? restorePermission(permission, change) : permission;
    return retained === null ? [] : [retained];
  });
  const values = HarmonyPermissions.mergePermissions(authored, configured);
  const original = new Map(authored.map(permission => [permission.name, permission]));
  const configuredNames = new Set(configured.map(permission => permission.name));
  const managed = values.flatMap((after) => {
    const before = original.get(after.name) ?? null;
    return configuredNames.has(after.name) && !isDeepStrictEqual(before, after) ? [{ before, after }] : [];
  });

  return { values, managed };
}

export { isManagedModuleConfig, reconcileModuleList, reconcileModulePermissions };
export type { ManagedModuleConfig };
