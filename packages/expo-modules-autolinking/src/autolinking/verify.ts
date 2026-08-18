import fs from 'node:fs';
import path from 'node:path';

import type { VerificationResult, VerifyOptions } from '../types';
import { HarmonyAutolinkingError } from '../errors';
import { HostMetadataFields } from '../metadata/host';
import { createDescriptorFromSearchRecordAsync } from '../metadata/descriptor';
import { providerAlias } from '../harmony/providers/names';
import { searchModulesAsync } from './search';
import { compareModuleDescriptors } from './resolve';
import { resolveRnohMetadata } from '../harmony/rnoh/packageMetadata';
import { compareText, emitLog, isObject, resolvePackageFromProject, sortedUniqueStrings } from '../utilities/values';

function diagnosticFromError(error, fallback) {
  const normalized = error instanceof HarmonyAutolinkingError
    ? error
    : new HarmonyAutolinkingError('INVALID_METADATA', error.message || String(error), { cause: error, packageName: fallback, stage: 'verify' });

  return {
    severity: 'error',
    code: normalized.code,
    message: normalized.message,
    ...(normalized.packageName || fallback ? { packageName: normalized.packageName || fallback } : {}),
    stage: normalized.stage,
  };
}

function compareDiagnostics(left, right) {
  const order = { error: 0, warning: 1 };

  return (order[left.severity] - order[right.severity])
    || compareText(left.code, right.code)
    || compareText(left.packageName || '', right.packageName || '')
    || compareText(left.message, right.message)
    || compareText(JSON.stringify(left.sources || []), JSON.stringify(right.sources || []));
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function diagnosticSource(descriptor, extra: Record<string, any> = {}) {
  return {
    packageName: descriptor.packageName,
    packageVersion: descriptor.packageVersion,
    packageRoot: descriptor.packageRoot,
    ...extra,
  };
}

function conflictDiagnostic(code, label, value, entries, packageName?: string, severity = 'error') {
  return {
    severity,
    code: `ERR_EXPO_HARMONY_${code}`,
    message: `${label} "${value}" is declared more than once.`,
    packageName,
    stage: 'verify',
    sources: entries.map(entry => entry.source).sort((left, right) => {
      return compareText(left.packageName, right.packageName)
        || compareText(left.packageRoot, right.packageRoot)
        || compareText(left.field || '', right.field || '');
    }),
  };
}

function collectDescriptorConflicts(descriptors) {
  const diagnostics = [];
  const packages = new Map();
  const ids = new Map();
  const classes = new Map();
  const aliases = new Map();
  const idCase = new Map();
  const headerCase = new Map();
  const oh = new Map();
  const ohCase = new Map();
  const ets = new Map();
  const etsCase = new Map();
  const cpp = new Map();
  const cppCase = new Map();
  const cmake = new Map();
  const cmakeCase = new Map();

  function push(map, key, source, value = key) {
    const entries = map.get(key) || [];
    entries.push({ value, source });
    map.set(key, entries);
  }

  for (const descriptor of descriptors) {
    push(packages, descriptor.packageName, diagnosticSource(descriptor));
    for (const provider of descriptor.expo.providers) {
      const source = diagnosticSource(descriptor, { field: `provider:${provider.identifier}` });
      push(ids, provider.identifier, source);
      push(idCase, provider.identifier.toLowerCase(), source, provider.identifier);
      push(classes, provider.className, source);
      push(aliases, providerAlias(provider), source);
      push(headerCase, provider.header.toLowerCase(), source, provider.header);
      push(cmake, provider.cmakeTargetName, source);
      push(cmakeCase, provider.cmakeTargetName.toLowerCase(), source, provider.cmakeTargetName);
    }

    if (descriptor.expo.providerHar) {
      push(oh, descriptor.expo.providerHar.ohPackageName, diagnosticSource(descriptor, {
        field: `providerHar:${descriptor.expo.providerHar.harPath}`,
      }), `${descriptor.packageRoot}\0${descriptor.expo.providerHar.harPath}`);
      push(ohCase, descriptor.expo.providerHar.ohPackageName.toLowerCase(), diagnosticSource(descriptor, {
        field: `providerHar:${descriptor.expo.providerHar.harPath}`,
      }), descriptor.expo.providerHar.ohPackageName);
    }

    if (descriptor.rnoh.harPaths.length > 0) {
      const rnohMetadata = resolveRnohMetadata(descriptor);
      for (const mapping of rnohMetadata.harMappings) {
        push(oh, mapping.ohPackageName, diagnosticSource(descriptor, {
          field: `HAR:${mapping.harPath}`,
        }), `${descriptor.packageRoot}\0${mapping.harPath}`);
        push(ohCase, mapping.ohPackageName.toLowerCase(), diagnosticSource(descriptor, {
          field: `HAR:${mapping.harPath}`,
        }), mapping.ohPackageName);
      }
      push(ets, rnohMetadata.etsPackageClassName, diagnosticSource(descriptor, { field: 'etsPackageClassName' }));
      push(etsCase, rnohMetadata.etsPackageClassName.toLowerCase(), diagnosticSource(descriptor, { field: 'etsPackageClassName' }), rnohMetadata.etsPackageClassName);
      push(cpp, rnohMetadata.cppPackageClassName, diagnosticSource(descriptor, { field: 'cppPackageClassName' }));
      push(cppCase, rnohMetadata.cppPackageClassName.toLowerCase(), diagnosticSource(descriptor, { field: 'cppPackageClassName' }), rnohMetadata.cppPackageClassName);
      push(cmake, rnohMetadata.cmakeLibraryTargetName, diagnosticSource(descriptor, { field: 'cmakeLibraryTargetName' }));
      push(cmakeCase, rnohMetadata.cmakeLibraryTargetName.toLowerCase(), diagnosticSource(descriptor, { field: 'cmakeLibraryTargetName' }), rnohMetadata.cmakeLibraryTargetName);
    }
  }

  for (const [packageName, entries] of packages) {
    const revisions = new Set(entries.map(entry => `${entry.source.packageVersion}\0${entry.source.packageRoot}`));
    if (revisions.size > 1) {
      diagnostics.push(conflictDiagnostic(
        'DUPLICATE_MODULE',
        'npm package',
        packageName,
        entries,
        packageName
      ));
    }
  }

  for (const [value, entries] of ids) {
    if (entries.length > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_PROVIDER', 'Provider identifier', value, entries));
    }
  }

  for (const [value, entries] of classes) {
    if (entries.length > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_PROVIDER', 'Provider C++ class', value, entries));
    }
  }

  for (const [value, entries] of aliases) {
    if (entries.length > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_PROVIDER', 'generated Provider alias', value, entries));
    }
  }

  for (const [value, entries] of idCase) {
    if (new Set(entries.map(entry => entry.value)).size > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_PROVIDER', 'case-folded Provider identifier', value, entries));
    }
  }

  for (const [value, entries] of headerCase) {
    if (new Set(entries.map(entry => entry.value)).size > 1
      || new Set(entries.map(entry => entry.source.packageRoot)).size > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_PROVIDER', 'case-folded Provider header', value, entries));
    }
  }

  for (const [value, entries] of oh) {
    if (new Set(entries.map(entry => entry.value)).size > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_MODULE', 'OH package', value, entries));
    }
  }

  for (const [value, entries] of ohCase) {
    if (new Set(entries.map(entry => entry.value)).size > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_MODULE', 'case-folded OH package', value, entries));
    }
  }

  for (const [value, entries] of ets) {
    if (new Set(entries.map(entry => entry.source.packageRoot)).size > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_MODULE', 'ETS Package class', value, entries));
    }
  }

  for (const [value, entries] of cpp) {
    if (new Set(entries.map(entry => entry.source.packageRoot)).size > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_MODULE', 'C++ Package class', value, entries));
    }
  }

  for (const [value, entries] of cmake) {
    if (new Set(entries.map(entry => entry.source.packageRoot)).size > 1) {
      diagnostics.push(conflictDiagnostic('DUPLICATE_MODULE', 'CMake target', value, entries));
    }
  }

  for (const [label, values] of [
    ['case-folded ETS Package class', etsCase],
    ['case-folded C++ Package class', cppCase],
    ['case-folded CMake target', cmakeCase],
  ]) {
    for (const [value, entries] of values) {
      if (new Set(entries.map(entry => entry.value)).size > 1) {
        diagnostics.push(conflictDiagnostic('DUPLICATE_MODULE', label, value, entries));
      }
    }
  }
  return diagnostics;
}

function normalizeDescriptorHarPaths(descriptor) {
  if (!Array.isArray(descriptor.rnoh.harPaths)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'descriptor.rnoh.harPaths must be an array.', {
      packageName: descriptor.packageName,
      stage: 'verify',
    });
  }

  const harPaths = descriptor.rnoh.harPaths.map((harPath, index) => {
    if (typeof harPath !== 'string' || !harPath.trim() || harPath.includes('\0')
      || path.win32.isAbsolute(harPath)) {
      throw new HarmonyAutolinkingError(
        'INVALID_METADATA',
        `descriptor.rnoh.harPaths[${index}] must be a non-empty package-relative HAR path.`,
        { packageName: descriptor.packageName, stage: 'verify' }
      );
    }
    const normalized = path.posix.normalize(harPath.replace(/\\/g, '/'));
    if (path.posix.isAbsolute(normalized) || normalized === '..' || normalized.startsWith('../')
      || path.posix.extname(normalized) !== '.har') {
      throw new HarmonyAutolinkingError(
        'INVALID_METADATA',
        `descriptor.rnoh.harPaths[${index}] must be a package-relative .har file.`,
        { packageName: descriptor.packageName, stage: 'verify' }
      );
    }
    return normalized;
  });

  return sortedUniqueStrings(harPaths);
}

