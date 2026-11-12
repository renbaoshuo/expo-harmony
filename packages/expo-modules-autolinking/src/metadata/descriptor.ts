/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as fs from 'node:fs';
import * as path from 'node:path';

import JSON5 from 'json5';

import { ArkTsLibraryHarPath, ArkTsLibraryManifestPath } from '../config/constants';
import { HarmonyAutolinkingError } from '../errors';
import { HostMetadataFields } from './host';
import type { BuildType, RnohMetadata } from '../types';
import {
  isValidOhpmPackageName,
  normalizeHarmonyModuleMetadata,
  normalizeRnohPackageMetadata,
} from './schema';
import { materializeModuleArtifactAsync } from '../harmony/materialize';
import { resolveInlineModuleDescriptorAsync } from '../harmony/inlineModules';
import {
  defaultCmakeTargetForNpmPackage, resolveHarPackageMappings,
} from '../harmony/rnoh/packageMetadata';
import {
  compareText, isPathInside, isObject, normalizeSlashes, requireNonEmptyString,
  resolveInsideAsync, sortedUniqueStrings,
} from '../utilities/values';

const HarScanIgnoredDirectories = new Set(['.git', 'build', 'node_modules', 'oh_modules']);

async function findHarPathsAsync(packageRoot, directory, record): Promise<string[]> {
  const paths: string[] = [];
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

        paths.push(normalizeSlashes(path.relative(packageRoot, target)));
      }
    }
  }

  await visit(directory);

  return sortedUniqueStrings(paths);
}

function resolveOhpmPackageName(raw, paths, record) {
  const mappings = resolveHarPackageMappings({
    packageName: record.packageName,
    rnoh: { ohPackageName: raw, harPaths: paths },
  });
  if (!Array.isArray(raw) && paths.length === 1) return mappings[0].ohPackageName;
  return mappings.map(mapping => ({
    harName: path.basename(mapping.harPath),
    packageName: mapping.ohPackageName,
    ...(mapping.version ? { version: mapping.version } : {}),
  }));
}

async function resolveArkTsModulePackageAsync(record, harmony) {
  const hasHostExtensions = HostMetadataFields.some(field => harmony[field].length > 0);
  if (harmony.modules.length === 0 && harmony.services.length === 0 && !hasHostExtensions
    && !isObject(record.expoModuleConfig?.harmony)) return undefined;

  const file = await resolveInsideAsync(
    record.packageRoot,
    ArkTsLibraryManifestPath,
    'Harmony library OHPM manifest',
    { packageName: record.packageName, type: 'file' }
  );
  let manifest;

  try {
    manifest = JSON5.parse(await fs.promises.readFile(file, 'utf8'));
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
  return Object.fromEntries(HostMetadataFields.map(field => [field, record.supportsHarmony ? canonical[field] : []]));
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

  const directory = await resolveInsideAsync(
    record.packageRoot,
    main,
    'harmony.autolinking.mainHarPath',
    { packageName: record.packageName, type: 'directory' }
  );

  main = normalizeSlashes(path.relative(record.packageRoot, directory)) || '.';

  const paths = await findHarPathsAsync(record.packageRoot, directory, record);
  if (paths.length === 0) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.autolinking.mainHarPath does not contain a HAR file.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  const names = paths.map(harPath => path.basename(harPath));
  if (new Set(names).size !== names.length) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.autolinking.mainHarPath contains duplicate HAR filenames.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  const name = resolveOhpmPackageName(metadata.ohPackageName, paths, record);
  if (Array.isArray(name)) {
    const order = new Map(name.map((mapping, index) => [mapping.harName, index]));
    paths.sort((left, right) => {
      return order.get(path.basename(left)) - order.get(path.basename(right));
    });
  }

  const rnoh: RnohMetadata = {
    ohPackageName: name,
    mainHarPath: main,
    harPaths: paths,
    etsPackageClassName: metadata.etsPackageClassName,
    etsPackageImport: metadata.etsPackageImport,
    etsPackageScope: metadata.etsPackageScope,
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

  if (record.source === 'inlineModules') {
    return resolveInlineModuleDescriptorAsync(record);
  }

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
      link = packageRoot;
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
