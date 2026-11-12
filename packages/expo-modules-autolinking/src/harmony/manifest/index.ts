/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import path from 'node:path';

import type { Manifest } from '../../types';
import { ArkTsLibraryHarPath, ManifestSchemaVersion, Platform } from '../../config/constants';
import { HarmonyAutolinkingError } from '../../errors';
import { collectOhpmDeps, resolveHarPath, resolveOhpmSpecifier } from '../ohpm/dependencies';
import { isValidOhpmPackageName } from '../../metadata/schema';
import { isArkTsIdentifier, isObject } from '../../utilities/values';
import { HostMetadataFields } from '../../metadata/host';

const ModuleSources = new Set(['dependency', 'searchPath', 'nativeModulesDir', 'reactNativeProjectConfig', 'inlineModules']);

function isProjectRelativePath(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && !value.includes('\\') && !value.includes('\0')
    && !path.posix.isAbsolute(value) && !path.win32.isAbsolute(value)
    && path.posix.normalize(value) === value && value !== '..' && !value.startsWith('../');
}

function isInlineDescriptor(value: unknown, modules: readonly string[]): boolean {
  if (!isObject(value)) return false;

  const descriptor = value as Record<string, unknown>;
  if (!Array.isArray(descriptor.watchedDirectories) || !descriptor.watchedDirectories.every(isProjectRelativePath)
    || !Array.isArray(descriptor.files) || descriptor.files.length === 0) return false;
  const files = descriptor.files as Record<string, unknown>[];
  if (!files.every(file => isObject(file) && isProjectRelativePath(file.path)
    && /\.(ets|ts|js|json)$/u.test(file.path)
    && Array.isArray(file.modules) && (file.modules.length === 0 || file.path.endsWith('.ets'))
    && file.modules.every(module => isObject(module) && isArkTsIdentifier(module.name) && typeof module.default === 'boolean')
    && file.modules.filter(module => module.default).length <= 1)
    || new Set(files.map(file => file.path)).size !== files.length) return false;

  const names = files.flatMap(file => (file.modules as { name: string }[]).map(module => module.name));

  return names.length === modules.length && new Set(names).size === names.length
    && names.every(name => modules.includes(name));
}

function isClassList(value: unknown): value is string[] {
  return Array.isArray(value)
    && value.every(isArkTsIdentifier)
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
        || entry.arkTs.harPath !== ArkTsLibraryHarPath
        || (entry.arkTs.builtHarPath !== undefined && (typeof entry.arkTs.builtHarPath !== 'string' || !path.isAbsolute(entry.arkTs.builtHarPath)))
        || !isValidOhpmPackageName(entry.arkTs.ohPackageName)
      ))
      || !isObject(entry.rnoh)
      || !Array.isArray(entry.rnoh.harPaths)
      || (entry.rnoh.etsPackageScope !== undefined && !['shared', 'ui', 'host'].includes(entry.rnoh.etsPackageScope))
      || (entry.source === 'inlineModules'
        ? (!isInlineDescriptor(entry.inlineModules, entry.harmony.modules)
          || entry.arkTs !== undefined || entry.harmony.services.length > 0 || entry.rnoh.harPaths.length > 0)
        : (entry.inlineModules !== undefined
          || ((entry.harmony.modules.length > 0 || entry.harmony.services.length > 0) && !isObject(entry.arkTs))))
      || !isObject(entry.expo)
      || !isClassList(entry.expo.rootViewComponents)
      || !HostMetadataFields.every(field => isClassList(entry.expo[field] ?? []))
      || (HostMetadataFields.some(field => entry.expo[field]?.length > 0) && !isObject(entry.arkTs))) {
      throw new HarmonyAutolinkingError(
        'INVALID_MANIFEST',
        `Harmony autolinking manifest module ${index} is invalid.`,
        { details: options.file ? { file: options.file } : undefined, stage: 'manifest' }
      );
    }
  }

  // Older schema-4 manifests need lifecycle defaults for stale cleanup.
  const normalized = structuredClone(candidate);

  normalized.modules.forEach((entry) => {
    for (const field of HostMetadataFields) entry.expo[field] ??= [];
  });

  return normalized as Manifest;
}

function ohpmDependenciesFromManifest(manifest: Manifest): Readonly<Record<string, string>> {
  const validated = validateManifest(manifest);

  return Object.fromEntries(collectOhpmDeps(validated.modules)
    .map(({ descriptor, mapping }) => [
      mapping.ohPackageName,
      resolveOhpmSpecifier(descriptor, mapping),
    ]));
}

function localOhpmDependenciesFromManifest(manifest: Manifest): Readonly<Record<string, string>> {
  return Object.fromEntries(collectOhpmDeps(validateManifest(manifest).modules)
    .map(({ descriptor, mapping }) => [mapping.ohPackageName, `file:${resolveHarPath(descriptor, mapping.harPath)}`]));
}

export {
  localOhpmDependenciesFromManifest,
  ohpmDependenciesFromManifest,
  validateManifest,
};
