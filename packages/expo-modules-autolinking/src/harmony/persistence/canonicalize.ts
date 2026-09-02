import path from 'node:path';

import JSON5 from 'json5';

import type {
  CanonicalizeAutolinkingArtifactsOptions,
  CanonicalizedAutolinkingArtifacts,
  Manifest,
} from '../../types';
import { HarmonyAutolinkingError } from '../../errors';
import { ohpmDependenciesFromManifest, validateManifest } from '../manifest';
import { isObject, isPathInside, stringifyJson } from '../../utilities/values';

interface CanonicalizeOhpmManifestOptions {
  previousManagedOhpmPackageNames?: ReadonlyArray<string>;
  requireManagedEntries?: boolean;
  harmonyProjectPath?: string;
  nodeModulesPath?: string;
  errorCode?: string;
  stage?: string;
}

function requireProjectRoot(value: unknown, field: string): string {
  if (typeof value !== 'string' || !path.isAbsolute(value)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', `${field} must be an absolute path.`, { stage: 'canonicalization' });
  }
  return path.resolve(value);
}

function rebaseProjectPath(value: string, fromRoot: string, toRoot: string): string {
  if (!path.isAbsolute(value) || !isPathInside(fromRoot, value)) return value;
  return path.join(toRoot, path.relative(fromRoot, value));
}

function canonicalizeAutolinkingManifest(
  manifest: unknown,
  options: { generatedProjectRoot: string; canonicalProjectRoot: string }
): { manifest: Manifest; source: string } {
  const generatedProjectRoot = requireProjectRoot(options.generatedProjectRoot, 'generatedProjectRoot');
  const canonicalProjectRoot = requireProjectRoot(options.canonicalProjectRoot, 'canonicalProjectRoot');
  const validated = validateManifest(manifest);
  const canonical = {
    ...validated,
    modules: validated.modules.map(module => ({
      ...module,
      packageRoot: rebaseProjectPath(module.packageRoot, generatedProjectRoot, canonicalProjectRoot),
      packageLinkPath: rebaseProjectPath(module.packageLinkPath, generatedProjectRoot, canonicalProjectRoot),
    })),
  } as Manifest;

  return {
    manifest: canonical,
    source: stringifyJson(canonical),
  };
}

function canonicalizeOhpmManifest(
  source: string,
  manifest: Manifest,
  options: CanonicalizeOhpmManifestOptions = {}
): { manifest: Readonly<Record<string, unknown>>; source: string } {
  const errorCode = options.errorCode || 'INVALID_OPTIONS';
  const stage = options.stage || 'canonicalization';
  let candidate;
  try {
    candidate = JSON5.parse(source);
  } catch (cause) {
    throw new HarmonyAutolinkingError(errorCode, 'harmony/oh-package.json5 must contain a JSON5 object.', { cause, stage });
  }

  if (!isObject(candidate)) {
    throw new HarmonyAutolinkingError(errorCode, 'harmony/oh-package.json5 must contain a JSON5 object.', { stage });
  }

  for (const field of ['dependencies', 'overrides']) {
    if (candidate[field] !== undefined && !isObject(candidate[field])) {
      throw new HarmonyAutolinkingError(errorCode, `harmony/oh-package.json5 ${field} must be an object.`, { stage });
    }
  }

  const specifiers = ohpmDependenciesFromManifest(manifest, {
    harmonyProjectPath: options.harmonyProjectPath,
    nodeModulesPath: options.nodeModulesPath,
  });
  const currentNames = Object.keys(specifiers).sort((left, right) => left.localeCompare(right, 'en'));
  const managedNames = new Set([
    ...(options.previousManagedOhpmPackageNames || []),
    ...currentNames,
  ]);

  if (options.requireManagedEntries) {
    for (const field of ['dependencies', 'overrides']) {
      if (!isObject(candidate[field])) {
        throw new HarmonyAutolinkingError(
          errorCode,
          `harmony/oh-package.json5 ${field} must be an object.`,
          { stage }
        );
      }
      for (const packageName of currentNames) {
        if (!Object.hasOwn(candidate[field], packageName)) {
          throw new HarmonyAutolinkingError(
            errorCode,
            `RNOH omitted the managed ${field} entry for ${packageName}.`,
            { stage, details: { packageName, field } }
          );
        }
      }
    }
  }

  for (const field of ['dependencies', 'overrides']) {
    const values = { ...(candidate[field] || {}) };
    for (const packageName of managedNames) delete values[packageName];
    for (const packageName of currentNames) values[packageName] = specifiers[packageName];
    candidate[field] = values;
  }

  return {
    manifest: candidate,
    source: `${JSON5.stringify(candidate, null, 2)}\n`,
  };
}

function canonicalizeAutolinkingArtifacts(
  options: CanonicalizeAutolinkingArtifactsOptions
): CanonicalizedAutolinkingArtifacts {
  let parsedManifest;
  try {
    parsedManifest = JSON.parse(options.manifestSource);
  } catch (cause) {
    throw new HarmonyAutolinkingError(
      'INVALID_MANIFEST',
      'Harmony autolinking manifest must contain valid JSON.',
      { cause, stage: 'canonicalization' }
    );
  }

  const canonicalManifest = canonicalizeAutolinkingManifest(parsedManifest, options);
  const canonicalOhpm = canonicalizeOhpmManifest(
    options.ohPackageSource,
    canonicalManifest.manifest,
    { requireManagedEntries: true }
  );

  return {
    manifest: canonicalManifest.manifest,
    manifestSource: canonicalManifest.source,
    ohPackageSource: canonicalOhpm.source,
  };
}

export {
  canonicalizeAutolinkingArtifacts,
  canonicalizeOhpmManifest,
};