function harRoot(harPaths) {
  const directories = harPaths.map(harPath => path.posix.dirname(harPath).split('/'));
  const common = [];

  for (let index = 0; index < directories[0].length; index += 1) {
    const segment = directories[0][index];
    if (directories.every(parts => parts[index] === segment)) common.push(segment);
    else break;
  }
  return common.length === 0 ? '.' : common.join('/');
}

function searchRecordFromDescriptor(descriptor, declared) {
  if (!isObject(descriptor)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'Harmony module descriptor must be an object.', {
      stage: 'verify',
    });
  }
  if (!isObject(descriptor.expo) || !Array.isArray(descriptor.expo.providers)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'descriptor.expo.providers must be an array.', {
      packageName: descriptor.packageName,
      stage: 'verify',
    });
  }
  if ('anchorHeader' in descriptor.expo || 'anchorSymbol' in descriptor.expo) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'descriptor.expo uses the unsupported anchor registration contract.', {
      packageName: descriptor.packageName,
      stage: 'verify',
    });
  }
  if (!isObject(descriptor.rnoh)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'descriptor.rnoh must be an object.', {
      packageName: descriptor.packageName,
      stage: 'verify',
    });
  }

  const host = HostMetadataFields.some(field => descriptor.expo[field]?.length > 0);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rnoh: Record<string, any> = {};
  if (descriptor.rnoh.ohPackageName !== undefined) {
    rnoh.ohPackageName = Array.isArray(descriptor.rnoh.ohPackageName)
      ? descriptor.rnoh.ohPackageName.map(mapping => ({ ...mapping }))
      : descriptor.rnoh.ohPackageName;
  }
  if (descriptor.rnoh.mainHarPath !== undefined) rnoh.mainHarPath = descriptor.rnoh.mainHarPath;
  else if (declared.length > 0) rnoh.mainHarPath = harRoot(declared);
  if (descriptor.rnoh.etsPackageImport !== undefined) {
    rnoh.etsPackageImport = descriptor.rnoh.etsPackageImport;
  }
  if (descriptor.rnoh.etsPackageClassName !== undefined) {
    rnoh.etsPackageClassName = descriptor.rnoh.etsPackageClassName;
  }
  if (descriptor.rnoh.cppPackageClassName !== undefined) {
    rnoh.cppPackageClassName = descriptor.rnoh.cppPackageClassName;
  }
  if (descriptor.rnoh.cmakeLibraryTargetName !== undefined) {
    rnoh.cmakeLibraryTargetName = descriptor.rnoh.cmakeLibraryTargetName;
  }

  return {
    packageName: descriptor.packageName,
    packageVersion: descriptor.packageVersion,
    packageRoot: descriptor.packageRoot,
    source: descriptor.source,
    supportsHarmony: descriptor.expo.providers.length > 0 || host,
    expoModuleConfig: descriptor.expo.providers.length > 0 || host
      ? {
          platforms: ['harmony'],
          harmony: {
            ...Object.fromEntries(HostMetadataFields.map(field => [
              field,
              [...(descriptor.expo[field] || [])],
            ])),
            ...(descriptor.expo.providerHar
              ? {
                  providerHar: {
                    ...descriptor.expo.providerHar,
                    harPath: String(descriptor.expo.providerHar.harPath).replace(/\\/g, '/'),
                  },
                }
              : {}),
            providers: descriptor.expo.providers,
          },
        }
      : null,
    rnohMetadata: Object.keys(rnoh).length > 0 ? rnoh : null,
    revision: {
      originPath: descriptor.packageLinkPath || descriptor.packageRoot,
    },
  };
}

