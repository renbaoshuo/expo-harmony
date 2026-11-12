/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as fs from 'node:fs';
import * as path from 'node:path';

import { ExpoArtifacts, ManifestArtifact, managedArtifactsForHarmonyRoot } from '../../config/constants';
import { inlineModuleArtifacts } from '../inlineModules';
import { validateManifest } from '../manifest';
import { collectOhpmDeps } from '../ohpm/dependencies';
import { isPathInside, normalizeSlashes } from '../../utilities/values';

async function readPreviousAutolinkingStateAsync(projectRoot: string, harmonyProjectPath: string) {
  const file = path.join(projectRoot, ManifestArtifact);
  let source: string | undefined;

  try {
    const stat = await fs.promises.lstat(file).catch((error) => {
      if (error.code === 'ENOENT') return null;
      throw error;
    });
    if (!stat) return { source, artifacts: [], managedOhpmPackageNames: [], warning: null };
    if (!stat.isFile() || stat.isSymbolicLink()) throw new TypeError('manifest is not a regular file');

    source = await fs.promises.readFile(file, 'utf8');
    const manifest = validateManifest(JSON.parse(source), { file });
    const harmony = await fs.promises.realpath(harmonyProjectPath);
    if (!isPathInside(projectRoot, harmony)) throw new TypeError('Harmony project is outside the project root');

    const root = normalizeSlashes(path.relative(projectRoot, harmony));
    const base = managedArtifactsForHarmonyRoot(root);
    const managed = new Set([
      ...base,
      ...manifest.modules.flatMap(inlineModuleArtifacts).map(file => path.posix.join(root, file)),
    ]);
    const workerFactory = path.posix.join(root, ExpoArtifacts.workerFactory);
    // Older schema-4 manifests managed the combined UI/worker factory.
    if (base.some(artifact => artifact !== workerFactory && !manifest.managedArtifacts.includes(artifact))
      || manifest.managedArtifacts.some(artifact => !managed.has(artifact))) {
      throw new TypeError('manifest contains a path outside the current Harmony managed artifacts');
    }

    const names = collectOhpmDeps(manifest.modules).map(({ mapping }) => mapping.ohPackageName);

    return {
      source,
      artifacts: [...new Set(manifest.managedArtifacts)].map(relative => path.join(projectRoot, ...relative.split('/'))),
      managedOhpmPackageNames: [...new Set(names)].sort((left, right) => left.localeCompare(right, 'en')),
      warning: null,
    };
  } catch (_cause) {
    return {
      source,
      artifacts: [],
      managedOhpmPackageNames: [],
      warning: {
        severity: 'warning',
        code: 'ERR_EXPO_HARMONY_STALE_MANIFEST_IGNORED',
        message: 'The previous Harmony autolinking manifest is invalid; stale artifact cleanup was skipped.',
        stage: 'publish',
      },
    };
  }
}

export {
  readPreviousAutolinkingStateAsync,
};
