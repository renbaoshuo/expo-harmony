import {
  ManagedArtifacts,
  ManifestSchemaVersion,
  Platform,
} from '../../config/constants';
import type { BuildType, Manifest } from '../../types';
import { stringifyJson } from '../../utilities/values';

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
    harmony: {
      modules: [...descriptor.harmony.modules],
    },
    ...(descriptor.arkTs ? { arkTs: { ...descriptor.arkTs } } : {}),
    expo: {
      rootViewComponents: [...descriptor.expo.rootViewComponents],
    },
    rnoh: {
      ...(descriptor.rnoh.ohPackageName !== undefined
        ? { ohPackageName: cloneOhPackageName(descriptor.rnoh.ohPackageName) }
        : {}),
      ...(descriptor.rnoh.mainHarPath ? { mainHarPath: descriptor.rnoh.mainHarPath } : {}),
      harPaths: [...descriptor.rnoh.harPaths],
      ...(descriptor.rnoh.etsPackageClassName ? { etsPackageClassName: descriptor.rnoh.etsPackageClassName } : {}),
      ...(descriptor.rnoh.etsPackageImport ? { etsPackageImport: descriptor.rnoh.etsPackageImport } : {}),
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
