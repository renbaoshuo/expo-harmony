import fs from 'node:fs';
import path from 'node:path';

import { HarmonyPlatformDirectory } from '@expo-harmony/prebuild-config/build-descriptor';

import { HarmonyCliError } from '../errors';
import { isInside } from '../path';
import { resolveHarmonyBuildPlanIfPresentAsync } from '../tools';

async function assertSafeCleanTarget(projectRoot) {
  const root = await fs.promises.realpath(projectRoot);
  const plan = await resolveHarmonyBuildPlanIfPresentAsync(root);
  const target = plan?.harmonyRoot ?? path.join(root, HarmonyPlatformDirectory);
  let stat;

  try {
    stat = await fs.promises.lstat(target);
  } catch (error) {
    if (error.code === 'ENOENT') return target;
    throw new HarmonyCliError(
      error.code || 'ERR_HARMONY_CLEAN_TARGET',
      error.message || `Cannot inspect the Harmony clean target: ${target}. Please delete it manually.`,
      { cause: error, exitCode: error.exitCode, operation: error.operation }
    );
  }

  if (!plan) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CLEAN_TARGET',
      `Refusing to clean ${target} because its CNG manifest is missing. Please delete it manually or run prebuild without --clean.`,
      { operation: 'clean' }
    );
  }

  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    throw new HarmonyCliError('ERR_HARMONY_CLEAN_TARGET', `Refusing to clean a non-directory or symlink: ${target}. Please delete it manually.`, {
      operation: 'clean',
    });
  }

  const real = await fs.promises.realpath(target);

  if (real !== target || !isInside(root, real) || real === root || real === path.parse(real).root) {
    throw new HarmonyCliError('ERR_HARMONY_CLEAN_TARGET', `Unsafe Harmony clean target: ${real}. Please delete it manually.`, { operation: 'clean' });
  }

  const marker = plan.projectFiles.templateMarker;
  let markerStat;

  try {
    markerStat = await fs.promises.lstat(marker);
  } catch (cause) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CLEAN_TARGET',
      `Refusing to clean ${real} because its template marker cannot be inspected. Please delete it manually.`,
      { cause, operation: 'clean' }
    );
  }

  if (!isInside(real, marker) || !markerStat.isFile() || markerStat.isSymbolicLink()) {
    throw new HarmonyCliError('ERR_HARMONY_CLEAN_TARGET', `Refusing to clean ${real} because its template marker is unsafe. Please delete it manually.`, { operation: 'clean' });
  }

  return real;
}

export { assertSafeCleanTarget };
