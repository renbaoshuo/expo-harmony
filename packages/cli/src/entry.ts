/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { HarmonyCliError } from './errors';
import { requireFromExpo } from './expo';

function isFile(file) {
  try {
    return fs.statSync(file).isFile();
  } catch {
    return false;
  }
}

function resolveHarmonyEntryPoint(projectRoot) {
  const manifest = path.join(projectRoot, 'package.json');
  try {
    const pkg = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    const { resolveEntryPoint } = requireFromExpo(projectRoot)('@expo/config/paths');
    let entry = resolveEntryPoint(projectRoot, { pkg, platform: 'harmony' });

    if (!isFile(entry) && typeof pkg.main === 'string' && pkg.main) {
      const directory = entry;
      const resolved = createRequire(manifest).resolve(pkg.main);

      try {
        const relative = path.relative(fs.realpathSync(directory), fs.realpathSync(resolved));
        entry = relative !== '..'
          && !relative.startsWith(`..${path.sep}`)
          && !path.isAbsolute(relative)
          ? path.join(directory, relative)
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
