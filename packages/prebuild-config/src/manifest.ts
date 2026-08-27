import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

import { normalizeHarmonyConfigPlugins, stableHarmonyJson } from '@expo-harmony/config-plugins';
import type { HarmonyConfigPluginOwnership } from '@expo-harmony/config-plugins';

import { HarmonyPrebuildError } from './errors';
import {
  createHarmonyBuildDescriptor,
  validateHarmonyBuildDescriptor,
  type HarmonyBuildDescriptor,
} from './buildDescriptor';
import type { NormalizedHarmonyConfig } from './normalizeHarmonyConfig';
import { PackageMetadata } from './packageMetadata';

const GeneratorVersion = PackageMetadata.version;
const ManifestSchemaVersion = 2;
const Sha256Pattern = /^[a-f0-9]{64}$/u;

interface ManagedFile {
  owner: string;
  path: string;
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
  managedIdentity: {
    abilityName: string;
    moduleName: string;
    productName: string;
    targetName: string;
  };
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
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest must be an object.', { file, operation: 'validate-manifest' });
  }
  if (manifest.generatedAt !== null) {
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest generatedAt must be the deterministic null sentinel.', { file, operation: 'validate-manifest' });
  }
  if (manifest.schemaVersion !== ManifestSchemaVersion) {
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', `Unsupported Harmony CNG manifest schema: ${manifest.schemaVersion}.`, { file, operation: 'validate-manifest' });
  }
  if (!isRecord(manifest.generator)
    || manifest.generator.package !== '@expo-harmony/prebuild-config'
    || !isNonEmptyString(manifest.generator.version)) {
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest has an invalid generator.', { file, operation: 'validate-manifest' });
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
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest has invalid input hashes.', { file, operation: 'validate-manifest' });
  }
  if (!Array.isArray(manifest.managedFiles)) {
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest managedFiles must be an array.', { file, operation: 'validate-manifest' });
  }
  try {
    manifest.configPlugins = normalizeHarmonyConfigPlugins(manifest.configPlugins);
  } catch (cause) {
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', `Harmony CNG manifest has invalid config-plugin ownership: ${cause.message}`, { cause, file, operation: 'validate-manifest' }
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
      throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', `Harmony CNG manifest contains an invalid managed file: ${relative}.`, { file, operation: 'validate-manifest' });
    }
    if (paths.has(relative)) {
      throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', `Harmony CNG manifest contains a duplicate managed path: ${relative}.`, { file, operation: 'validate-manifest' });
    }
    paths.add(relative);
  }
  if (!Array.isArray(manifest.modules)) {
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest modules must be an array.', { file, operation: 'validate-manifest' });
  }

  const packages = new Set();
  for (const module of manifest.modules) {
    if (!isRecord(module)
      || !isNonEmptyString(module.packageName)
      || !isNonEmptyString(module.packageVersion)) {
      throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest contains an invalid module descriptor.', { file, operation: 'validate-manifest' });
    }
    if (packages.has(module.packageName)) {
      throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', `Harmony CNG manifest contains a duplicate module: ${module.packageName}.`, { file, operation: 'validate-manifest' });
    }
    packages.add(module.packageName);
  }
  if (!isRecord(manifest.managedIdentity)
    || ['abilityName', 'moduleName', 'productName', 'targetName']
      .some(field => !isNonEmptyString(manifest.managedIdentity[field]))) {
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest has an invalid managed identity.', { file, operation: 'validate-manifest' });
  }
  if (build.identity.abilityName !== manifest.managedIdentity.abilityName
    || build.identity.moduleName !== manifest.managedIdentity.moduleName
    || build.identity.productName !== manifest.managedIdentity.productName
    || build.identity.targetName !== manifest.managedIdentity.targetName) {
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest build identity does not match its managed identity.', { file, operation: 'validate-manifest' });
  }
  if (manifest.signingConfigName !== null
    && !isNonEmptyString(manifest.signingConfigName)) {
    throw new HarmonyPrebuildError('ERR_HARMONY_MANIFEST_INVALID', 'Harmony CNG manifest has an invalid signing config name.', { file, operation: 'validate-manifest' });
  }

  return manifest as unknown as CngManifest;
}

function hashSha256(value: string | Uint8Array) {
  return createHash('sha256').update(value).digest('hex');
}

async function hashFile(file: string) {
  return hashSha256(Uint8Array.from(await fs.readFile(file)));
}

async function createCngManifest(
  projectRoot: string,
  normalized: NormalizedHarmonyConfig,
  managedFiles: readonly ManagedFile[],
  modules: ReadonlyArray<{ packageName: string; packageVersion: string }> = [],
  signingConfigName: string | null = null,
  configPlugins: readonly HarmonyConfigPluginOwnership[] = []
): Promise<CngManifest> {
  const build = createHarmonyBuildDescriptor(normalized, signingConfigName);
  const files = [];

  for (const item of managedFiles) {
    const target = path.join(projectRoot, ...item.path.split('/'));
    try {
      files.push({ owner: item.owner, path: item.path, sha256: await hashFile(target) });
    } catch (error) {
      if (error.code !== 'ENOENT') return Promise.reject(error);
    }
  }

  files.sort((left, right) => left.path.localeCompare(right.path, 'en'));
  const autolinkingFile = path.join(projectRoot, '.expo/harmony/autolinking.json');
  const autolinkingHash = await hashFile(autolinkingFile)
    .catch(error => error.code === 'ENOENT' ? hashSha256('') : Promise.reject(error));

  return validateCngManifest({
    build,
    generatedAt: null,
    configPlugins: normalizeHarmonyConfigPlugins(configPlugins),
    generator: { package: '@expo-harmony/prebuild-config', version: GeneratorVersion },
    inputs: {
      autolinkingHash,
      configHash: hashSha256(stableHarmonyJson(normalized)),
    },
    managedFiles: files,
    managedIdentity: {
      abilityName: build.identity.abilityName,
      moduleName: build.identity.moduleName,
      productName: build.identity.productName,
      targetName: build.identity.targetName,
    },
    modules: modules.map(module => ({ packageName: module.packageName, packageVersion: module.packageVersion })),
    schemaVersion: ManifestSchemaVersion,
    signingConfigName,
  });
}

export {
  ManifestSchemaVersion,
  createCngManifest,
  hashFile,
  hashSha256,
  validateCngManifest,
};
export type {
  CngManifest,
};
