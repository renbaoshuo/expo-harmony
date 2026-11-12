/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export interface HarmonyNativeModule {
  packageName: string;
  packageVersion: string;
  modules: string[];
  services: string[];
  registrations: string[];
  artifacts: string[];
}

export interface HarmonyRuntimeContract {
  schemaVersion: 1 | 2;
  platform: 'harmony';
  runtimeVersion: string;
  development: boolean;
  expo: string;
  expoModulesCore: string;
  rnoh: string;
  react: string;
  hermes: string;
  engine: 'hermes-v1';
  bundleFormat: 'js-source';
  renderer: 'rnoh';
  modules: HarmonyNativeModule[];
  config: {
    nativeCompiler: string;
    targetApiVersion?: number | string;
    compatibleApiVersion: number | string;
    nativeLibFilterHash?: string;
    permissions: string[];
    querySchemes: string[];
    backgroundModes: string[];
    abiFilters: string[];
  };
}

export interface HarmonyCompatibilityIssue {
  code: string;
  field: string;
  message: string;
}

export class HarmonyCompatibilityError extends Error {
  readonly code = 'ERR_HARMONY_INCOMPATIBLE';

  constructor(readonly issues: HarmonyCompatibilityIssue[]) {
    super(issues.map(issue => `[${issue.code}] ${issue.message}`).join('\n'));

    this.name = 'HarmonyCompatibilityError';
  }
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0;
}

function strings(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(nonEmptyString) && new Set(value).size === value.length;
}

const Versions = ['runtimeVersion', 'expo', 'expoModulesCore', 'rnoh', 'react', 'hermes'] as const;
const Settings = ['permissions', 'querySchemes', 'backgroundModes', 'abiFilters'] as const;

function apiVersion(value: unknown, schema: unknown): boolean {
  return (typeof value === 'number' && Number.isSafeInteger(value) && value > 0)
    || (schema === 2 && typeof value === 'string' && /^\d+\.\d+\.\d+$/.test(value));
}

export function harmonyRuntimeSchemaVersion(config: HarmonyRuntimeContract['config']): 1 | 2 {
  return typeof config.targetApiVersion === 'string' || typeof config.compatibleApiVersion === 'string'
    || config.nativeLibFilterHash !== undefined
    ? 2
    : 1;
}

export function validateHarmonyRuntime(value: unknown): HarmonyCompatibilityIssue[] {
  if (!record(value)) return [{ code: 'INVALID_CONTRACT', field: '', message: 'Runtime contract must be an object.' }];

  const issues: HarmonyCompatibilityIssue[] = [];
  if (value.schemaVersion !== 1 && value.schemaVersion !== 2) {
    issues.push({ code: 'INVALID_CONTRACT', field: 'schemaVersion', message: 'schemaVersion must be 1 or 2.' });
  }

  for (const [field, expected] of Object.entries({ platform: 'harmony', engine: 'hermes-v1', bundleFormat: 'js-source', renderer: 'rnoh' })) {
    if (value[field] !== expected) {
      issues.push({ code: field === 'platform' ? 'PLATFORM_MISMATCH' : 'INVALID_CONTRACT', field, message: `${field} must be ${expected}.` });
    }
  }

  if (typeof value.development !== 'boolean') {
    issues.push({ code: 'INVALID_CONTRACT', field: 'development', message: 'development must describe native development support.' });
  }

  for (const field of Versions) {
    if (!nonEmptyString(value[field])) {
      issues.push({ code: 'INVALID_CONTRACT', field, message: `${field} must be an explicit version.` });
    }
  }

  if (!Array.isArray(value.modules)) {
    issues.push({ code: 'INVALID_CONTRACT', field: 'modules', message: 'Native modules must be an array.' });
  } else {
    const names = new Set<string>();
    for (const module of value.modules) {
      if (!record(module) || !nonEmptyString(module.packageName) || !nonEmptyString(module.packageVersion)
        || !strings(module.modules) || !strings(module.services) || !strings(module.registrations)
        || !strings(module.artifacts) || module.artifacts.some(hash => !/^[a-f0-9]{64}$/.test(hash))
        || names.has(module.packageName)) {
        issues.push({ code: 'INVALID_CONTRACT', field: 'modules', message: 'Invalid or duplicate native module contract.' });
      } else {
        names.add(module.packageName);
      }
    }
  }

  const config = value.config;
  const target = record(config)
    && (config.targetApiVersion === undefined || apiVersion(config.targetApiVersion, value.schemaVersion));
  const compatible = record(config) ? apiVersion(config.compatibleApiVersion, value.schemaVersion) : undefined;

  if (!record(config) || !nonEmptyString(config.nativeCompiler) || !Settings.every(field => strings(config[field]))
    || !target || !compatible
    || (config.nativeLibFilterHash !== undefined && (value.schemaVersion !== 2
      || typeof config.nativeLibFilterHash !== 'string' || !/^[a-f0-9]{64}$/.test(config.nativeLibFilterHash)))) {
    issues.push({ code: 'INVALID_CONTRACT', field: 'config', message: 'Invalid native build configuration.' });
  }

  return issues;
}

