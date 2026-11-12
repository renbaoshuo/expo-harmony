/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs/promises';
import path from 'node:path';

import { assertSafeCleanTarget, withGeneratedProjectAsync, withHarmonyProjectLockAsync } from '@expo-harmony/cli/internal/prebuild';
import { atomicWrite, HarmonyPaths } from '@expo-harmony/config-plugins';

import { HarmonyPatchError } from '../errors';
import { generatePatchAsync } from '../gitPatch';
import { getPatchFilesAsync } from '../patches';

export async function patchProjectAsync(projectRoot: string, options: { clean?: boolean } = {}) {
  return withHarmonyProjectLockAsync(projectRoot, 'patch-project', async (root) => {
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
    const outputRoot = await fs.realpath(directory).catch((cause) => {
      if (cause.code !== 'ENOENT') throw cause;
      return directory;
    });
    if (HarmonyPaths.isInside(native, outputRoot)) {
      throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch output directory must be outside the Harmony native project: ${directory}.`);
    }

    const previous = await getPatchFilesAsync(directory);
    const result = await withGeneratedProjectAsync(
      root, { clean: true, skipPatches: true }, async (expected, checksum) => ({
        patch: await generatePatchAsync(path.join(expected, 'harmony'), native),
        file: path.join(directory, `harmony+${checksum}.patch`),
      })
    );

    if (result.patch.length) {
      const stat = await fs.lstat(result.file).catch((cause) => {
        if (cause.code !== 'ENOENT') throw cause;
      });
      if (stat && !stat.isFile()) {
        throw new HarmonyPatchError('ERR_HARMONY_PATCH_FAILED', `Patch output must be a regular file: ${result.file}.`);
      }

      await atomicWrite(result.file, result.patch);
    }
    for (const name of previous) {
      const file = path.join(directory, name);
      if (!result.patch.length || file !== result.file) await fs.rm(file, { force: true });
    }

    if (options.clean) await fs.rm(native, { recursive: true });

    return result.patch.length ? result.file : null;
  });
}
