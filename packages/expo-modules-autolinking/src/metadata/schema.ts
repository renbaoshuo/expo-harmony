/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

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

function requireObject(value: unknown, message: string, record: MetadataRecord): UnknownRecord {
  if (!isObject(value)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', message, {
      packageName: record.packageName,
      stage: 'metadata-normalize',
    });
  }

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
      throw new HarmonyAutolinkingError('INVALID_METADATA', 'package.json#harmony.autolinking.ohPackageName must be a safe OHPM package name.', {
        packageName: record.packageName,
        stage: 'metadata-normalize',
      });
    }
    return value;
  }
  if (!Array.isArray(value)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'package.json#harmony.autolinking.ohPackageName must be a string or HAR mapping array.', {
      packageName: record.packageName,
      stage: 'metadata-normalize',
    });
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
      throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.harName must be a HAR filename.`, {
        packageName: record.packageName,
        stage: 'metadata-normalize',
      });
    }
    if (seen.has(harName)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.harName is declared more than once.`, {
        packageName: record.packageName,
        stage: 'metadata-normalize',
      });
    }

    seen.add(harName);
    if (!isValidOhpmPackageName(mapping.packageName)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `${field}.packageName must be a safe OHPM package name.`, {
        packageName: record.packageName,
        stage: 'metadata-normalize',
      });
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

function normalizeArkTsDeclarations(value: unknown, field: string, record: MetadataRecord): ReadonlyArray<string> {
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `expo-module.config.json#harmony.${field} must be an array.`, { packageName: record.packageName, stage: 'metadata-normalize' });
  }

  const seen = new Set<string>();
  const names = value.map((item, index) => {
    const name = requireNonEmptyString(
      item,
      `expo-module.config.json#harmony.${field}[${index}]`,
      { packageName: record.packageName, stage: 'metadata-normalize' }
    );
    if (!ArkTsIdentifierPattern.test(name)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `expo-module.config.json#harmony.${field}[${index}] must be an ArkTS identifier.`, { packageName: record.packageName, stage: 'metadata-normalize' });
    }
    if (seen.has(name)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `expo-module.config.json#harmony.${field} declares ${name} more than once.`, { packageName: record.packageName, stage: 'metadata-normalize' });
    }
    seen.add(name);
    return name;
  });
  return field === 'services' ? names : names.sort((left, right) => left.localeCompare(right, 'en'));
}

function normalizeHarmonyModuleMetadata(
  harmonyValue: unknown,
  record: MetadataRecord
): HarmonyModuleMetadata {
  const harmony = harmonyValue === undefined
    ? {}
    : requireObject(harmonyValue, 'expo-module.config.json#harmony must be an object.', record);
  const host = normalizeHostMetadata(harmony, record) as unknown as HostMetadata;
  const buildOptionsFile = harmony.buildOptionsFile;
  if (buildOptionsFile !== undefined && (typeof buildOptionsFile !== 'string'
    || !/^[A-Za-z0-9_-]+\.json$/u.test(buildOptionsFile))) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'harmony.buildOptionsFile must name a JSON file in the Harmony source project.', {
      packageName: record.packageName,
      stage: 'metadata-normalize',
    });
  }

  return {
    ...host,
    ...(buildOptionsFile ? { buildOptionsFile: buildOptionsFile as string } : {}),
    modules: normalizeArkTsDeclarations(harmony.modules, 'modules', record),
    services: normalizeArkTsDeclarations(harmony.services, 'services', record),
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
  if (!pattern.test(normalized)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `${field} is invalid.`, {
      packageName: record.packageName,
      stage: 'metadata-normalize',
    });
  }

  return normalized;
}

function normalizeRnohPackageMetadata(
  value: unknown,
  record: MetadataRecord
): Omit<RnohMetadata, 'harPaths'> {
  if (value == null || value === true) return {};
  const rnoh = requireObject(value, 'package.json#harmony.autolinking must be an object.', record);
  const etsPackageImport = rnoh.etsPackageImport;
  if (etsPackageImport !== undefined && etsPackageImport !== 'default' && etsPackageImport !== 'named') {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'package.json#harmony.autolinking.etsPackageImport must be "default" or "named".', {
      packageName: record.packageName,
      stage: 'metadata-normalize',
    });
  }

  const etsPackageScope = rnoh.etsPackageScope;
  if (etsPackageScope !== undefined && etsPackageScope !== 'shared' && etsPackageScope !== 'ui' && etsPackageScope !== 'host') {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'package.json#harmony.autolinking.etsPackageScope must be "shared", "ui", or "host".', {
      packageName: record.packageName,
      stage: 'metadata-normalize',
    });
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
    etsPackageScope: etsPackageScope as RnohMetadata['etsPackageScope'],
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
