import { createRequire } from 'node:module';
import path from 'node:path';

import type { InputConfigT } from 'metro-config';

import { DefaultReactNativeHarmonyPackage } from './constants';
import {
  createWithHarmonyConfig,
  type CreateHarmonyMetroConfig,
  type MergeConfig,
  type WithHarmonyConfigOptions,
} from './createWithHarmonyConfig';
import { ExpoHarmonyMetroError } from './errors';

interface MetroConfigPeer {
  mergeConfig?: MergeConfig;
}

interface HarmonyMetroConfigPeer {
  createHarmonyMetroConfig?: CreateHarmonyMetroConfig;
}

type WithHarmonyConfig = ReturnType<typeof createWithHarmonyConfig>;

const Implementations = new Map<string, WithHarmonyConfig>();

function loadPeer<T>(projectRequire: NodeRequire, moduleName: string): T {
  try {
    return projectRequire(moduleName) as T;
  } catch (cause) {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_MISSING_PEER_DEPENDENCY',
      `@expo-harmony/metro-config could not load its peer dependency "${moduleName}". `
      + 'Install it in the app that owns the Metro configuration.',
      { cause }
    );
  }
}

function getPeerVersion(projectRequire: NodeRequire, packageName: string): string {
  try {
    const manifest = projectRequire(`${packageName}/package.json`) as { version?: unknown };
    return typeof manifest.version === 'string' ? manifest.version : 'unknown';
  } catch {
    return 'unknown';
  }
}

function getImplementation(projectRoot: string, harmonyPackage: string): WithHarmonyConfig {
  const key = `${projectRoot}\0${harmonyPackage}`;
  const cached = Implementations.get(key);
  if (cached) return cached;

  const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
  const metro = loadPeer<MetroConfigPeer>(projectRequire, 'metro-config');
  const harmony = loadPeer<HarmonyMetroConfigPeer>(projectRequire, `${harmonyPackage}/metro.config`);

  if (typeof metro.mergeConfig !== 'function') {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_INCOMPATIBLE_PEER_DEPENDENCY',
      '@expo-harmony/metro-config requires metro-config to expose mergeConfig(); '
      + `the project resolved version ${getPeerVersion(projectRequire, 'metro-config')}.`
    );
  }
  if (typeof harmony.createHarmonyMetroConfig !== 'function') {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_INCOMPATIBLE_PEER_DEPENDENCY',
      `@expo-harmony/metro-config requires ${harmonyPackage} to expose `
      + 'the /metro.config createHarmonyMetroConfig() export; '
      + `the project resolved version ${getPeerVersion(projectRequire, harmonyPackage)}.`
    );
  }

  const implementation = createWithHarmonyConfig({
    createHarmonyMetroConfig: harmony.createHarmonyMetroConfig,
    mergeConfig: metro.mergeConfig,
  });
  Implementations.set(key, implementation);

  return implementation;
}

/**
 * 将 Expo Metro 配置与 RNOH 配置组合。options.enabled 为 false 时原样
 * 返回 config，且不会加载 RNOH 和 metro-config peer dependencies。
 */
export function withHarmonyConfig<T extends InputConfigT>(
  config: T,
  options: WithHarmonyConfigOptions = {}
): T & InputConfigT {
  if (options.enabled === false) return config;

  const projectRoot = path.resolve(options.projectRoot ?? config.projectRoot ?? process.cwd());
  const harmonyPackage = options.reactNativeHarmonyPackageName ?? DefaultReactNativeHarmonyPackage;

  return getImplementation(projectRoot, harmonyPackage)(config, { ...options, projectRoot });
}
