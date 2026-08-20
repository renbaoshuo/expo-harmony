import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { resolveEntryPoint } from '@expo/config/paths';

import { HarmonyCliError } from './errors';

function isFile(file) {
  try {
    return fs.statSync(file).isFile();
  } catch {
    return false;
  }
}

function resolveHarmonyEntryPoint(projectRoot) {
  const packageJsonPath = path.join(projectRoot, 'package.json');
  try {
    const pkg = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    let entry = resolveEntryPoint(projectRoot, { pkg, platform: 'harmony' });

    if (!isFile(entry) && typeof pkg.main === 'string' && pkg.main) {
      const logicalPackageRoot = entry;
      const resolved = createRequire(packageJsonPath).resolve(pkg.main);

      try {
        const relative = path.relative(fs.realpathSync(logicalPackageRoot), fs.realpathSync(resolved));
        entry = relative !== '..'
          && !relative.startsWith(`..${path.sep}`)
          && !path.isAbsolute(relative)
          ? path.join(logicalPackageRoot, relative)
          : resolved;
      } catch {
        entry = resolved;
      }
    }

    if (!isFile(entry)) throw new Error('Resolved entry is not a file.');

    return entry;
  } catch (cause) {
    throw new HarmonyCliError('ERR_HARMONY_EXPORT_ENTRY', 'Cannot resolve the Expo entry point for the Harmony bundle.', { cause, operation: 'resolve-entry-point' });
  }
}

export { resolveHarmonyEntryPoint };
