/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ManagedArtifacts,
  ManifestSchemaVersion,
  Platform,
} from '../../config/constants';
import type { BuildType, Manifest } from '../../types';
import { stringifyJson } from '../../utilities/values';
import { HostMetadataFields } from '../../metadata/host';

function cloneOhPackageName(value) {
  if (Array.isArray(value)) return value.map(mapping => ({ ...mapping }));
  return value;
}

function createManifestEntry(descriptor) {
  return {
    packageName: descriptor.packageName,
    packageVersion: descriptor.packageVersion,
    packageRoot: descriptor.packageRoot,
    packageLinkPath: descriptor.packageLinkPath,
    source: descriptor.source,
    ...(descriptor.inlineModules ? { inlineModules: structuredClone(descriptor.inlineModules) } : {}),
    harmony: {
      modules: [...descriptor.harmony.modules],
      services: [...descriptor.harmony.services],
    },
    ...(descriptor.arkTs ? { arkTs: { ...descriptor.arkTs } } : {}),
    expo: Object.fromEntries(HostMetadataFields.map(field => [field, [...descriptor.expo[field]]])),
    rnoh: {
      ...(descriptor.rnoh.ohPackageName !== undefined
        ? { ohPackageName: cloneOhPackageName(descriptor.rnoh.ohPackageName) }
        : {}),
      ...(descriptor.rnoh.mainHarPath ? { mainHarPath: descriptor.rnoh.mainHarPath } : {}),
      harPaths: [...descriptor.rnoh.harPaths],
      ...(descriptor.rnoh.etsPackageClassName ? { etsPackageClassName: descriptor.rnoh.etsPackageClassName } : {}),
      ...(descriptor.rnoh.etsPackageImport ? { etsPackageImport: descriptor.rnoh.etsPackageImport } : {}),
      ...(descriptor.rnoh.etsPackageScope ? { etsPackageScope: descriptor.rnoh.etsPackageScope } : {}),
      ...(descriptor.rnoh.cppPackageClassName ? { cppPackageClassName: descriptor.rnoh.cppPackageClassName } : {}),
      ...(descriptor.rnoh.cmakeLibraryTargetName
        ? { cmakeLibraryTargetName: descriptor.rnoh.cmakeLibraryTargetName }
        : {}),
    },
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function createManifest(modules, options: Record<string, any> = {}): Manifest {
  const buildType: BuildType = options.buildType || 'debug';

  return {
    schemaVersion: ManifestSchemaVersion,
    platform: Platform,
    buildType,
    ...(options.runtimeModules ? { runtimeModules: options.runtimeModules } : {}),
    modules: modules.map(descriptor => createManifestEntry(descriptor)),
    managedArtifacts: [...(options.managedArtifacts || ManagedArtifacts)],
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function serializeManifest(modules, options: Record<string, any> = {}) {
  return stringifyJson(createManifest(modules, options));
}

export {
  createManifest,
  serializeManifest,
};