async function validateDescriptorAsync(descriptor) {
  if (!isObject(descriptor) || !isObject(descriptor.rnoh)) {
    return createDescriptorFromSearchRecordAsync(searchRecordFromDescriptor(descriptor, []));
  }

  const declared = normalizeDescriptorHarPaths(descriptor);
  const normalized = await createDescriptorFromSearchRecordAsync(
    searchRecordFromDescriptor(descriptor, declared)
  );

  if (normalized.rnoh.harPaths.length !== declared.length
    || normalized.rnoh.harPaths.some((harPath, index) => harPath !== declared[index])) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'descriptor.rnoh.harPaths must exactly list the HAR files selected by descriptor.rnoh.mainHarPath.', {
      packageName: descriptor.packageName,
      stage: 'verify',
      details: { declared, discovered: normalized.rnoh.harPaths },
    });
  }

  const packageRoot = await fs.promises.realpath(descriptor.packageRoot);
  if (packageRoot !== descriptor.packageRoot) {
    normalized.packageRoot = packageRoot;
  }
  return normalized;
}

async function verifyModulesAsync(options: VerifyOptions = {}): Promise<VerificationResult> {
  let searchResult = options.searchResult;
  const inputs = options.modules;

  if (inputs !== undefined && !Array.isArray(inputs)) {
    throw new HarmonyAutolinkingError('INVALID_OPTIONS', 'modules must be an array when provided.', { stage: 'verify' });
  }
  if (!searchResult && inputs === undefined) {
    const runtime = [
      '@react-native-oh/react-native-harmony',
      'react-native',
      'react-native-tvos',
    ].filter((packageName) => {
      try {
        resolvePackageFromProject(
          options.projectRoot || process.cwd(),
          `${packageName}/package.json`
        );
        return true;
      } catch (_cause) {
        return false;
      }
    });
    searchResult = await searchModulesAsync({
      ...options,
      include: [...(options.include || []), ...runtime],
      includeReactNativeProjectConfig: true,
    } as VerifyOptions & { includeReactNativeProjectConfig: true });
  }

  const descriptors = [];
  const diagnostics = [];

  if (inputs !== undefined) {
    for (const input of inputs) {
      try {
        descriptors.push(await validateDescriptorAsync(input));
      } catch (error) {
        diagnostics.push(diagnosticFromError(error, input?.packageName));
      }
    }
  } else {
    const records = [...searchResult.modules].sort((left, right) => {
      return compareText(left.packageName, right.packageName)
        || compareText(left.packageVersion, right.packageVersion)
        || compareText(left.packageRoot, right.packageRoot);
    });
    for (const record of records) {
      try {
        descriptors.push(await createDescriptorFromSearchRecordAsync(record));
      } catch (error) {
        diagnostics.push(diagnosticFromError(error, record.packageName));
      }
    }
    for (const packageName of sortedUniqueStrings(searchResult.missingIncludes || [])) {
      diagnostics.push({
        severity: 'warning',
        code: 'ERR_EXPO_HARMONY_INCLUDED_MODULE_NOT_FOUND',
        message: `Included package "${packageName}" was not found.`,
        packageName,
        stage: 'verify',
      });
    }
  }

  descriptors.sort(compareModuleDescriptors);
  diagnostics.push(...collectDescriptorConflicts(descriptors));

  if (searchResult) {
    const seen = new Map();
    for (const descriptor of descriptors) {
      const set = seen.get(descriptor.packageName) || new Set();
      set.add(`${descriptor.packageVersion}\0${descriptor.packageRoot}`);
      seen.set(descriptor.packageName, set);
    }
    for (const duplicate of searchResult.duplicates || []) {
      const list = [...new Map(duplicate.revisions.map(revision => [
        `${revision.version}\0${revision.path}`, revision,
      ])).values()] as Array<{ version: string; path: string }>;
      if (list.length < 2 || (seen.get(duplicate.packageName)?.size || 0) >= list.length) {
        continue;
      }
      diagnostics.push(conflictDiagnostic(
        'DUPLICATE_MODULE',
        'npm package',
        duplicate.packageName,
        list.map(revision => ({
          source: {
            packageName: duplicate.packageName,
            packageVersion: revision.version,
            packageRoot: revision.path,
          },
        })),
        duplicate.packageName,
        'warning'
      ));
    }
  }

  diagnostics.sort(compareDiagnostics);
  const result = {
    valid: diagnostics.every(diagnostic => diagnostic.severity !== 'error'),
    diagnostics,
    modules: descriptors,
  };

  emitLog(options.logger, result.valid ? 'debug' : 'warn', 'Harmony module verification completed.', {
    valid: result.valid,
    diagnosticCount: diagnostics.length,
    moduleCount: descriptors.length,
  });
  return result;
}

function assertVerificationSucceeded(result, stage = 'verify') {
  if (result.valid) return;

  const first = result.diagnostics.find(diagnostic => diagnostic.severity === 'error');
  throw new HarmonyAutolinkingError(first?.code || 'INVALID_METADATA', 'Harmony module verification failed.', {
    diagnostics: result.diagnostics,
    packageName: first?.packageName,
    stage,
  });
}

export {
  compareDiagnostics,
  assertVerificationSucceeded,
  verifyModulesAsync,
};
