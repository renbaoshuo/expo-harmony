import * as fs from 'node:fs';
import * as path from 'node:path';

import { ExpoArtifacts, ManifestArtifact, RnohArtifacts } from '../../config/constants';
import { ohpmDependenciesFromManifest, validateManifest } from '../manifest';
import { pathExistsAsync } from '../../utilities/values';

const ManagedSuffixes = [
  ...Object.values(RnohArtifacts),
  ...Object.values(ExpoArtifacts),
];

function isManagedArtifactPath(relativePath) {
  if (relativePath === ManifestArtifact) return true;
  return ManagedSuffixes.some(suffix => relativePath === suffix || relativePath.endsWith(`/${suffix}`));
}

function normalizeManagedArtifactPath(value) {
  if (typeof value !== 'string' || !value || value.includes('\\') || path.posix.isAbsolute(value)) {
    return null;
  }

  const normalized = path.posix.normalize(value);
  if (normalized !== value || normalized === '..' || normalized.startsWith('../')) return null;
  return isManagedArtifactPath(normalized) ? normalized : null;
}

function staleManifestWarning(message) {
  return {
    severity: 'warning',
    code: 'ERR_EXPO_HARMONY_STALE_MANIFEST_IGNORED',
    message,
    stage: 'publish',
  };
}

async function readPreviousAutolinkingStateAsync(projectRoot) {
  const manifestPath = path.join(projectRoot, ManifestArtifact);

  if (!(await pathExistsAsync(manifestPath))) {
    return { artifacts: [], managedOhpmPackageNames: [], warning: null };
  }
  try {
    const stat = await fs.promises.lstat(manifestPath);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new TypeError('manifest is not a regular file');
    const manifest = validateManifest(
      JSON.parse(await fs.promises.readFile(manifestPath, 'utf8')),
      { file: manifestPath }
    );
    const normalized: Array<string | null> = manifest.managedArtifacts.map(normalizeManagedArtifactPath);
    if (normalized.some(value => value == null)) throw new TypeError('manifest contains an unsafe path');
    const artifacts = normalized.filter((value): value is string => value !== null);

    return {
      artifacts: [...new Set(artifacts)].map(relative => path.join(projectRoot, ...relative.split('/'))),
      managedOhpmPackageNames: Object.keys(ohpmDependenciesFromManifest(manifest))
        .sort((left, right) => left.localeCompare(right, 'en')),
      warning: null,
    };
  } catch (_cause) {
    return {
      artifacts: [],
      managedOhpmPackageNames: [],
      warning: staleManifestWarning('The previous Harmony autolinking manifest is invalid; stale artifact cleanup was skipped.'),
    };
  }
}

export {
  isManagedArtifactPath,
  normalizeManagedArtifactPath,
  readPreviousAutolinkingStateAsync,
};
