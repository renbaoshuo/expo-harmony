import { createRequire } from 'node:module';
import path from 'node:path';

import type { InputConfigT } from 'metro-config';

import { DefaultReactNativeHarmonyPackage, HarmonyPlatform } from './constants';
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

interface AutolinkingPlatformsModule {
  getSupportPackageForPlatform?: (platform: string) => string | null;
}

type WithHarmonyConfig = ReturnType<typeof createWithHarmonyConfig>;

const Implementations = new Map<string, WithHarmonyConfig>();
const PatchedProjects = new Set<string>();

/**
 * Expo CLI 的多平台 Metro resolver 在为每个平台解析模块时，都会向
 * expo-modules-autolinking 查询该平台的 react-native「支持包」
 * （getReactNativeHostPackage -> getSupportPackageForPlatform）。上游只认识
 * ios/android/tvos/macos/windows，遇到其它平台会直接抛错，从而让 harmony
 * bundle 构建失败（"No support package is known for platform \"harmony\""）。
 *
 * Expo CLI 在同一个进程中加载 metro.config.js，因此在配置加载阶段补上
 * harmony 分支即可。在 RNOH resolver 中 react-native 会被重定向到 RNOH，
 * 所以这里返回 RNOH 运行时包，使 Expo 的 react-native 内部改写（HMR、LogBox）
 * 能按 node_modules/@react-native-oh/react-native-harmony 的真实路径命中。
 */
function patchAutolinkingHarmonySupportPackage(projectRoot: string): void {
  if (PatchedProjects.has(projectRoot)) return;
  PatchedProjects.add(projectRoot);

  let platforms: AutolinkingPlatformsModule;
  try {
    const projectRequire = createRequire(path.join(projectRoot, 'package.json'));
    const expoRequire = createRequire(projectRequire.resolve('expo/package.json'));
    platforms = expoRequire('expo-modules-autolinking/build/platforms') as AutolinkingPlatformsModule;
  } catch {
    // expo-modules-autolinking 是 Expo CLI 的实现细节；无法按此路径解析时跳过，
    // 后续若仍触发该错误说明上游结构已变化。
    return;
  }

  const original = platforms.getSupportPackageForPlatform;
  if (typeof original !== 'function') return;

  try {
    original(HarmonyPlatform);
    // 上游已经认识 harmony（未来版本），无需补丁。
    return;
  } catch {
    // 上游对 harmony 抛错，补上 harmony 分支。
  }

  platforms.getSupportPackageForPlatform = (platform: string) => platform === HarmonyPlatform
    ? DefaultReactNativeHarmonyPackage
    : original(platform);
}

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

  patchAutolinkingHarmonySupportPackage(projectRoot);

  return getImplementation(projectRoot, harmonyPackage)(config, { ...options, projectRoot });
}
