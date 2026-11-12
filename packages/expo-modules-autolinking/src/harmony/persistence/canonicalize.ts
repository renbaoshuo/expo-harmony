/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';

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
  const origin = requireProjectRoot(options.generatedProjectRoot, 'generatedProjectRoot');
  const target = requireProjectRoot(options.canonicalProjectRoot, 'canonicalProjectRoot');
  const validated = validateManifest(manifest);
  const canonical = {
    ...validated,
    modules: validated.modules.map(module => ({
      ...module,
      packageRoot: rebaseProjectPath(module.packageRoot, origin, target),
      packageLinkPath: rebaseProjectPath(module.packageLinkPath, origin, target),
      ...(module.arkTs?.builtHarPath
        ? {
            arkTs: {
              ...module.arkTs,
              builtHarPath: rebaseProjectPath(module.arkTs.builtHarPath, origin, target),
            },
          }
        : {}),
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
  const code = options.errorCode || 'INVALID_OPTIONS';
  const stage = options.stage || 'canonicalization';
  let candidate;

  try {
    candidate = JSON5.parse(source);
  } catch (cause) {
    throw new HarmonyAutolinkingError(code, 'harmony/oh-package.json5 must contain a JSON5 object.', { cause, stage });
  }

  if (!isObject(candidate)) {
    throw new HarmonyAutolinkingError(code, 'harmony/oh-package.json5 must contain a JSON5 object.', { stage });
  }

  for (const field of ['dependencies', 'devDependencies', 'dynamicDependencies', 'overrides']) {
    if (candidate[field] !== undefined && !isObject(candidate[field])) {
      throw new HarmonyAutolinkingError(code, `harmony/oh-package.json5 ${field} must be an object.`, { stage });
    }
  }

  const specifiers = ohpmDependenciesFromManifest(manifest);
  const names = Object.keys(specifiers).sort((left, right) => left.localeCompare(right, 'en'));
  const managed = new Set([
    ...(options.previousManagedOhpmPackageNames || []),
    ...names,
  ]);

  if (options.requireManagedEntries) {
    for (const field of ['dependencies', 'overrides']) {
      if (!isObject(candidate[field])) {
        throw new HarmonyAutolinkingError(
          code,
          `harmony/oh-package.json5 ${field} must be an object.`,
          { stage }
        );
      }

      for (const packageName of names) {
        if (!Object.hasOwn(candidate[field], packageName)) {
          throw new HarmonyAutolinkingError(
            code,
            `RNOH omitted the managed ${field} entry for ${packageName}.`,
            { stage, details: { packageName, field } }
          );
        }
      }
    }
  }

  let changed = false;
  for (const field of ['dependencies', 'overrides']) {
    const values = { ...(candidate[field] || {}) };
    for (const packageName of managed) delete values[packageName];
    for (const packageName of names) values[packageName] = specifiers[packageName];
    if (!isDeepStrictEqual(candidate[field] ?? {}, values)) {
      candidate[field] = values;
      changed = true;
    }
  }

  for (const field of ['dependencies', 'devDependencies', 'dynamicDependencies', 'overrides']) {
    for (const [name, value] of Object.entries(candidate[field] || {})) {
      if (typeof value !== 'string' || !value.trim()) {
        throw new HarmonyAutolinkingError(code, `harmony/oh-package.json5 ${field}.${name} must declare a version.`, { stage });
      }
    }
  }

  return {
    manifest: candidate,
    source: changed ? `${JSON5.stringify(candidate, null, 2)}\n` : source,
  };
}

function canonicalizeAutolinkingArtifacts(
  options: CanonicalizeAutolinkingArtifactsOptions
): CanonicalizedAutolinkingArtifacts {
  let parsed;

  try {
    parsed = JSON.parse(options.manifestSource);
  } catch (cause) {
    throw new HarmonyAutolinkingError(
      'INVALID_MANIFEST',
      'Harmony autolinking manifest must contain valid JSON.',
      { cause, stage: 'canonicalization' }
    );
  }

  const manifest = canonicalizeAutolinkingManifest(parsed, options);
  const ohpm = canonicalizeOhpmManifest(
    options.ohPackageSource,
    parsed,
    { requireManagedEntries: true }
  );

  return {
    manifest: manifest.manifest,
    manifestSource: manifest.source,
    ohPackageSource: ohpm.source,
  };
}

export {
  canonicalizeAutolinkingArtifacts,
  canonicalizeOhpmManifest,
};
