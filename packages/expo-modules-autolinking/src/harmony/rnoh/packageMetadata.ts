/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as path from 'node:path';

import Case from 'case';
import { HarmonyAutolinkingError } from '../../errors';

function packageNameParts(packageName) {
  if (packageName.startsWith('@')) {
    const [scope, name] = packageName.slice(1).split('/');
    return { scope, name };
  }

  return { scope: null, name: packageName };
}

function defaultPackageClassName(packageName) {
  const { scope, name } = packageNameParts(packageName);
  return scope
    ? `${Case.pascal(scope)}${Case.pascal(name)}Package`
    : `${Case.pascal(name)}Package`;
}

function defaultCmakeTargetForNpmPackage(packageName) {
  const { scope, name } = packageNameParts(packageName);
  return scope
    ? `rnoh__${Case.snake(scope)}__${Case.snake(name)}`
    : `rnoh__${Case.snake(name)}`;
}

function defaultOhPackageNameForNpmPackage(packageName) {
  const { scope, name } = packageNameParts(packageName);
  return scope
    ? `@rnoh/${Case.kebab(scope)}--${Case.kebab(name)}`
    : `@rnoh/${Case.kebab(name)}`;
}

function ohPackageNameForHar(base, harPath, harCount) {
  return harCount > 1
    ? `${base}--${path.basename(harPath, '.har')}`
    : base;
}

function resolveHarPackageMappings(descriptor) {
  const paths = descriptor.rnoh.harPaths || [];
  if (paths.length === 0) return [];

  const configured = descriptor.rnoh.ohPackageName;

  if (configured === undefined) {
    const base = defaultOhPackageNameForNpmPackage(descriptor.packageName);
    return paths.map(harPath => ({
      harPath,
      ohPackageName: ohPackageNameForHar(base, harPath, paths.length),
    }));
  }

  if (typeof configured === 'string') {
    return paths.map(harPath => ({
      harPath,
      ohPackageName: ohPackageNameForHar(configured, harPath, paths.length),
    }));
  }

  const fallback = defaultOhPackageNameForNpmPackage(descriptor.packageName);
  const lookup = new Map(paths.map(harPath => [path.basename(harPath), harPath]));
  const mapped = new Set();
  const mappings = [];

  // RNOH selects its primary HAR by mapping order, independent of scan order.
  for (const mapping of configured) {
    const harPath = lookup.get(mapping.harName);
    if (!harPath) continue;

    mapped.add(mapping.harName);
    mappings.push({
      harPath,
      ohPackageName: mapping.packageName,
      ...(mapping.version ? { version: mapping.version } : {}),
    });
  }

  for (const harPath of paths) {
    if (mapped.has(path.basename(harPath))) continue;

    mappings.push({
      harPath,
      ohPackageName: ohPackageNameForHar(fallback, harPath, paths.length),
    });
  }

  return mappings;
}

function resolveRnohMetadata(descriptor) {
  const pkg = defaultPackageClassName(descriptor.packageName);
  if ((descriptor.rnoh.etsPackageClassName === undefined
    || descriptor.rnoh.cppPackageClassName === undefined)
  && !/^[A-Za-z_][A-Za-z0-9_]*$/u.test(pkg)) {
    throw new HarmonyAutolinkingError(
      'INVALID_METADATA',
      'The npm package name cannot produce a valid default RNOH package class; configure the package class names explicitly.',
      { packageName: descriptor.packageName, stage: 'metadata' }
    );
  }

  return {
    packageName: descriptor.packageName,
    harMappings: resolveHarPackageMappings(descriptor),
    etsPackageClassName: descriptor.rnoh.etsPackageClassName || pkg,
    etsPackageImport: descriptor.rnoh.etsPackageImport || 'default',
    etsPackageScope: descriptor.rnoh.etsPackageScope ?? 'shared',
    cppPackageClassName: descriptor.rnoh.cppPackageClassName || pkg,
    cmakeLibraryTargetName: descriptor.rnoh.cmakeLibraryTargetName
      || defaultCmakeTargetForNpmPackage(descriptor.packageName),
  };
}

export {
  defaultCmakeTargetForNpmPackage,
  defaultOhPackageNameForNpmPackage,
  ohPackageNameForHar,
  resolveHarPackageMappings,
  resolveRnohMetadata,
};
