/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs/promises';

import { HarmonyPatchError } from './errors';

export async function getPatchFilesAsync(root: string, includeSymlinks = false): Promise<string[]> {
  try {
    const entries = await fs.readdir(root, { withFileTypes: true });

    return entries
      .filter(entry => (entry.isFile() || (includeSymlinks && entry.isSymbolicLink()))
        && /^harmony\+[a-f0-9]{32}\.patch$/u.test(entry.name))
      .map(entry => entry.name)
      .sort();
  } catch (cause) {
    if (cause.code === 'ENOENT') return [];

    throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Cannot read patch directory ${root}.`, { cause, file: root });
  }
}
