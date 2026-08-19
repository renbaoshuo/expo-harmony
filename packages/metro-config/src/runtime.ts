import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { HarmonyMetroError } from './errors';

export type PathNormalizer = (file: string) => string;

export interface BootstrapModules {
  runtimeInstaller: string;
  initializeCore: string;
  expoWinter: string;
  metroRuntime: string;
}

const localRequire = createRequire(__filename);
const HarmonySingletonPackages = [
  '@expo/metro-runtime',
  'expo',
  'expo-modules-core',
  'expo-router',
  'react',
  'react-dom',
] as const;

function getErrorCode(cause: unknown): unknown {
  return cause && typeof cause === 'object' && 'code' in cause ? cause.code : undefined;
}

function isFile(file: string): boolean {
  try {
    return fs.statSync(file).isFile();
  } catch (cause) {
    const code = getErrorCode(cause);
    if (code === 'ENOENT' || code === 'ENOTDIR') return false;

    throw new Error(`Failed to inspect ${file}.`, { cause });
  }
}

function getPackageRoot(packageName: string, projectRoot: string): string | null {
  try {
    return path.dirname(localRequire.resolve(`${packageName}/package.json`, { paths: [projectRoot] }));
  } catch (cause) {
    const code = getErrorCode(cause);
    if (code !== 'MODULE_NOT_FOUND' && code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') {
      throw new Error(`Failed to resolve ${packageName} from ${projectRoot}.`, { cause });
    }

    return null;
  }
}

function createPackagePathNormalizer(
  packageName: string,
  projectRoot: string,
  aliases: readonly string[] = [packageName]
): PathNormalizer {
  const packageRoot = getPackageRoot(packageName, projectRoot);
  if (!packageRoot) return file => file;

  const markers = [...new Set(aliases)].map(candidate => `${path.sep}node_modules${path.sep}${candidate.replaceAll('/', path.sep)}`);
  return function normalizePackagePath(file) {
    if (!path.isAbsolute(file)) return file;

    for (const marker of markers) {
      const markerIndex = file.lastIndexOf(marker);
      if (markerIndex < 0) continue;
      const suffix = file.slice(markerIndex + marker.length);
      if (suffix.length > 0 && !suffix.startsWith(path.sep)) continue;

      return path.join(packageRoot, suffix);
    }

    return file;
  };
}

export function createHarmonyPathNormalizer(harmonyPackage: string, projectRoot: string): PathNormalizer {
  const normalizers = [
    createPackagePathNormalizer(harmonyPackage, projectRoot, [harmonyPackage, 'react-native']),
    ...HarmonySingletonPackages.map(packageName => createPackagePathNormalizer(packageName, projectRoot)),
  ];

  return file => normalizers.reduce((normalized, normalize) => normalize(normalized), file);
}

export function getBootstrapModules(harmonyPackage: string, projectRoot: string): BootstrapModules {
  const reactNativeHarmonyRoot = getPackageRoot(harmonyPackage, projectRoot);
  const expoModulesCoreRoot = getPackageRoot('@expo-harmony/expo-modules-core', projectRoot);
  const expoRoot = getPackageRoot('expo', projectRoot);
  const metroRuntimeRoot = getPackageRoot('@expo/metro-runtime', projectRoot);
  const packages: [string, string | null][] = [
    [harmonyPackage, reactNativeHarmonyRoot],
    ['@expo-harmony/expo-modules-core', expoModulesCoreRoot],
    ['expo', expoRoot],
    ['@expo/metro-runtime', metroRuntimeRoot],
  ];
  const missingPackage = packages.find(([, root]) => root === null);
  if (missingPackage) {
    throw new HarmonyMetroError(
      'ERR_EXPO_HARMONY_MISSING_BOOTSTRAP',
      `@expo-harmony/metro-config cannot compose the Harmony bootstrap because `
      + `${missingPackage[0]} is not resolvable from ${projectRoot}.`
    );
  }

  const files = {
    runtimeInstaller: path.join(expoModulesCoreRoot!, 'install-runtime.js'),
    initializeCore: path.join(reactNativeHarmonyRoot!, 'Libraries/Core/InitializeCore.js'),
    expoWinter: path.join(expoRoot!, 'src/winter/index.ts'),
    metroRuntime: path.join(metroRuntimeRoot!, 'src/index.ts'),
  };
  const missingFile = Object.entries(files).find(([, file]) => !isFile(file));
  if (missingFile) {
    throw new HarmonyMetroError(
      'ERR_EXPO_HARMONY_MISSING_BOOTSTRAP',
      `@expo-harmony/metro-config cannot compose the Harmony bootstrap because `
      + `${missingFile[0]} is missing at ${missingFile[1]}.`
    );
  }

  return files;
}