export function checkHarmonyCompatibility(client: unknown, requirements: unknown): HarmonyCompatibilityIssue[] {
  const issues = [
    ...validateHarmonyRuntime(client).map(issue => ({ ...issue, field: `client.${issue.field}` })),
    ...validateHarmonyRuntime(requirements).map(issue => ({ ...issue, field: `requirements.${issue.field}` })),
  ];
  if (issues.length > 0) return issues;

  const available = client as HarmonyRuntimeContract;
  const required = requirements as HarmonyRuntimeContract;

  for (const field of Versions) {
    if (available[field] !== required[field]) {
      issues.push({ code: 'RUNTIME_MISMATCH', field, message: `${field}: project requires ${required[field]}, client provides ${available[field]}. Rebuild or select a matching client.` });
    }
  }

  if (required.development && !available.development) {
    issues.push({ code: 'CONFIG_MISMATCH', field: 'development', message: 'This client was built without native development support. Use a debug client for development manifests.' });
  }

  for (const module of required.modules) {
    const found = available.modules.find(item => item.packageName === module.packageName);
    if (!found) {
      issues.push({ code: 'MISSING_NATIVE_MODULE', field: module.packageName, message: `Client is missing native package ${module.packageName}. Rebuild the client with this package.` });
      continue;
    }

    if (found.packageVersion !== module.packageVersion
      || ['modules', 'services', 'registrations', 'artifacts'].some((field) => {
        const left = found[field] as string[];
        const right = module[field] as string[];

        return left.length !== right.length || right.some(item => !left.includes(item));
      })) {
      issues.push({ code: 'NATIVE_MODULE_MISMATCH', field: module.packageName, message: `Native contract differs for ${module.packageName}. Rebuild or select a matching client.` });
    }
  }

  for (const field of ['nativeCompiler', 'targetApiVersion', 'compatibleApiVersion', 'nativeLibFilterHash'] as const) {
    // Hvigor chooses the target SDK when neither targetSdkVersion nor compileSdkVersion is explicit.
    if (field === 'targetApiVersion' && (available.config[field] === undefined || required.config[field] === undefined)) continue;
    if (available.config[field] !== required.config[field]) {
      issues.push({ code: 'CONFIG_MISMATCH', field, message: `${field}: project requires ${required.config[field]}, client provides ${available.config[field]}.` });
    }
  }

  for (const field of Settings) {
    for (const item of required.config[field]) {
      if (!available.config[field].includes(item)) {
        issues.push({ code: 'CONFIG_MISMATCH', field, message: `Client build is missing ${field}: ${item}. Rebuild the client with this configuration.` });
      }
    }
  }

  return issues;
}

export function assertHarmonyCompatibility(
  client: unknown,
  requirements: unknown
): asserts requirements is HarmonyRuntimeContract {
  const issues = checkHarmonyCompatibility(client, requirements);
  if (issues.length > 0) throw new HarmonyCompatibilityError(issues);
}

export interface HarmonyDevelopmentManifest {
  id: string;
  createdAt: string;
  metadata: Record<string, string>;
  assets: unknown[];
  runtimeVersion: string;
  launchAsset: { key: 'bundle'; contentType: 'application/javascript'; url: string };
  extra: {
    expoClient: Record<string, unknown>;
    expoGo: Record<string, unknown>;
    harmony: { projectId: string; manifestUrl: string; requirements: HarmonyRuntimeContract };
  };
}

function parseDevelopmentURL(value: string): URL | undefined {
  const authority = /^https?:\/\/([^/?#\\]+)/i.exec(value)?.[1];
  if (!authority || authority.includes('@') || value.includes('#') || value.includes('\\')) return undefined;

  try {
    decodeURIComponent(value);
    const url = new URL(value);
    if (url.hostname && !url.username && !url.password) return url;
  } catch {
    return undefined;
  }
}

function hasQueryParameter(url: URL, name: string, value: string): boolean {
  const values = url.searchParams.getAll(name);
  return values.length === 1 && values[0] === value;
}

export function assertHarmonyDevelopmentManifest(
  client: unknown,
  value: unknown
): asserts value is HarmonyDevelopmentManifest {
  if (!record(value) || typeof value.id !== 'string'
    || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value.id)
    || typeof value.createdAt !== 'string' || !Number.isFinite(Date.parse(value.createdAt))
    || !record(value.metadata) || !Object.values(value.metadata).every(item => typeof item === 'string')
    || !Array.isArray(value.assets) || value.assets.length !== 0 || !record(value.launchAsset)
    || value.launchAsset.key !== 'bundle' || value.launchAsset.contentType !== 'application/javascript'
    || typeof value.launchAsset.url !== 'string' || !record(value.extra) || !record(value.extra.expoClient)
    || !record(value.extra.expoGo) || !record(value.extra.harmony)
    || typeof value.extra.harmony.projectId !== 'string' || !value.extra.harmony.projectId
    || typeof value.extra.harmony.manifestUrl !== 'string') {
    throw new HarmonyCompatibilityError(
      [{ code: 'INVALID_MANIFEST', field: '', message: 'Expected an Expo development JS source manifest with Harmony requirements.' }]
    );
  }

  const harmony = value.extra.harmony;
  assertHarmonyCompatibility(client, harmony.requirements);

  const manifest = parseDevelopmentURL(harmony.manifestUrl as string);
  const bundle = parseDevelopmentURL(value.launchAsset.url);
  if (value.runtimeVersion !== harmony.requirements.runtimeVersion || !manifest
    || !['/', '/manifest', '/index.exp'].includes(manifest.pathname)
    || !hasQueryParameter(manifest, 'platform', 'harmony')
    || !bundle || bundle.origin !== manifest.origin || !bundle.pathname.endsWith('.bundle')
    || !hasQueryParameter(bundle, 'platform', 'harmony')
    || !hasQueryParameter(bundle, 'transform.bytecode', '0')
    || !hasQueryParameter(bundle, 'dev', 'true')
    || !hasQueryParameter(bundle, 'transform.engine', 'hermes')) {
    throw new HarmonyCompatibilityError(
      [{ code: 'INVALID_MANIFEST', field: 'launchAsset', message: 'Manifest and bundle must use the same HTTP(S) origin, runtime, Harmony platform, and development JS source format.' }]
    );
  }
}
