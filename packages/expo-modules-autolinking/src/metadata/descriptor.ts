import * as fs from 'node:fs';
import * as path from 'node:path';

import { HarmonyAutolinkingError } from '../errors';
import { normalizeHostMetadata } from './host';
import {
  defaultCmakeTargetForNpmPackage, defaultOhPackageNameForNpmPackage,
  ohPackageNameForHar, resolveRnohMetadata,
} from '../harmony/rnoh/packageMetadata';
import {
  compareText, isPathInside, isObject, normalizeSlashes, requireNonEmptyString,
  resolveInsideAsync, sortedUniqueStrings,
} from '../utilities/values';

const CppSymbolPattern = /^[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*$/;
const ArkTsIdentifierPattern = /^[A-Za-z_$][A-Za-z0-9_$]*$/;
const CmakeTargetPattern = /^[A-Za-z0-9_.:+-]+$/;
const ProviderIdentifierPattern = /^[^\0\r\n]+$/;
const OhPackagePartPattern = /^[A-Za-z0-9._~-]+$/;
const HarScanIgnoredDirectories = new Set(['.git', 'build', 'node_modules', 'oh_modules']);

function isValidOhpmPackageName(value) {
  if (typeof value !== 'string' || !value || /[\0\r\n\\'"`;${}()<>\s]/u.test(value)) {
    return false;
  }

  const parts = value.startsWith('@') ? value.slice(1).split('/') : value.split('/');
  return parts.length === (value.startsWith('@') ? 2 : 1)
    && parts.every(part => part !== '.' && part !== '..' && OhPackagePartPattern.test(part));
}

function requireValidOhpmPackageName(value, field, record) {
  const specifier = requireNonEmptyString(value, field, { packageName: record.packageName });

  if (!isValidOhpmPackageName(specifier)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} must be a safe scoped or unscoped OH package specifier.`, { packageName: record.packageName, stage: 'metadata' });
  }
  return specifier;
}

function optionalMetadataString(metadata, field, record) {
  if (metadata[field] === undefined) return undefined;
  return requireNonEmptyString(metadata[field], `harmony.autolinking.${field}`, { packageName: record.packageName });
}

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

function normalizeOhpmPackageName(metadata, harPaths, record) {
  const raw = metadata.ohPackageName;
  const base = defaultOhPackageNameForNpmPackage(record.packageName);
  const fallback = harPath => ({
    harName: path.basename(harPath),
    packageName: ohPackageNameForHar(base, harPath, harPaths.length),
  });

  if (raw === undefined) {
    return harPaths.length === 1 ? base : harPaths.map(fallback);
  }

  if (typeof raw === 'string') {
    const packageName = requireValidOhpmPackageName(raw, 'harmony.autolinking.ohPackageName', record);
    return harPaths.length === 1
      ? packageName
      : harPaths.map(harPath => ({
          harName: path.basename(harPath),
          packageName: ohPackageNameForHar(packageName, harPath, harPaths.length),
        }));
  }

  if (!Array.isArray(raw)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.autolinking.ohPackageName must be a string or mapping array.', { packageName: record.packageName, stage: 'metadata' }
    );
  }
  const harNames = new Set(harPaths.map(harPath => path.basename(harPath)));
  const seen = new Set();

  const mappings = raw.map((mapping, index) => {
    const field = `harmony.autolinking.ohPackageName[${index}]`;
    if (!isObject(mapping)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} must be an object.`, {
        packageName: record.packageName,
        stage: 'metadata',
      });
    }
    const harName = requireNonEmptyString(mapping.harName, `${field}.harName`, { packageName: record.packageName });

    if (path.basename(harName) !== harName || path.extname(harName).toLowerCase() !== '.har') {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.harName must be a HAR filename without a directory.`, {
        packageName: record.packageName,
        stage: 'metadata',
      });
    }
    if (!harNames.has(harName)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.harName does not match a HAR under mainHarPath.`, {
        packageName: record.packageName,
        stage: 'metadata',
      });
    }

    if (seen.has(harName)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.harName is declared more than once.`, {
        packageName: record.packageName,
        stage: 'metadata',
      });
    }
    seen.add(harName);

    const packageName = requireValidOhpmPackageName(mapping.packageName, `${field}.packageName`, record);
    const version = mapping.version === undefined
      ? undefined
      : requireNonEmptyString(mapping.version, `${field}.version`, { packageName: record.packageName });
    return { harName, packageName, ...(version ? { version } : {}) };
  });
  for (const harPath of harPaths) {
    if (!seen.has(path.basename(harPath))) mappings.push(fallback(harPath));
  }

  return mappings;
}

async function normalizeProviderAsync(provider, index, record) {
  const field = `harmony.providers[${index}]`;

  if (!isObject(provider)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} must be an object.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  if ('anchorHeader' in provider || 'anchorSymbol' in provider) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} uses the unsupported anchor registration contract.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  const identifier = requireNonEmptyString(provider.identifier, `${field}.identifier`, {
    packageName: record.packageName,
  });

  if (!ProviderIdentifierPattern.test(identifier)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.identifier contains a forbidden control character.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  const className = requireNonEmptyString(provider.className, `${field}.className`, {
    packageName: record.packageName,
  });

  if (!CppSymbolPattern.test(className)) {
    throw new HarmonyAutolinkingError('INVALID_CPP_SYMBOL', `${field}.className is not a valid C++ qualified identifier.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  if (!className.includes('::')) {
    throw new HarmonyAutolinkingError('INVALID_CPP_SYMBOL', `${field}.className must be namespace-qualified.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  const target = requireNonEmptyString(provider.cmakeTargetName, `${field}.cmakeTargetName`, {
    packageName: record.packageName,
  });
  if (!CmakeTargetPattern.test(target)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.cmakeTargetName is not a valid CMake target.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  if (provider.debugOnly !== undefined && typeof provider.debugOnly !== 'boolean') {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.debugOnly must be a boolean.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  const header = requireNonEmptyString(provider.header, `${field}.header`, {
    packageName: record.packageName,
  });

  if (/[\0\r\n"<>]/.test(header)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.header contains characters unsafe for a C++ include.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  const resolved = await resolveInsideAsync(record.packageRoot, header, `${field}.header`, {
    packageName: record.packageName,
    type: 'file',
  });

  return {
    identifier,
    header: normalizeSlashes(path.relative(record.packageRoot, resolved)),
    className,
    cmakeTargetName: target,
    debugOnly: provider.debugOnly === true,
  };
}

async function normalizeProviderHarAsync(value, record) {
  const field = 'harmony.providerHar';

  if (!isObject(value)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} must be an object.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  const harPath = requireNonEmptyString(value.harPath, `${field}.harPath`, {
    packageName: record.packageName,
  });
  const normalized = path.posix.normalize(harPath.replace(/\\/g, '/'));

  if (path.win32.isAbsolute(harPath)
    || path.posix.isAbsolute(normalized)
    || normalized === '..'
    || normalized.startsWith('../')
    || path.posix.extname(normalized) !== '.har') {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.harPath must reference a package-relative .har file.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  const resolvedHar = await resolveInsideAsync(record.packageRoot, path.join(...normalized.split('/')), `${field}.harPath`, {
    packageName: record.packageName,
    type: 'file',
  });

  return {
    harPath: normalizeSlashes(path.relative(record.packageRoot, resolvedHar)),
    ohPackageName: requireValidOhpmPackageName(value.ohPackageName, `${field}.ohPackageName`, record),
  };
}

async function normalizeExpoMetadataAsync(record) {
  if (!record.supportsHarmony) return {
    abilityLifecycleSubscribers: [],
    providers: [],
    reactInstanceLifecycleListeners: [],
    rootViewComponents: [],
  };

  const raw = record.expoModuleConfig;
  if (!isObject(raw)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'A Harmony Expo module must have a valid Expo module config.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  const harmony = raw.harmony;

  if (!isObject(harmony)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'expo-module.config.json#harmony must be an object.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  if ('anchorHeader' in harmony || 'anchorSymbol' in harmony) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'expo-module.config.json#harmony uses the unsupported anchor registration contract.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  const rawProviders = harmony.providers === undefined ? [] : harmony.providers;

  if (!Array.isArray(rawProviders)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'expo-module.config.json#harmony.providers must be an array.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  const providers = [];
  for (let index = 0; index < rawProviders.length; index += 1) {
    providers.push(await normalizeProviderAsync(rawProviders[index], index, record));
  }

  if (providers.length === 0 && harmony.providerHar !== undefined) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'expo-module.config.json#harmony.providerHar requires at least one Provider.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  const hostMetadata = normalizeHostMetadata(harmony, record);

  return {
    ...hostMetadata,
    ...(harmony.providerHar === undefined
      ? {}
      : { providerHar: await normalizeProviderHarAsync(harmony.providerHar, record) }),
    providers: providers.sort((left, right) => left.identifier.localeCompare(right.identifier, 'en')),
  };
}

function resolveExpoProviderHar(expo, rnoh, record) {
  if (expo.providers.length === 0) return expo;

  const rnohPackage = rnoh.harPaths.length > 0
    ? resolveRnohMetadata({ packageName: record.packageName, rnoh })
    : null;

  if (expo.providerHar) {
    const sameHar = rnohPackage?.harMappings.find(mapping => mapping.harPath === expo.providerHar.harPath);
    const primaryHar = rnohPackage?.harMappings[0];
    const reuse = primaryHar?.harPath === expo.providerHar.harPath
      && primaryHar.ohPackageName === expo.providerHar.ohPackageName;

    if (sameHar && sameHar.ohPackageName !== expo.providerHar.ohPackageName) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.providerHar.ohPackageName must match the RNOH mapping for the same HAR.', {
        packageName: record.packageName,
        stage: 'metadata',
      });
    }

    if (rnohPackage && !reuse && expo.providers.some((provider) => {
      return provider.cmakeTargetName === rnohPackage.cmakeLibraryTargetName;
    })) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', 'A Provider that reuses the RNOH CMake target must use the same RNOH HAR as harmony.providerHar.', {
        packageName: record.packageName,
        stage: 'metadata',
      });
    }

    return expo;
  }

  if (!rnohPackage) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'Expo Harmony Providers require harmony.providerHar so their headers and CMake targets have a source HAR.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  if (expo.providers.some(provider => provider.cmakeTargetName !== rnohPackage.cmakeLibraryTargetName)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'Providers without an explicit harmony.providerHar must reuse the package RNOH CMake target.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  const primary = rnohPackage.harMappings[0];

  return {
    ...expo,
    providerHar: {
      harPath: primary.harPath,
      ohPackageName: primary.ohPackageName,
    },
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

  const metadata = record.rnohMetadata === true ? {} : record.rnohMetadata;
  if (!isObject(metadata)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'package.json#harmony.autolinking must be an object.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  let main;
  if (metadata.mainHarPath !== undefined) {
    main = requireNonEmptyString(metadata.mainHarPath, 'harmony.autolinking.mainHarPath', {
      packageName: record.packageName,
    });
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

  const name = normalizeOhpmPackageName(metadata, harPaths, record);
  if (Array.isArray(name)) {
    const order = new Map(name.map((mapping, index) => [mapping.harName, index]));
    harPaths.sort((left, right) => {
      return order.get(path.basename(left)) - order.get(path.basename(right));
    });
  }

  const etsClass = optionalMetadataString(metadata, 'etsPackageClassName', record);
  const etsImport = metadata.etsPackageImport === undefined
    ? undefined
    : requireNonEmptyString(metadata.etsPackageImport, 'harmony.autolinking.etsPackageImport', {
        packageName: record.packageName,
      });
  if (etsImport !== undefined && etsImport !== 'default' && etsImport !== 'named') {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.autolinking.etsPackageImport must be either "default" or "named".', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  const cppClass = optionalMetadataString(metadata, 'cppPackageClassName', record);
  const cmake = optionalMetadataString(metadata, 'cmakeLibraryTargetName', record)
    || defaultCmakeTargetForNpmPackage(record.packageName);
  const rnoh = {
    ohPackageName: name,
    mainHarPath: main,
    harPaths,
    etsPackageClassName: etsClass,
    etsPackageImport: etsImport,
    cppPackageClassName: cppClass,
    cmakeLibraryTargetName: cmake,
  };

  const resolved = resolveRnohMetadata({ packageName: record.packageName, rnoh });
  for (const mapping of resolved.harMappings) {
    if (!isValidOhpmPackageName(mapping.ohPackageName)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `Resolved OH package specifier for ${mapping.harPath} is invalid: ${mapping.ohPackageName}`, {
        packageName: record.packageName,
        stage: 'metadata',
      });
    }
  }

  if (!ArkTsIdentifierPattern.test(resolved.etsPackageClassName)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.autolinking.etsPackageClassName must be a valid ArkTS identifier.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  if (!CppSymbolPattern.test(resolved.cppPackageClassName)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.autolinking.cppPackageClassName contains an invalid C++ class name.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

  if (!CmakeTargetPattern.test(resolved.cmakeLibraryTargetName)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.autolinking.cmakeLibraryTargetName contains an invalid target.', {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }

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

async function createDescriptorFromSearchRecordAsync(record) {
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

  const rnoh = await normalizeRnohMetadataAsync(base);
  const expo = resolveExpoProviderHar(await normalizeExpoMetadataAsync(base), rnoh, base);

  const descriptor = {
    packageName: record.packageName,
    packageVersion: record.packageVersion,
    packageRoot,
    packageLinkPath: link,
    source: record.source,
    expo,
    rnoh,
  };

  if (descriptor.expo.providers.length === 0 && descriptor.rnoh.harPaths.length === 0) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${record.packageName} supports Harmony but declares neither a C++ Provider nor valid RNOH metadata.`, {
      packageName: record.packageName,
      stage: 'metadata',
    });
  }
  return descriptor;
}

export {
  ArkTsIdentifierPattern,
  CmakeTargetPattern,
  CppSymbolPattern,
  createDescriptorFromSearchRecordAsync,
  isValidOhpmPackageName,
  normalizeExpoMetadataAsync,
  normalizeRnohMetadataAsync,
};
