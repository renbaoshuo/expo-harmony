import * as fs from 'node:fs';
import * as path from 'node:path';

import JSON5 from 'json5';

import { HarmonyAutolinkingError } from '../errors';
import type { BuildType, RnohMetadata } from '../types';
import {
  isValidOhpmPackageName,
  normalizeHarmonyModuleMetadata,
  normalizeRnohPackageMetadata,
} from './schema';
import { materializeModuleArtifactAsync } from '../harmony/materialize';
import {
  defaultCmakeTargetForNpmPackage, defaultOhPackageNameForNpmPackage,
  ohPackageNameForHar,
} from '../harmony/rnoh/packageMetadata';
import {
  compareText, isPathInside, isObject, normalizeSlashes, requireNonEmptyString,
  resolveInsideAsync, sortedUniqueStrings,
} from '../utilities/values';

const HarScanIgnoredDirectories = new Set(['.git', 'build', 'node_modules', 'oh_modules']);
const ArkTsLibraryManifestPath = 'harmony/library/oh-package.json5';
const ArkTsLibraryHarPath = 'harmony/library.har';

async function findHarPathsAsync(packageRoot, scanRoot, record): Promise<string[]> {
  const harPaths: string[] = [];
  const visited = new Set();

  async function visit(directory) {
    let real;
    let entries;
    try {
      real = await fs.promises.realpath(directory);
      entries = await fs.promises.readdir(directory, { withFileTypes: true });
    } catch (cause) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', 'Unable to scan harmony.autolinking.mainHarPath.', {
        cause,
        packageName: record.packageName,
        stage: 'metadata',
      });
    }

    if (!isPathInside(packageRoot, real)) {
      throw new HarmonyAutolinkingError('PATH_OUTSIDE_PACKAGE', 'harmony.autolinking.mainHarPath resolves outside package root.', { packageName: record.packageName, stage: 'metadata' });
    }
    if (visited.has(real)) return;
    visited.add(real);

    entries.sort((left, right) => compareText(left.name, right.name));
    for (const entry of entries) {
      const target = path.join(directory, entry.name);
      let stat;
      try {
        stat = await fs.promises.lstat(target);
      } catch (cause) {
        throw new HarmonyAutolinkingError('INVALID_METADATA', 'A HAR scan entry is missing or unreadable.', {
          cause,
          packageName: record.packageName,
          stage: 'metadata',
        });
      }

      if (stat.isDirectory()) {
        if (HarScanIgnoredDirectories.has(entry.name)) continue;
        await visit(target);
      } else if (path.extname(entry.name) === '.har') {
        let realTarget;
        try {
          realTarget = await fs.promises.realpath(target);
          if (!(await fs.promises.stat(realTarget)).isFile()) continue;
        } catch (cause) {
          throw new HarmonyAutolinkingError('INVALID_METADATA', 'A HAR scan entry is missing or unreadable.', {
            cause,
            packageName: record.packageName,
            stage: 'metadata',
          });
        }

        if (!isPathInside(packageRoot, realTarget)) {
          throw new HarmonyAutolinkingError('PATH_OUTSIDE_PACKAGE', 'A HAR scan path resolves outside package root.', { packageName: record.packageName, stage: 'metadata' });
        }

        harPaths.push(normalizeSlashes(path.relative(packageRoot, target)));
      }
    }
  }

  await visit(scanRoot);

  return sortedUniqueStrings(harPaths);
}

function resolveOhpmPackageName(raw, harPaths, record) {
  const base = defaultOhPackageNameForNpmPackage(record.packageName);
  const fallback = harPath => ({
    harName: path.basename(harPath),
    packageName: ohPackageNameForHar(base, harPath, harPaths.length),
  });

  if (raw === undefined) {
    return harPaths.length === 1 ? base : harPaths.map(fallback);
  }

  if (typeof raw === 'string') {
    return harPaths.length === 1
      ? raw
      : harPaths.map(harPath => ({
          harName: path.basename(harPath),
          packageName: ohPackageNameForHar(raw, harPath, harPaths.length),
        }));
  }

  const harNames = new Set(harPaths.map(harPath => path.basename(harPath)));
  const mappings = raw.map((mapping) => {
    if (!harNames.has(mapping.harName)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `package.json#harmony.autolinking.ohPackageName mapping ${mapping.harName} does not match a discovered HAR.`, {
        packageName: record.packageName,
        stage: 'metadata',
      });
    }
    return mapping;
  });
  const mapped = new Set(mappings.map(mapping => mapping.harName));
  for (const harPath of harPaths) {
    if (!mapped.has(path.basename(harPath))) mappings.push(fallback(harPath));
  }

  return mappings;
}

