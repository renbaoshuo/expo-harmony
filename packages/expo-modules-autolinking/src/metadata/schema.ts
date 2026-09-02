import * as path from 'node:path';

import { HarmonyAutolinkingError } from '../errors';
import type { HarmonyModuleMetadata, HostMetadata, RnohMetadata } from '../types';
import { normalizeHostMetadata } from './host';
import { isObject, requireNonEmptyString } from '../utilities/values';

const ArkTsIdentifierPattern = /^[A-Za-z_$][A-Za-z0-9_$]*$/;
const CppIdentifierPattern = /^[A-Za-z_][A-Za-z0-9_]*$/;
const CmakeTargetPattern = /^[A-Za-z0-9_.:+-]+$/;
const OhPackagePartPattern = /^[A-Za-z0-9._~-]+$/;

interface MetadataRecord {
  readonly packageName: string;
  readonly packageVersion?: string;
}

type UnknownRecord = Record<string, unknown>;

function metadataError(message: string, record: MetadataRecord): never {
  throw new HarmonyAutolinkingError('INVALID_METADATA', message, {
    packageName: record.packageName,
    stage: 'metadata-normalize',
  });
}

function requireObject(value: unknown, message: string, record: MetadataRecord): UnknownRecord {
  if (!isObject(value)) metadataError(message, record);
  return value as UnknownRecord;
}

function isValidOhpmPackageName(value: unknown): value is string {
  if (typeof value !== 'string' || !value || /[\0\r\n\\'"`;${}()<>\s]/u.test(value)) return false;
  const scoped = value.startsWith('@');
  const parts = scoped ? value.slice(1).split('/') : value.split('/');
  return parts.length === (scoped ? 2 : 1)
    && parts.every(part => part !== '.' && part !== '..' && OhPackagePartPattern.test(part));
}

function normalizeOhPackageName(
  value: unknown,
  record: MetadataRecord
): RnohMetadata['ohPackageName'] {
  if (value === undefined) return undefined;
  if (typeof value === 'string') {
    if (!isValidOhpmPackageName(value)) {
      metadataError('package.json#harmony.autolinking.ohPackageName must be a safe OHPM package name.', record);
    }
    return value;
  }
  if (!Array.isArray(value)) {
    metadataError('package.json#harmony.autolinking.ohPackageName must be a string or HAR mapping array.', record);
  }

  const seen = new Set<string>();
  return value.map((rawMapping, index) => {
    const field = `package.json#harmony.autolinking.ohPackageName[${index}]`;
    const mapping = requireObject(rawMapping, `${field} must be an object.`, record);
    const harName = requireNonEmptyString(mapping.harName, `${field}.harName`, {
      packageName: record.packageName,
      stage: 'metadata-normalize',
    });
    if (path.posix.basename(harName) !== harName
      || path.win32.basename(harName) !== harName
      || path.posix.extname(harName).toLowerCase() !== '.har') {
      metadataError(`${field}.harName must be a HAR filename.`, record);
    }
    if (seen.has(harName)) metadataError(`${field}.harName is declared more than once.`, record);
    seen.add(harName);
    if (!isValidOhpmPackageName(mapping.packageName)) {
      metadataError(`${field}.packageName must be a safe OHPM package name.`, record);
    }
    const version = mapping.version === undefined
      ? undefined
      : requireNonEmptyString(mapping.version, `${field}.version`, {
          packageName: record.packageName,
          stage: 'metadata-normalize',
        });
    return { harName, packageName: mapping.packageName, ...(version ? { version } : {}) };
  });
}

function normalizeArkTsModules(value: unknown, record: MetadataRecord): ReadonlyArray<string> {
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    metadataError('expo-module.config.json#harmony.modules must be an array.', record);
  }

  const seen = new Set<string>();
  const modules = value.map((item, index) => {
    const moduleClass = requireNonEmptyString(
      item,
      `expo-module.config.json#harmony.modules[${index}]`,
      { packageName: record.packageName, stage: 'metadata-normalize' }
    );
    if (!ArkTsIdentifierPattern.test(moduleClass)) {
      metadataError(`expo-module.config.json#harmony.modules[${index}] must be an ArkTS identifier.`, record);
    }
    if (seen.has(moduleClass)) {
      metadataError(`expo-module.config.json#harmony.modules declares ${moduleClass} more than once.`, record);
    }
    seen.add(moduleClass);
    return moduleClass;
  });
  return modules.sort((left, right) => left.localeCompare(right, 'en'));
}

function normalizeHarmonyModuleMetadata(
  harmonyValue: unknown,
  record: MetadataRecord
): HarmonyModuleMetadata {
  const harmony = harmonyValue === undefined
    ? {}
    : requireObject(harmonyValue, 'expo-module.config.json#harmony must be an object.', record);
  const host = normalizeHostMetadata(harmony, record) as unknown as HostMetadata;
  return {
    ...host,
    modules: normalizeArkTsModules(harmony.modules, record),
  };
}

function optionalIdentifier(
  value: unknown,
  field: string,
  pattern: RegExp,
  record: MetadataRecord
): string | undefined {
  if (value === undefined) return undefined;
  const normalized = requireNonEmptyString(value, field, {
    packageName: record.packageName,
    stage: 'metadata-normalize',
  });
  if (!pattern.test(normalized)) metadataError(`${field} is invalid.`, record);
  return normalized;
}

/** Normalizes current RNOH package metadata, independently of Expo module config. */
function normalizeRnohPackageMetadata(
  value: unknown,
  record: MetadataRecord
): Omit<RnohMetadata, 'harPaths'> {
  if (value == null || value === true) return {};
  const rnoh = requireObject(value, 'package.json#harmony.autolinking must be an object.', record);
  const etsPackageImport = rnoh.etsPackageImport;
  if (etsPackageImport !== undefined && etsPackageImport !== 'default' && etsPackageImport !== 'named') {
    metadataError('package.json#harmony.autolinking.etsPackageImport must be "default" or "named".', record);
  }
  return {
    ohPackageName: normalizeOhPackageName(rnoh.ohPackageName, record),
    ...(rnoh.mainHarPath === undefined
      ? {}
      : {
          mainHarPath: requireNonEmptyString(rnoh.mainHarPath, 'package.json#harmony.autolinking.mainHarPath', {
            packageName: record.packageName,
            stage: 'metadata-normalize',
          }),
        }),
    etsPackageClassName: optionalIdentifier(
      rnoh.etsPackageClassName,
      'package.json#harmony.autolinking.etsPackageClassName',
      ArkTsIdentifierPattern,
      record
    ),
    etsPackageImport: etsPackageImport as 'default' | 'named' | undefined,
    cppPackageClassName: optionalIdentifier(
      rnoh.cppPackageClassName,
      'package.json#harmony.autolinking.cppPackageClassName',
      CppIdentifierPattern,
      record
    ),
    cmakeLibraryTargetName: optionalIdentifier(
      rnoh.cmakeLibraryTargetName,
      'package.json#harmony.autolinking.cmakeLibraryTargetName',
      CmakeTargetPattern,
      record
    ),
  };
}

export {
  isValidOhpmPackageName,
  normalizeHarmonyModuleMetadata,
  normalizeRnohPackageMetadata,
};
