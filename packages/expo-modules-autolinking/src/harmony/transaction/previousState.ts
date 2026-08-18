import * as fs from 'node:fs';
import * as path from 'node:path';

import { ExpoArtifacts, ManifestArtifact, ManifestSchemaVersion, RnohArtifacts } from '../../config/constants';
import { isValidOhpmPackageName } from '../../metadata/descriptor';
import { resolveRnohMetadata } from '../rnoh/packageMetadata';
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

function ohpmPackageNamesFromManifest(manifest) {
  if (!Array.isArray(manifest.modules)) throw new TypeError('manifest modules are missing');
  const names = new Set<string>();

  for (const entry of manifest.modules) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)
      || typeof entry.packageName !== 'string' || !entry.packageName
      || !entry.rnoh || typeof entry.rnoh !== 'object' || Array.isArray(entry.rnoh)
      || !Array.isArray(entry.rnoh.harPaths)
      || entry.rnoh.harPaths.some(harPath => typeof harPath !== 'string' || !harPath)) {
      throw new TypeError('manifest contains an invalid module descriptor');
    }
    const configured = entry.rnoh.ohPackageName;
    if (configured !== undefined && typeof configured !== 'string' && !Array.isArray(configured)) {
      throw new TypeError('manifest contains an invalid OH package mapping');
    }
    if (Array.isArray(configured) && configured.some(mapping => (
      !mapping || typeof mapping !== 'object' || Array.isArray(mapping)
      || typeof mapping.harName !== 'string' || !mapping.harName
      || !isValidOhpmPackageName(mapping.packageName)
    ))) {
      throw new TypeError('manifest contains an invalid OH package mapping');
    }

    const rnohMetadata = resolveRnohMetadata(entry);
    for (const mapping of rnohMetadata.harMappings) {
      if (!isValidOhpmPackageName(mapping.ohPackageName)) {
        throw new TypeError('manifest contains an unsafe OH package specifier');
      }
      names.add(mapping.ohPackageName);
    }

    const providerHar = entry.expo?.providerHar;
    if (providerHar !== undefined) {
      if (!providerHar || typeof providerHar !== 'object' || Array.isArray(providerHar)
        || typeof providerHar.harPath !== 'string' || !providerHar.harPath
        || path.posix.extname(providerHar.harPath) !== '.har'
        || !isValidOhpmPackageName(providerHar.ohPackageName)) {
        throw new TypeError('manifest contains an invalid Provider HAR');
      }
      names.add(providerHar.ohPackageName);
    }
  }

  return [...names].sort((left, right) => left.localeCompare(right, 'en'));
}

async function readPreviousAutolinkingStateAsync(projectRoot) {
  const manifestPath = path.join(projectRoot, ManifestArtifact);

  if (!(await pathExistsAsync(manifestPath))) {
    return { artifacts: [], managedOhpmPackageNames: [], warning: null };
  }
  try {
    const stat = await fs.promises.lstat(manifestPath);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new TypeError('manifest is not a regular file');
    const manifest = JSON.parse(await fs.promises.readFile(manifestPath, 'utf8'));

    if (!Number.isInteger(manifest.schemaVersion)
      || manifest.schemaVersion < 1
      || manifest.schemaVersion > ManifestSchemaVersion
      || manifest.platform !== 'harmony'
      || !Array.isArray(manifest.managedArtifacts)) {
      throw new TypeError('manifest schema is unsupported');
    }
    const normalized: Array<string | null> = manifest.managedArtifacts.map(normalizeManagedArtifactPath);
    if (normalized.some(value => value == null)) throw new TypeError('manifest contains an unsafe path');
    const artifacts = normalized.filter((value): value is string => value !== null);

    return {
      artifacts: [...new Set(artifacts)].map(relative => path.join(projectRoot, ...relative.split('/'))),
      managedOhpmPackageNames: ohpmPackageNamesFromManifest(manifest),
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
  ohpmPackageNamesFromManifest,
  normalizeManagedArtifactPath,
  readPreviousAutolinkingStateAsync,
};