async function resolveArkTsModulePackageAsync(record, harmony) {
  const hasHostExtensions = harmony.rootViewComponents.length > 0;
  if (harmony.modules.length === 0 && !hasHostExtensions) return undefined;

  const manifestPath = await resolveInsideAsync(
    record.packageRoot,
    ArkTsLibraryManifestPath,
    'Harmony library OHPM manifest',
    { packageName: record.packageName, type: 'file' }
  );
  let manifest;
  try {
    manifest = JSON5.parse(await fs.promises.readFile(manifestPath, 'utf8'));
  } catch (cause) {
    throw new HarmonyAutolinkingError(
      'INVALID_METADATA',
      `${ArkTsLibraryManifestPath} must contain valid JSON5.`,
      { cause, packageName: record.packageName, stage: 'metadata' }
    );
  }
  if (!isObject(manifest) || !isValidOhpmPackageName(manifest.name)) {
    throw new HarmonyAutolinkingError(
      'INVALID_METADATA',
      `${ArkTsLibraryManifestPath} must declare a valid OHPM package name.`,
      { packageName: record.packageName, stage: 'metadata' }
    );
  }
  return {
    harPath: ArkTsLibraryHarPath,
    ohPackageName: manifest.name,
  };
}

function normalizeExpoMetadata(record, canonical) {
  if (!record.supportsHarmony) return {
    rootViewComponents: [],
  };

  return {
    rootViewComponents: canonical.rootViewComponents,
  };
}

async function normalizeRnohMetadataAsync(record) {
  if (record.rnohMetadata == null) {
    return {
      ohPackageName: undefined,
      mainHarPath: undefined,
      harPaths: [],
      etsPackageClassName: undefined,
      cppPackageClassName: undefined,
      cmakeLibraryTargetName: undefined,
    };
  }

  const metadata = normalizeRnohPackageMetadata(record.rnohMetadata, {
    packageName: record.packageName,
    packageVersion: record.packageVersion,
  });

  let main;
  if (metadata.mainHarPath !== undefined) {
    main = metadata.mainHarPath;
  } else {
    try {
      const harmonyStat = await fs.promises.stat(path.join(record.packageRoot, 'harmony'));
      main = harmonyStat.isDirectory() ? 'harmony' : '.';
    } catch (_cause) {
      main = '.';
    }
  }

  const scanRoot = await resolveInsideAsync(
    record.packageRoot,
    main,
    'harmony.autolinking.mainHarPath',
    { packageName: record.packageName, type: 'directory' }
  );
  main = normalizeSlashes(path.relative(record.packageRoot, scanRoot)) || '.';

  const harPaths = await findHarPathsAsync(record.packageRoot, scanRoot, record);
  if (harPaths.length === 0) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.autolinking.mainHarPath does not contain a HAR file.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  const harBasenames = harPaths.map(harPath => path.basename(harPath));
  if (new Set(harBasenames).size !== harBasenames.length) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.autolinking.mainHarPath contains duplicate HAR filenames.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  const name = resolveOhpmPackageName(metadata.ohPackageName, harPaths, record);
  if (Array.isArray(name)) {
    const order = new Map(name.map((mapping, index) => [mapping.harName, index]));
    harPaths.sort((left, right) => {
      return order.get(path.basename(left)) - order.get(path.basename(right));
    });
  }

  const rnoh: RnohMetadata = {
    ohPackageName: name,
    mainHarPath: main,
    harPaths,
    etsPackageClassName: metadata.etsPackageClassName,
    etsPackageImport: metadata.etsPackageImport,
    cppPackageClassName: metadata.cppPackageClassName,
    cmakeLibraryTargetName: metadata.cmakeLibraryTargetName
      || defaultCmakeTargetForNpmPackage(record.packageName),
  };

  return rnoh;
}

function assertSearchRecord(record) {
  if (!isObject(record)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'Search record must be an object.', {
      stage: 'metadata',
    });
  }

  for (const field of ['packageName', 'packageVersion', 'packageRoot', 'source']) {
    requireNonEmptyString(record[field], field, { packageName: record.packageName });
  }
}

async function createDescriptorFromSearchRecordAsync(record, buildType: BuildType = 'debug') {
  assertSearchRecord(record);

  let packageRoot;
  try {
    packageRoot = await fs.promises.realpath(record.packageRoot);
    if (!(await fs.promises.stat(packageRoot)).isDirectory()) throw new TypeError('not a directory');
  } catch (cause) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${record.packageName} packageRoot is not an existing directory.`, {
      cause,
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  const base = { ...record, packageRoot };
  let link = packageRoot;
  if (typeof record.revision?.originPath === 'string') {
    const candidate = path.resolve(record.revision.originPath);
    try {
      if (await fs.promises.realpath(candidate) === packageRoot) link = candidate;
    } catch (_cause) {
      // The canonical package root remains the safe fallback for direct callers.
    }
  }

  const expoConfig = isObject(base.expoModuleConfig) ? base.expoModuleConfig : null;
  const harmony = normalizeHarmonyModuleMetadata(
    expoConfig?.harmony,
    { packageName: record.packageName, packageVersion: record.packageVersion }
  );
  const arkTs = await resolveArkTsModulePackageAsync(base, harmony);
  const rnoh = await normalizeRnohMetadataAsync(base);
  const expo = normalizeExpoMetadata(base, harmony);
  const artifact = await materializeModuleArtifactAsync({
    packageName: record.packageName,
    packageRoot,
    source: record.source,
    buildType,
    arkTs,
    rnoh,
  });

  const descriptor = {
    packageName: record.packageName,
    packageVersion: record.packageVersion,
    packageRoot,
    packageLinkPath: link,
    source: record.source,
    expo,
    rnoh,
    harmony,
    ...(arkTs ? { arkTs } : {}),
    artifact,
  };

  return descriptor;
}

export {
  createDescriptorFromSearchRecordAsync,
};
