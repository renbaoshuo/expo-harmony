import path from 'node:path';

import { resolveRnohMetadata } from '../rnoh/packageMetadata';
import { normalizeSlashes } from '../../utilities/values';

function collectOhpmDeps(descriptors) {
  const dependencies = new Map();

  for (const descriptor of descriptors) {
    if (!descriptor.arkTs) continue;
    dependencies.set(descriptor.arkTs.ohPackageName, {
      descriptor,
      mapping: {
        harPath: descriptor.arkTs.harPath,
        ohPackageName: descriptor.arkTs.ohPackageName,
      },
    });
  }

  for (const descriptor of descriptors.filter(item => item.rnoh.harPaths.length > 0)) {
    for (const mapping of resolveRnohMetadata(descriptor).harMappings) {
      dependencies.set(mapping.ohPackageName, { descriptor, mapping });
    }
  }

  return [...dependencies.values()].sort((left, right) => {
    return left.mapping.ohPackageName.localeCompare(right.mapping.ohPackageName, 'en');
  });
}

function resolveOhpmSpecifier(
  descriptor,
  mapping,
  options: { harmonyProjectPath?: string; nodeModulesPath?: string } = {}
) {
  if (options.harmonyProjectPath) {
    const packageRoot = options.nodeModulesPath
      ? path.join(options.nodeModulesPath, ...descriptor.packageName.split('/'))
      : descriptor.packageLinkPath;
    const target = path.join(packageRoot, ...mapping.harPath.split('/'));
    const relative = normalizeSlashes(path.relative(options.harmonyProjectPath, target));
    return relative.startsWith('.') ? relative : `./${relative}`;
  }
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
