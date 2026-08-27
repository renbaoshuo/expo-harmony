import fs from 'node:fs';
import path from 'node:path';

import type { Manifest } from '../../types';
import { ManifestSchemaVersion, Platform } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { collectOhpmDeps, resolveOhpmSpecifier } from '../ohpm/dependencies';
import { isObject } from '../../utilities/values';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function validateManifest(manifest: unknown, options: Record<string, any> = {}): Manifest {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const candidate = isObject(manifest) ? manifest as Record<string, any> : null;

  if (!candidate
    || candidate.schemaVersion !== ManifestSchemaVersion
    || candidate.platform !== Platform
    || !['debug', 'release'].includes(candidate.buildType)
    || !Array.isArray(candidate.modules)
    || !Array.isArray(candidate.managedArtifacts)) {
    throw new HarmonyAutolinkingError('INVALID_MANIFEST', `Harmony autolinking manifest must use schema ${ManifestSchemaVersion}.`, {
      details: options.file ? { file: options.file } : undefined,
      stage: 'manifest',
    });
  }
  for (const [index, entry] of candidate.modules.entries()) {
    if (!isObject(entry)
      || typeof entry.packageName !== 'string'
      || !entry.packageName
      || typeof entry.packageVersion !== 'string'
      || !entry.packageVersion
      || typeof entry.packageRoot !== 'string'
      || !path.isAbsolute(entry.packageRoot)
      || typeof entry.packageLinkPath !== 'string'
      || !path.isAbsolute(entry.packageLinkPath)
      || !isObject(entry.expo)
      || !Array.isArray(entry.expo.abilityLifecycleSubscribers)
      || !Array.isArray(entry.expo.providers)
      || !Array.isArray(entry.expo.reactInstanceLifecycleListeners)
      || !Array.isArray(entry.expo.rootViewComponents)
      || !isObject(entry.rnoh)
      || !Array.isArray(entry.rnoh.harPaths)) {
      throw new HarmonyAutolinkingError(
        'INVALID_MANIFEST',
        `Harmony autolinking manifest module ${index} is invalid.`,
        { details: options.file ? { file: options.file } : undefined, stage: 'manifest' }
      );
    }
  }

  return structuredClone(candidate) as Manifest;
}

async function readManifestAsync(
  file: string,
  options: { allowMissing?: boolean } = {}
): Promise<Manifest | null> {
  let source;

  try {
    source = await fs.promises.readFile(file, 'utf8');
  } catch (cause) {
    if (cause.code === 'ENOENT' && options.allowMissing) return null;
    throw new HarmonyAutolinkingError('INVALID_MANIFEST', `Cannot read Harmony autolinking manifest: ${file}`, {
      cause,
      details: { file },
      stage: 'manifest',
    });
  }

  try {
    return validateManifest(JSON.parse(source), { file });
  } catch (cause) {
    if (cause?.code === 'ERR_EXPO_HARMONY_INVALID_MANIFEST') {
      throw new HarmonyAutolinkingError('INVALID_MANIFEST', cause.message, {
        cause,
        details: cause.details,
        stage: cause.stage || 'manifest',
      });
    }
    throw new HarmonyAutolinkingError('INVALID_MANIFEST', `Cannot parse Harmony autolinking manifest: ${file}`, {
      cause,
      details: { file },
      stage: 'manifest',
    });
  }
}

function ohpmDependenciesFromManifest(manifest: Manifest): Readonly<Record<string, string>> {
  const validated = validateManifest(manifest);

  return Object.fromEntries(collectOhpmDeps(validated.modules, validated.buildType)
    .map(({ descriptor, mapping }) => [mapping.ohPackageName, resolveOhpmSpecifier(descriptor, mapping)]));
}

function localOhpmDependenciesFromManifest(manifest: Manifest, harmony: string): Readonly<Record<string, string>> {
  const validated = validateManifest(manifest);

  if (typeof harmony !== 'string' || !path.isAbsolute(harmony)) {
    throw new HarmonyAutolinkingError('INVALID_MANIFEST', 'Harmony project path must be absolute.', {
      stage: 'manifest',
    });
  }
  return Object.fromEntries(collectOhpmDeps(validated.modules, validated.buildType).map(({
    descriptor,
    mapping,
  }) => {
    if (!descriptor.packageLinkPath.includes(`${path.sep}node_modules${path.sep}`)) {
      throw new HarmonyAutolinkingError(
        'INVALID_MANIFEST',
        `Harmony package link path for ${descriptor.packageName} is not inside node_modules.`,
        { stage: 'manifest' }
      );
    }
    const segments = mapping.harPath.split('/');
    if (path.isAbsolute(mapping.harPath)
      || segments.length === 0
      || segments.some(segment => !segment || segment === '.' || segment === '..')) {
      throw new HarmonyAutolinkingError(
        'INVALID_MANIFEST',
        `Harmony autolinking manifest contains an unsafe HAR path for ${descriptor.packageName}.`,
        { stage: 'manifest' }
      );
    }
    const harPath = path.resolve(descriptor.packageLinkPath, ...segments);
    let specifier = path.relative(harmony, harPath).split(path.sep).join('/');
    if (!specifier.startsWith('.')) specifier = `./${specifier}`;
    return [mapping.ohPackageName, specifier];
  }));
}

export {
  localOhpmDependenciesFromManifest,
  ohpmDependenciesFromManifest,
  readManifestAsync,
  validateManifest,
};
