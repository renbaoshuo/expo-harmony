import fs from 'node:fs/promises';
import path from 'node:path';

import { assertSafeCleanTarget, withGeneratedProjectAsync, withHarmonyProjectLockAsync } from '@expo-harmony/cli/internal/prebuild';
import { atomicWrite, HarmonyPaths } from '@expo-harmony/config-plugins';

import { HarmonyPatchError } from '../errors';
import { generatePatchAsync } from '../gitPatch';
import { getPatchFilesAsync } from '../patches';

export async function patchProjectAsync(root: string, options: { clean?: boolean } = {}) {
  return withHarmonyProjectLockAsync(root, 'patch-project', async () => {
    const native = await HarmonyPaths.resolveHarmonyPath(root, 'harmony');
    let stat;
    try {
      stat = await fs.lstat(native);
    } catch (cause) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'Cannot read the harmony directory. Run prebuild first.', {
        cause, file: native,
      });
    }

    if (!stat.isDirectory() || !(await fs.readdir(native)).length) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', 'The harmony directory must exist and contain a native project. Run prebuild first.');
    }
    if (options.clean) await assertSafeCleanTarget(root);

    const directory = await HarmonyPaths.resolveHarmonyPath(root, 'cng-patches');
    const previous = await getPatchFilesAsync(directory);
    const result = await withGeneratedProjectAsync(
      root, { clean: true, skipPatches: true }, async (expected, checksum) => ({
        patch: await generatePatchAsync(path.join(expected, 'harmony'), native),
        file: path.join(directory, `harmony+${checksum}.patch`),
      })
    );

    if (result.patch.trim()) await atomicWrite(result.file, result.patch);
    for (const name of previous) {
      const file = await HarmonyPaths.resolveHarmonyPath(directory, name);
      if (!result.patch.trim() || file !== result.file) await fs.rm(file);
    }

    if (options.clean) await fs.rm(native, { recursive: true });

    return result.patch.trim() ? result.file : null;
  });
}
