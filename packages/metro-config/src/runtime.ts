/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

import { DefaultReactNativeHarmonyPackage } from './constants';
import { ExpoHarmonyMetroError } from './errors';

export type PathNormalizer = (file: string) => string;

export interface BootstrapModules {
  runtimeInstaller: string;
  initializeCore: string;
  expoWinter: string;
  metroRuntime: string;
}

const HarmonySingletonPackages = [
  '@react-native/assets-registry',
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

    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_FS_ERROR',
      `Failed to inspect ${file}.`,
      { cause }
    );
  }
}

function getPackageRoot(packageName: string, projectRoot: string): string | null {
  try {
    const project = createRequire(path.join(projectRoot, 'package.json'));
    const require = packageName === DefaultReactNativeHarmonyPackage
      ? createRequire(project.resolve('@expo-harmony/expo-modules-core/package.json'))
      : packageName === '@react-native/assets-registry'
        ? createRequire(project.resolve('react-native/package.json'))
        : project;
    return path.dirname(require.resolve(`${packageName}/package.json`));
  } catch (cause) {
    const code = getErrorCode(cause);
    if (code !== 'MODULE_NOT_FOUND' && code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') {
      throw new ExpoHarmonyMetroError(
        'ERR_EXPO_HARMONY_RESOLVE_ERROR',
        `Failed to resolve ${packageName} from ${projectRoot}.`,
        { cause }
      );
    }

    return null;
  }
}

function getMetroRuntimeEntry(projectRoot: string, expoRoot: string | null): string | null {
  const routerRoot = getPackageRoot('expo-router', projectRoot);
  // Match Expo's project, Router, and Expo fallback order for unhoisted peers.
  for (const root of [projectRoot, routerRoot, expoRoot]) {
    if (root === null) continue;
    try {
      return createRequire(path.join(root, 'package.json')).resolve('@expo/metro-runtime');
    } catch (cause) {
      const code = getErrorCode(cause);
      if (code !== 'MODULE_NOT_FOUND' && code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') {
        throw new ExpoHarmonyMetroError(
          'ERR_EXPO_HARMONY_RESOLVE_ERROR', `Failed to resolve @expo/metro-runtime from ${root}.`, { cause }
        );
      }
    }
  }
  return null;
}

export function getHarmonyPackageRoot(harmonyPackage: string, projectRoot: string): string {
  const root = getPackageRoot(harmonyPackage, projectRoot);
  if (!root) {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_MISSING_PEER_DEPENDENCY',
      `Cannot resolve ${harmonyPackage} from the Harmony SDK toolchain in ${projectRoot}.`
    );
  }

  return root;
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
      // Nested dependencies belong to their own package, not to the aliased runtime.
      if (suffix.includes(`${path.sep}node_modules${path.sep}`)) continue;

      return path.join(packageRoot, suffix);
    }

    return file;
  };
}

export function createHarmonyPathNormalizer(harmonyPackage: string, projectRoot: string, reactPackage = 'react'): PathNormalizer {
  const normalizers = [
    createPackagePathNormalizer(harmonyPackage, projectRoot, [harmonyPackage, 'react-native']),
    ...HarmonySingletonPackages.map(packageName => packageName === 'react'
      ? createPackagePathNormalizer(reactPackage, projectRoot, ['react', reactPackage])
      : createPackagePathNormalizer(packageName, projectRoot)),
  ];

  return file => normalizers.reduce((normalized, normalize) => normalize(normalized), file);
}

export function getBootstrapModules(harmonyPackage: string, projectRoot: string): BootstrapModules {
  const harmonyRoot = getPackageRoot(harmonyPackage, projectRoot);
  const coreRoot = getPackageRoot('@expo-harmony/expo-modules-core', projectRoot);
  const expoRoot = getPackageRoot('expo', projectRoot);
  const metroRuntime = getMetroRuntimeEntry(projectRoot, expoRoot);
  const packages: [string, string | null][] = [
    [harmonyPackage, harmonyRoot],
    ['@expo-harmony/expo-modules-core', coreRoot],
    ['expo', expoRoot],
    ['@expo/metro-runtime', metroRuntime],
  ];
  const missingPackage = packages.find(([, root]) => root === null);
  if (missingPackage) {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_MISSING_BOOTSTRAP',
      `@expo-harmony/metro-config cannot compose the Harmony bootstrap because `
      + `${missingPackage[0]} is not resolvable from ${projectRoot}.`
    );
  }

  const files = {
    runtimeInstaller: path.join(coreRoot!, 'install-runtime.js'),
    initializeCore: path.join(harmonyRoot!, 'Libraries/Core/InitializeCore.js'),
    expoWinter: path.join(expoRoot!, 'src/winter/index.ts'),
    metroRuntime: metroRuntime!,
  };
  const missingFile = Object.entries(files).find(([, file]) => !isFile(file));
  if (missingFile) {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_MISSING_BOOTSTRAP',
      `@expo-harmony/metro-config cannot compose the Harmony bootstrap because `
      + `${missingFile[0]} is missing at ${missingFile[1]}.`
    );
  }

  return files;
}
