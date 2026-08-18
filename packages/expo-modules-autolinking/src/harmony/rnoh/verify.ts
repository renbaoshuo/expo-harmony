import JSON5 from 'json5';

import { HarmonyAutolinkingError } from '../../errors';
import {
  collectOhpmDeps,
  resolveOhpmSpecifier,
  normalizeLocalOhpmSpecifier,
} from '../ohpm/dependencies';
import { normalizeSlashes } from '../../utilities/values';
import { resolveRnohMetadata } from './packageMetadata';

function captureValues(content, pattern) {
  return [...content.matchAll(pattern)].map(match => match[1]).sort();
}

function captureTuples(content, pattern, fields) {
  return [...content.matchAll(pattern)]
    .map(match => fields.map(index => match[index]).join('\0'))
    .sort();
}

function importRelations(content) {
  const relations = [];
  for (const match of content.matchAll(
    /^\s*import\s+([A-Za-z_$][A-Za-z0-9_$]*)\s+from\s+(['"])([^'"\r\n]+)\2;\s*$/gm
  )) {
    relations.push(`default\0${match[3]}\0${match[1]}`);
  }

  for (const match of content.matchAll(
    /^\s*import\s+\{\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\}\s+from\s+(['"])([^'"\r\n]+)\2;\s*$/gm
  )) {
    relations.push(`named\0${match[3]}\0${match[1]}`);
  }

  return relations.sort();
}

function assertExactValues(label, expected, actual) {
  const left = [...expected].sort();
  const right = [...actual].sort();

  if (left.length === right.length && left.every((value, index) => value === right[index])) return;
  throw new HarmonyAutolinkingError('GENERATED_ARTIFACT_SET_MISMATCH', `RNOH generated an unexpected ${label} set.`, {
    stage: 'rnoh-validate',
    details: { label, expected: left, actual: right },
  });
}

function syncOhpmVersions(artifacts, descriptors, buildType) {
  let manifest;
  try {
    manifest = JSON5.parse(artifacts.ohPackage.content);
  } catch (cause) {
    throw new HarmonyAutolinkingError('GENERATED_ARTIFACT_SET_MISMATCH', 'Generated oh-package.json5 is invalid.', {
      cause,
      stage: 'rnoh-validate',
    });
  }

  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)
    || !manifest.dependencies || typeof manifest.dependencies !== 'object'
    || Array.isArray(manifest.dependencies)
    || !manifest.overrides || typeof manifest.overrides !== 'object'
    || Array.isArray(manifest.overrides)) {
    throw new HarmonyAutolinkingError('GENERATED_ARTIFACT_SET_MISMATCH', 'Generated oh-package.json5 is invalid.', {
      stage: 'rnoh-validate',
    });
  }

  for (const { descriptor, mapping } of collectOhpmDeps(descriptors, buildType)) {
    const version = resolveOhpmSpecifier(descriptor, mapping);

    for (const field of ['dependencies', 'overrides']) {
      if (!Object.hasOwn(manifest[field], mapping.ohPackageName)) {
        throw new HarmonyAutolinkingError(
          'GENERATED_ARTIFACT_SET_MISMATCH',
          `RNOH omitted the managed ${field} entry for ${mapping.ohPackageName}.`,
          { stage: 'rnoh-validate', details: { packageName: mapping.ohPackageName, field } }
        );
      }
      manifest[field][mapping.ohPackageName] = version;
    }
  }

  artifacts.ohPackage.content = `${JSON5.stringify(manifest, null, 2)}\n`;
}

function verifyOhpmDependencies(artifacts, descriptors, options) {
  const parsed = JSON5.parse(artifacts.ohPackage.content);
  const dependencies = parsed.dependencies && typeof parsed.dependencies === 'object'
    && !Array.isArray(parsed.dependencies)
    ? parsed.dependencies
    : {};
  const overrides = parsed.overrides && typeof parsed.overrides === 'object'
    && !Array.isArray(parsed.overrides)
    ? parsed.overrides
    : {};
  const expected = new Map();

  for (const { descriptor, mapping } of collectOhpmDeps(descriptors, options.buildType)) {
    expected.set(
      mapping.ohPackageName,
      resolveOhpmSpecifier(descriptor, mapping)
    );
  }

  for (const [name, specifier] of expected) {
    if (dependencies[name] !== specifier) {
      throw new HarmonyAutolinkingError(
        'GENERATED_ARTIFACT_SET_MISMATCH',
        `RNOH generated an unexpected dependency for ${name}.`,
        {
          stage: 'rnoh-validate',
          details: { packageName: name, expected: specifier, actual: dependencies[name] },
        }
      );
    }
    if (overrides[name] !== specifier) {
      throw new HarmonyAutolinkingError(
        'GENERATED_ARTIFACT_SET_MISMATCH',
        `RNOH generated an unexpected override for ${name}.`,
        {
          stage: 'rnoh-validate',
          details: { packageName: name, expected: specifier, actual: overrides[name] },
        }
      );
    }
  }

  const allowed = new Map(Object.entries(options.allowedUnmanagedDependencies || {}));
  for (const name of expected.keys()) allowed.delete(name);

  const expectedLocal = [...expected, ...allowed]
    .map(([name, value]) => [name, normalizeLocalOhpmSpecifier(value)])
    .filter(([, value]) => value?.includes('node_modules/'));
  const actualLocal = Object.entries(dependencies)
    .map(([name, value]) => [name, normalizeLocalOhpmSpecifier(value)])
    .filter(([, value]) => value?.includes('node_modules/'));

  assertExactValues(
    'managed OH package dependency',
    expectedLocal.map(entry => `${entry[0]}\0${normalizeSlashes(entry[1])}`),
    actualLocal.map(entry => `${entry[0]}\0${normalizeSlashes(entry[1])}`)
  );
}

function verifyRnohArtifacts(artifacts, descriptors, options) {
  const packages = descriptors
    .filter(descriptor => descriptor.rnoh.harPaths.length > 0)
    .map(descriptor => ({ descriptor, metadata: resolveRnohMetadata(descriptor) }));

  assertExactValues(
    'ETS Package class',
    packages.map(({ metadata }) => metadata.etsPackageClassName),
    captureValues(artifacts.etsFactory.content, /^\s*new\s+([A-Za-z_$][A-Za-z0-9_$]*)\(ctx\),?\s*$/gm)
  );
  assertExactValues(
    'ETS import package/class relation',
    packages.map(({ metadata }) => `${metadata.etsPackageImport}\0${metadata.harMappings[0].ohPackageName}\0${metadata.etsPackageClassName}`),
    importRelations(artifacts.etsFactory.content)
  );

  assertExactValues(
    'C++ Package class',
    packages.map(({ metadata }) => metadata.cppPackageClassName),
    captureValues(artifacts.cppFactory.content, /std::make_shared<rnoh::([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*)>\(ctx\)/g)
  );

  const targets = packages.map(({ metadata }) => metadata.cmakeLibraryTargetName);
  assertExactValues(
    'CMake add_subdirectory target',
    targets,
    captureValues(artifacts.cmake.content, /add_subdirectory\([^\n]*\s\.\/([^\s)]+)\)/g)
  );

  assertExactValues(
    'CMake OH package/target relation',
    packages.map(({ metadata }) => `${metadata.harMappings[0].ohPackageName}\0${metadata.cmakeLibraryTargetName}`),
    captureTuples(artifacts.cmake.content, /^\s*add_subdirectory\("\$\{OH_MODULES_DIR\}\/([^"\r\n]+)\/src\/main\/cpp"\s+\.\/([^\s)]+)\)\s*$/gm, [1, 2])
  );

  const libraryBlock = artifacts.cmake.content.match(/set\(AUTOLINKED_LIBRARIES\s*\n([\s\S]*?)\n\s*\)/);
  assertExactValues('CMake linked library', targets, libraryBlock ? libraryBlock[1].split(/\r?\n/).map(value => value.trim()).filter(Boolean) : []);

  verifyOhpmDependencies(artifacts, descriptors, options);
}

export {
  assertExactValues,
  syncOhpmVersions,
  verifyRnohArtifacts,
};
