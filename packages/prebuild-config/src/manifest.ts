/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { createHash } from 'node:crypto';
import { promises as fs, realpathSync } from 'node:fs';
import path from 'node:path';

import { HarmonyPaths, stableHarmonyJson } from '@expo-harmony/config-plugins';
import { normalizeHarmonyConfigPlugins } from '@expo-harmony/config-plugins/internal';
import type {
  HarmonyConfigPluginOwnership,
  NormalizedHarmonyConfig,
} from '@expo-harmony/config-plugins';
import { isManagedBuildProperties, type ManagedBuildProperties } from '@expo-harmony/expo-build-properties/internal';
import { ManifestArtifact } from '@expo-harmony/expo-modules-autolinking';
import JSON5 from 'json5';

import { HarmonyPrebuildError } from './errors';
import {
  createHarmonyBuildDescriptor,
  validateHarmonyBuildDescriptor,
  type HarmonyBuildDescriptor,
} from './buildDescriptor';
import { isManagedModuleConfig, type ManagedModuleConfig } from './moduleConfig';
import { PackageMetadata } from './packageMetadata';

const GeneratorVersion = PackageMetadata.version;
const ManifestSchemaVersion = 2;
const CngManifestPath = '.expo/harmony/cng-manifest.json';
const Sha256Pattern = /^[a-f0-9]{64}$/u;

interface ManagedFile {
  owner: string;
  path: string;
  sha256?: string;
}

