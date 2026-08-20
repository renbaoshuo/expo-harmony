import fs from 'node:fs';
import path from 'node:path';

import { HarmonyCliError } from '../errors';

async function assertSafeCleanTarget(projectRoot) {
  const root = await fs.promises.realpath(projectRoot);
  const target = path.join(root, 'harmony');
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

  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    throw new HarmonyCliError('ERR_HARMONY_CLEAN_TARGET', `Refusing to clean a non-directory or symlink: ${target}. Please delete it manually.`, {
      operation: 'clean',
    });
  }

  const real = await fs.promises.realpath(target);

  if (real !== target || path.dirname(real) !== root || real === root || real === path.parse(real).root) {
    throw new HarmonyCliError('ERR_HARMONY_CLEAN_TARGET', `Unsafe Harmony clean target: ${real}. Please delete it manually.`, { operation: 'clean' });
  }

  const marker = path.join(real, '.expo-harmony-template');

  if (!fs.existsSync(marker)) {
    throw new HarmonyCliError('ERR_HARMONY_CLEAN_TARGET', `Refusing to clean ${real} because .expo-harmony-template is missing. Please delete it manually.`, { operation: 'clean' });
  }

  return real;
}

export { assertSafeCleanTarget };
