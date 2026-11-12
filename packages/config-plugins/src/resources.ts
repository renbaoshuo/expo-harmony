/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { createRequire } from 'node:module';

import { HarmonyConfigPluginError } from './errors';

const normalizeReactNativeColor = createRequire(__filename)('@react-native/normalize-colors') as (
  value: string
) => number | null;

export interface HarmonyResourceItem extends Record<string, unknown> {
  name: string;
  value: string;
}

export interface HarmonyResourceFile extends Record<string, unknown> {
  string?: HarmonyResourceItem[];
  color?: HarmonyResourceItem[];
}

function setItem(file: HarmonyResourceFile, kind: 'string' | 'color', item: HarmonyResourceItem): HarmonyResourceFile {
  if (!item || typeof item.name !== 'string' || !/^[A-Za-z0-9_.-]+$/.test(item.name)
    || item.name.includes('..') || typeof item.value !== 'string') {
    throw new HarmonyConfigPluginError('ERR_HARMONY_RESOURCE_INVALID', `Invalid Harmony ${kind} resource.`, { operation: 'edit-resource' });
  }

  const items = readItems(file, kind);
  const existing = items.find(value => value?.name === item.name);
  file[kind] = [...items.filter(value => value?.name !== item.name), { ...existing, ...item }];

  return file;
}

function readItems(file: HarmonyResourceFile, kind: 'string' | 'color'): HarmonyResourceItem[] {
  if (file[kind] !== undefined && !Array.isArray(file[kind])) {
    throw new HarmonyConfigPluginError('ERR_HARMONY_RESOURCE_INVALID', `Harmony ${kind} resources must be an array.`, { operation: 'edit-resource' });
  }

  return file[kind] ?? [];
}

export function setString(file: HarmonyResourceFile, item: HarmonyResourceItem): HarmonyResourceFile {
  return setItem(file, 'string', item);
}

export function removeString(file: HarmonyResourceFile, name: string): HarmonyResourceFile {
  const items = readItems(file, 'string');
  if (file.string) file.string = items.filter(item => item?.name !== name);
  return file;
}

export function setColor(file: HarmonyResourceFile, item: HarmonyResourceItem): HarmonyResourceFile {
  return setItem(file, 'color', item);
}

export function removeColor(file: HarmonyResourceFile, name: string): HarmonyResourceFile {
  const items = readItems(file, 'color');
  if (file.color) file.color = items.filter(item => item?.name !== name);
  return file;
}

export function toArgb(value: string | number): string {
  if (typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value)) return value.toUpperCase();

  const color = typeof value === 'string' ? normalizeReactNativeColor(value) : value;
  if (color == null || !Number.isInteger(color) || color < 0 || color > 0xffffffff) {
    throw new HarmonyConfigPluginError(
      'ERR_HARMONY_CONFIG_INVALID', 'Color must be a valid React Native color or an unsigned RGBA integer.',
      { operation: 'convert-color' }
    );
  }

  const hex = color.toString(16).padStart(8, '0');
  return `#${hex.slice(6, 8)}${hex.slice(0, 6)}`.toUpperCase();
}
