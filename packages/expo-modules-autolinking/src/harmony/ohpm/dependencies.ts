import path from 'node:path';

import { resolveProviderSources } from '../providers/source';
import { resolveRnohMetadata } from '../rnoh/packageMetadata';
import { normalizeSlashes } from '../../utilities/values';

function collectOhpmDeps(descriptors, buildType = 'debug') {
  const dependencies = new Map();

  for (const descriptor of descriptors.filter(item => item.rnoh.harPaths.length > 0)) {
    for (const mapping of resolveRnohMetadata(descriptor).harMappings) {
      dependencies.set(mapping.ohPackageName, { descriptor, mapping });
    }
  }

  for (const source of resolveProviderSources(descriptors, buildType)) {
    const existing = dependencies.get(source.ohPackageName);
    if (existing
      && existing.descriptor.packageRoot === source.descriptor.packageRoot
      && existing.mapping.harPath === source.harPath) {
      continue;
    }
    dependencies.set(source.ohPackageName, {
      descriptor: source.descriptor,
      mapping: {
        harPath: source.harPath,
        ohPackageName: source.ohPackageName,
        ...(source.version ? { version: source.version } : {}),
      },
    });
  }

  return [...dependencies.values()].sort((left, right) => {
    return left.mapping.ohPackageName.localeCompare(right.mapping.ohPackageName, 'en');
  });
}

function resolveOhpmSpecifier(descriptor, mapping) {
  return mapping.version || descriptor.packageVersion;
}

function normalizeLocalOhpmSpecifier(specifier) {
  if (typeof specifier !== 'string' || !specifier) return null;
  if (path.isAbsolute(specifier) || path.win32.isAbsolute(specifier) || !/^\.\.?[\\/]/u.test(specifier)) {
    return null;
  }
  return normalizeSlashes(specifier);
}

export {
  collectOhpmDeps,
  resolveOhpmSpecifier,
  normalizeLocalOhpmSpecifier,
};
