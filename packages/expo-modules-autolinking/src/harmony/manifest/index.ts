import path from 'node:path';

import type { Manifest } from '../../types';
import { ManifestSchemaVersion, Platform } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { collectOhpmDeps, resolveOhpmSpecifier } from '../ohpm/dependencies';
import { isValidOhpmPackageName } from '../../metadata/schema';
import { isObject } from '../../utilities/values';

const ModuleSources = new Set(['dependency', 'searchPath', 'nativeModulesDir', 'reactNativeProjectConfig']);

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
      || !ModuleSources.has(entry.source)
      || (entry.harmony !== undefined && (
        !isObject(entry.harmony)
        || !Array.isArray(entry.harmony.modules)
        || entry.harmony.modules.some(moduleClass => typeof moduleClass !== 'string' || !moduleClass)
      ))
      || (entry.arkTs !== undefined && (
        !isObject(entry.arkTs)
        || entry.arkTs.harPath !== 'harmony/library.har'
        || !isValidOhpmPackageName(entry.arkTs.ohPackageName)
      ))
      || (entry.harmony?.modules.length > 0 && !isObject(entry.arkTs))
      || !isObject(entry.expo)
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

function ohpmDependenciesFromManifest(
  manifest: Manifest,
  options: { harmonyProjectPath?: string; nodeModulesPath?: string } = {}
): Readonly<Record<string, string>> {
  const validated = validateManifest(manifest);

  return Object.fromEntries(collectOhpmDeps(validated.modules)
    .map(({ descriptor, mapping }) => [
      mapping.ohPackageName,
      resolveOhpmSpecifier(descriptor, mapping, options),
    ]));
}

export {
  ohpmDependenciesFromManifest,
  validateManifest,
};
