import fs from 'node:fs/promises';

import { HarmonyPatchError } from './errors';

export async function getPatchFilesAsync(root: string): Promise<string[]> {
  try {
    return (await fs.readdir(root)).filter(name => name.startsWith('harmony') && name.endsWith('.patch')).sort();
  } catch (cause) {
    if (cause.code === 'ENOENT') return [];

    throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Cannot read patch directory ${root}.`, { cause, file: root });
  }
}
