import * as path from 'node:path';

import Case from 'case';
import { HarmonyAutolinkingError } from '../../errors';

function packageNameParts(packageName) {
  if (packageName.startsWith('@')) {
    const [scopeName, name] = packageName.slice(1).split('/');
    return { scopeName, name };
  }

  return { scopeName: null, name: packageName };
}

function defaultPackageClassName(packageName) {
  const { scopeName, name } = packageNameParts(packageName);
  return scopeName
    ? `${Case.pascal(scopeName)}${Case.pascal(name)}Package`
    : `${Case.pascal(name)}Package`;
}

function defaultCmakeTargetForNpmPackage(packageName) {
  const { scopeName, name } = packageNameParts(packageName);
  return scopeName
    ? `rnoh__${Case.snake(scopeName)}__${Case.snake(name)}`
    : `rnoh__${Case.snake(name)}`;
}

function defaultOhPackageNameForNpmPackage(packageName) {
  const { scopeName, name } = packageNameParts(packageName);
  return scopeName
    ? `@rnoh/${Case.kebab(scopeName)}--${Case.kebab(name)}`
    : `@rnoh/${Case.kebab(name)}`;
}

function ohPackageNameForHar(base, harPath, harCount) {
  return harCount > 1
    ? `${base}--${path.basename(harPath, '.har')}`
    : base;
}

function resolveHarPackageMappings(descriptor) {
  const harPaths = descriptor.rnoh.harPaths || [];
  if (harPaths.length === 0) return [];

  const configured = descriptor.rnoh.ohPackageName;
  if (configured === undefined) {
    const base = defaultOhPackageNameForNpmPackage(descriptor.packageName);
    return harPaths.map(harPath => ({
      harPath,
      ohPackageName: ohPackageNameForHar(base, harPath, harPaths.length),
    }));
  }

  if (typeof configured === 'string') {
    return harPaths.map(harPath => ({
      harPath,
      ohPackageName: ohPackageNameForHar(configured, harPath, harPaths.length),
    }));
  }

  if (!Array.isArray(configured)) {
    throw new HarmonyAutolinkingError(
      'INVALID_METADATA',
      'RNOH metadata must declare ohPackageName as a string or a complete HAR mapping array.',
      { packageName: descriptor.packageName, stage: 'metadata' }
    );
  }

  const mappings = new Map(configured.map(mapping => [mapping.harName, mapping]));
  const defaultName = defaultOhPackageNameForNpmPackage(descriptor.packageName);
  return harPaths.map((harPath) => {
    const mapping = mappings.get(path.basename(harPath));
    if (!mapping) return {
      harPath,
      ohPackageName: ohPackageNameForHar(defaultName, harPath, harPaths.length),
    };
    return {
      harPath,
      ohPackageName: mapping.packageName,
      ...(mapping.version ? { version: mapping.version } : {}),
    };
  });
}

function resolveRnohMetadata(descriptor) {
  const pkg = defaultPackageClassName(descriptor.packageName);

  return {
    packageName: descriptor.packageName,
    harMappings: resolveHarPackageMappings(descriptor),
    etsPackageClassName: descriptor.rnoh.etsPackageClassName || pkg,
    etsPackageImport: descriptor.rnoh.etsPackageImport || 'default',
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
