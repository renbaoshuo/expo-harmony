import path from 'node:path';

import type { Manifest } from '../../types';
import { ManifestSchemaVersion, Platform } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { collectOhpmDeps, resolveOhpmSpecifier } from '../ohpm/dependencies';
import { isValidOhpmPackageName } from '../../metadata/schema';
import { isObject } from '../../utilities/values';
import { HostMetadataFields } from '../../metadata/host';

const ModuleSources = new Set(['dependency', 'searchPath', 'nativeModulesDir', 'reactNativeProjectConfig']);

function isClassList(value: unknown): value is string[] {
  return Array.isArray(value)
    && value.every(name => typeof name === 'string' && /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name))
    && new Set(value).size === value.length;
}

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
      || !isObject(entry.harmony)
      || !isClassList(entry.harmony.modules)
      || !isClassList(entry.harmony.services)
      || (entry.arkTs !== undefined && (
        !isObject(entry.arkTs)
        || entry.arkTs.harPath !== 'harmony/library.har'
        || !isValidOhpmPackageName(entry.arkTs.ohPackageName)
      ))
      || ((entry.harmony.modules.length > 0 || entry.harmony.services.length > 0) && !isObject(entry.arkTs))
      || !isObject(entry.expo)
      || !isClassList(entry.expo.rootViewComponents)
      || !HostMetadataFields.every(field => isClassList(entry.expo[field] ?? []))
      || (HostMetadataFields.some(field => entry.expo[field]?.length > 0) && !isObject(entry.arkTs))
      || !isObject(entry.rnoh)
      || !Array.isArray(entry.rnoh.harPaths)) {
      throw new HarmonyAutolinkingError(
        'INVALID_MANIFEST',
        `Harmony autolinking manifest module ${index} is invalid.`,
        { details: options.file ? { file: options.file } : undefined, stage: 'manifest' }
      );
    }
  }

  // Schema 4 manifests generated before lifecycle contributions remain readable
  // for stale dependency cleanup. New manifests always contain the full lists.
  const normalized = structuredClone(candidate);

  normalized.modules.forEach((entry) => {
    for (const field of HostMetadataFields) entry.expo[field] ??= [];
  });

  return normalized as Manifest;
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
