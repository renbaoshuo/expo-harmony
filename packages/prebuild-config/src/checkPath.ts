/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import path from 'node:path';

import { HarmonyPaths } from '@expo-harmony/config-plugins';

export function mirrorHarmonyCheckPath(temp: string, source: string): string {
  const absolute = path.resolve(source);
  if (HarmonyPaths.isInside(temp, absolute)) return absolute;

  const { root } = path.parse(absolute);
  const volume = root.replace(/[^A-Za-z0-9]+/gu, '') || 'root';
  return path.join(temp, 'filesystem', volume, absolute.slice(root.length));
}