interface CngManifest {
  build: HarmonyBuildDescriptor;
  configPlugins: HarmonyConfigPluginOwnership[];
  generatedAt: null;
  generator: {
    package: '@expo-harmony/prebuild-config';
    version: string;
  };
  inputs: {
    autolinkingHash: string;
    configHash: string;
  };
  managedFiles: Array<ManagedFile & { sha256: string }>;
  managedBuildProperties?: ManagedBuildProperties;
  managedIdentity: {
    abilityName: string;
    moduleName: string;
    productName: string;
    targetName: string;
  };
  managedModuleConfig?: ManagedModuleConfig;
  modules: Array<{ packageName: string; packageVersion: string }>;
  schemaVersion: 2;
  signingConfigName: string | null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

interface ValidateCngManifestOptions {
  file?: string;
}

function validateCngManifest(manifest: unknown, options: ValidateCngManifestOptions = {}): CngManifest {
  const file = options.file;

  if (!isRecord(manifest)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest must be an object.',
      { file, operation: 'validate-manifest' }
    );
  }
  if (manifest.generatedAt !== null) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest generatedAt must be the deterministic null sentinel.',
      { file, operation: 'validate-manifest' }
    );
  }
  if (manifest.schemaVersion !== ManifestSchemaVersion) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      `Unsupported Harmony CNG manifest schema: ${manifest.schemaVersion}.`,
      { file, operation: 'validate-manifest' }
    );
  }
  if (!isRecord(manifest.generator)
    || manifest.generator.package !== '@expo-harmony/prebuild-config'
    || !isNonEmptyString(manifest.generator.version)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest has an invalid generator.',
      { file, operation: 'validate-manifest' }
    );
  }

  let build: HarmonyBuildDescriptor;

  try {
    build = validateHarmonyBuildDescriptor(manifest.build);
    manifest.build = build;
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      `Harmony CNG manifest has an invalid build descriptor: ${cause.message}`,
      { cause, file, operation: 'validate-manifest' }
    );
  }

  if (!isRecord(manifest.inputs)
    || typeof manifest.inputs.autolinkingHash !== 'string'
    || typeof manifest.inputs.configHash !== 'string'
    || !Sha256Pattern.test(manifest.inputs.autolinkingHash)
    || !Sha256Pattern.test(manifest.inputs.configHash)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest has invalid input hashes.',
      { file, operation: 'validate-manifest' }
    );
  }
  if (!Array.isArray(manifest.managedFiles)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest managedFiles must be an array.',
      { file, operation: 'validate-manifest' }
    );
  }

  try {
    manifest.configPlugins = normalizeHarmonyConfigPlugins(manifest.configPlugins);
  } catch (cause) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      `Harmony CNG manifest has invalid config-plugin ownership: ${cause.message}`,
      { cause, file, operation: 'validate-manifest' }
    );
  }

  const paths = new Set();

  for (const descriptor of manifest.managedFiles) {
    const relative = descriptor?.path;
    const segments = typeof relative === 'string' ? relative.split('/') : [];

    if (!isRecord(descriptor)
      || !isNonEmptyString(descriptor.owner)
      || !isNonEmptyString(relative)
      || relative.includes('\\')
      || path.posix.isAbsolute(relative)
      || path.win32.isAbsolute(relative)
      || path.posix.normalize(relative) !== relative
      || segments.some(segment => !segment || segment === '.' || segment === '..')
      || typeof descriptor.sha256 !== 'string'
      || !Sha256Pattern.test(descriptor.sha256)) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_MANIFEST_INVALID',
        `Harmony CNG manifest contains an invalid managed file: ${relative}.`,
        { file, operation: 'validate-manifest' }
      );
    }
    if (paths.has(relative)) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_MANIFEST_INVALID',
        `Harmony CNG manifest contains a duplicate managed path: ${relative}.`,
        { file, operation: 'validate-manifest' }
      );
    }

    paths.add(relative);
  }

  if (!Array.isArray(manifest.modules)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest modules must be an array.',
      { file, operation: 'validate-manifest' }
    );
  }

  const names = new Set();

  for (const module of manifest.modules) {
    if (!isRecord(module)
      || !isNonEmptyString(module.packageName)
      || !isNonEmptyString(module.packageVersion)) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_MANIFEST_INVALID',
        'Harmony CNG manifest contains an invalid module descriptor.',
        { file, operation: 'validate-manifest' }
      );
    }
    if (names.has(module.packageName)) {
      throw new HarmonyPrebuildError(
        'ERR_HARMONY_MANIFEST_INVALID',
        `Harmony CNG manifest contains a duplicate module: ${module.packageName}.`,
        { file, operation: 'validate-manifest' }
      );
    }

    names.add(module.packageName);
  }

  if (!isRecord(manifest.managedIdentity)
    || ['abilityName', 'moduleName', 'productName', 'targetName']
      .some(field => !isNonEmptyString(manifest.managedIdentity[field]))) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest has an invalid managed identity.',
      { file, operation: 'validate-manifest' }
    );
  }
  if (build.identity.abilityName !== manifest.managedIdentity.abilityName
    || build.identity.moduleName !== manifest.managedIdentity.moduleName
    || build.identity.productName !== manifest.managedIdentity.productName
    || build.identity.targetName !== manifest.managedIdentity.targetName) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest build identity does not match its managed identity.',
      { file, operation: 'validate-manifest' }
    );
  }
  if (manifest.signingConfigName !== null
    && !isNonEmptyString(manifest.signingConfigName)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest has an invalid signing config name.',
      { file, operation: 'validate-manifest' }
    );
  }
  if (manifest.managedModuleConfig !== undefined && !isManagedModuleConfig(manifest.managedModuleConfig)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest has invalid module configuration ownership.',
      { file, operation: 'validate-manifest' }
    );
  }
  if (manifest.managedBuildProperties !== undefined && !isManagedBuildProperties(manifest.managedBuildProperties)) {
    throw new HarmonyPrebuildError(
      'ERR_HARMONY_MANIFEST_INVALID',
      'Harmony CNG manifest has invalid build properties ownership.',
      { file, operation: 'validate-manifest' }
    );
  }

  return manifest as unknown as CngManifest;
}

function hashSha256(value: string | Uint8Array) {
  return createHash('sha256').update(value).digest('hex');
}

function hashHarmonyConfig(root: string, config: NormalizedHarmonyConfig): string {
  // Dynamic app config can resolve its project-local inputs to absolute paths.
  // Those inputs refer to the same files when evaluated in the check mirror.
  const roots = [root, realpathSync(root)];
  const projectRelative = (file?: string) => {
    if (!file || !path.isAbsolute(file)) return file;
    const base = roots.find(candidate => HarmonyPaths.isInside(candidate, file));
    return base ? HarmonyPaths.toPosixRelative(base, file) : file;
  };

  return hashSha256(stableHarmonyJson({
    ...config,
    icon: projectRelative(config.icon),
    signingConfigFile: projectRelative(config.signingConfigFile),
  }));
}

async function hashFile(file: string) {
  return hashSha256(Uint8Array.from(await fs.readFile(file)));
}

async function createCngManifest(
  root: string,
  config: NormalizedHarmonyConfig,
  managed: readonly ManagedFile[],
  modules: ReadonlyArray<{ packageName: string; packageVersion: string }> = [],
  signing: string | null = null,
  plugins: readonly HarmonyConfigPluginOwnership[] = [],
  ownership: { moduleConfig?: ManagedModuleConfig; buildProperties?: ManagedBuildProperties } = {}
): Promise<CngManifest> {
  const file = path.join(root, 'harmony', HarmonyPaths.HARMONY_PATHS.projectBuildProfile);
  const profile = JSON5.parse(await fs.readFile(file, 'utf8'));
  const product = profile.app?.products?.find(item => item.name === config.productName);
  const build = createHarmonyBuildDescriptor(config, product?.signingConfig ?? null);
  const files = [];

  for (const item of managed) {
    if (item.sha256 !== undefined) {
      files.push({ owner: item.owner, path: item.path, sha256: item.sha256 });
      continue;
    }
    const target = path.join(root, ...item.path.split('/'));

    try {
      files.push({ owner: item.owner, path: item.path, sha256: await hashFile(target) });
    } catch (cause) {
      if (cause.code !== 'ENOENT') {
        throw new HarmonyPrebuildError(
          cause.code || 'ERR_HARMONY_MANIFEST_INVALID',
          cause.message || `Cannot hash managed file ${target}.`,
          { cause, file: target, operation: 'create-manifest' }
        );
      }
    }
  }

  files.sort((left, right) => left.path.localeCompare(right.path, 'en'));

  const autolinking = path.join(root, ManifestArtifact);
  const hash = await hashFile(autolinking).catch((cause) => {
    if (cause.code === 'ENOENT') return hashSha256('');

    throw new HarmonyPrebuildError(
      cause.code || 'ERR_HARMONY_MANIFEST_INVALID',
      cause.message || `Cannot hash autolinking manifest ${autolinking}.`,
      { cause, file: autolinking, operation: 'create-manifest' }
    );
  });

  return validateCngManifest({
    build,
    generatedAt: null,
    configPlugins: normalizeHarmonyConfigPlugins(plugins),
    generator: { package: '@expo-harmony/prebuild-config', version: GeneratorVersion },
    inputs: {
      autolinkingHash: hash,
      configHash: hashHarmonyConfig(root, config),
    },
    managedFiles: files,
    managedIdentity: {
      abilityName: build.identity.abilityName,
      moduleName: build.identity.moduleName,
      productName: build.identity.productName,
      targetName: build.identity.targetName,
    },
    ...(ownership.moduleConfig ? { managedModuleConfig: ownership.moduleConfig } : {}),
    ...(ownership.buildProperties && Object.keys(ownership.buildProperties).length
      ? { managedBuildProperties: ownership.buildProperties }
      : {}),
    modules: modules.map(module => ({ packageName: module.packageName, packageVersion: module.packageVersion })),
    schemaVersion: ManifestSchemaVersion,
    signingConfigName: signing,
  });
}

export {
  CngManifestPath,
  hashHarmonyConfig,
  ManifestSchemaVersion,
  createCngManifest,
  hashFile,
  hashSha256,
  validateCngManifest,
};
export type {
  CngManifest,
};
