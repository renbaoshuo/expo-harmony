import crypto from 'node:crypto';
import type { InputConfigT } from 'metro-config';

import { DefaultReactNativeHarmonyPackage, HarmonyPlatform, HarmonyPlatformExtensions } from './constants';
import { ExpoHarmonyMetroError } from './errors';
import { createResolver, getEntries, type HarmonyResolverOptions } from './resolver';
import { createHarmonyPathNormalizer, getBootstrapModules } from './runtime';
import { composeSerializer } from './serializer';

export interface HarmonyMetroConfigOptions {
  reactNativeHarmonyPackageName?: string;
  /** @internal */
  __reactNativeHarmonyPattern?: string;
  /** @internal */
  __reactNativeInteropLibraryPackagePattern?: string;
  [option: string]: unknown;
}

export interface WithHarmonyConfigOptions extends HarmonyResolverOptions {
  enabled?: boolean;
  projectRoot?: string;
  reactNativeHarmonyPackageName?: string;
  harmonyConfigOptions?: HarmonyMetroConfigOptions;
  conditions?: readonly string[];
  env?: false | Readonly<Record<string, string>>;
}

export type CreateHarmonyMetroConfig = (options: HarmonyMetroConfigOptions) => InputConfigT;
export type MergeConfig = (base: InputConfigT, override: InputConfigT) => InputConfigT;

interface ConfigFactories {
  createHarmonyMetroConfig: CreateHarmonyMetroConfig;
  mergeConfig: MergeConfig;
}

const ExpoVirtualEntryPath = '/.expo/.virtual-metro-entry.bundle';

function assertObject(value: unknown, name: string): asserts value is Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoHarmonyMetroError('ERR_EXPO_HARMONY_INVALID_OPTIONS', `${name} must be an object.`);
  }
}

function validateOptions(value: unknown): asserts value is WithHarmonyConfigOptions {
  assertObject(value, 'options');

  if (value.resolveRequest !== undefined && typeof value.resolveRequest !== 'function') {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_INVALID_OPTIONS',
      'options.resolveRequest must be a function.'
    );
  }

  if (value.emptyModules !== undefined && !Array.isArray(value.emptyModules)) {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_INVALID_OPTIONS',
      'options.emptyModules must be an array.'
    );
  }
  if (Array.isArray(value.emptyModules)
    && value.emptyModules.some(matcher => typeof matcher !== 'string' && !(matcher instanceof RegExp) && typeof matcher !== 'function')) {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_INVALID_OPTIONS',
      'options.emptyModules entries must be strings, regular expressions, or functions.'
    );
  }

  if (value.conditions !== undefined
    && (!Array.isArray(value.conditions)
      || value.conditions.some(condition => typeof condition !== 'string'))) {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_INVALID_OPTIONS',
      'options.conditions must be an array of strings.'
    );
  }

  for (const [alias, target] of getEntries(value.aliases, 'options.aliases')) {
    if (typeof alias !== 'string' || typeof target !== 'string') {
      throw new ExpoHarmonyMetroError(
        'ERR_EXPO_HARMONY_INVALID_OPTIONS',
        'options.aliases must map strings to strings.'
      );
    }
  }

  for (const [name, target] of getEntries(value.redirects, 'options.redirects')) {
    if (typeof name !== 'string') {
      throw new ExpoHarmonyMetroError(
        'ERR_EXPO_HARMONY_INVALID_OPTIONS',
        'options.redirects keys must be strings.'
      );
    }
    if (!['string', 'function', 'object', 'undefined'].includes(typeof target) && target !== false) {
      throw new ExpoHarmonyMetroError(
        'ERR_EXPO_HARMONY_INVALID_REDIRECT',
        `Unsupported redirect target for "${name}".`
      );
    }
  }

  if (value.env !== undefined && value.env !== false) {
    for (const [name, entry] of getEntries(value.env, 'options.env')) {
      if (typeof entry !== 'string') {
        throw new ExpoHarmonyMetroError(
          'ERR_EXPO_HARMONY_INVALID_OPTIONS',
          `options.env["${name}"] must be a string.`
        );
      }
    }
  }
}

function wrapRequestUrl(
  rewrite: ((url: string) => string) | undefined
): ((url: string) => string) | undefined {
  if (typeof rewrite !== 'function') return undefined;

  return function rewriteHarmonyRequestUrl(request) {
    let url;
    const relative = request.startsWith('/');

    try {
      url = relative ? new URL(request, 'http://localhost') : new URL(request);
    } catch {
      return rewrite(request);
    }

    // RNOH requests index.bundle by convention. Expo's native clients request
    // this virtual entry so Metro can resolve package.json "main" correctly.
    if (url.pathname === '/index.bundle' && url.searchParams.get('platform') === HarmonyPlatform) {
      url = new URL(`${ExpoVirtualEntryPath}${url.search}${url.hash}`, url);
      request = relative ? `${url.pathname}${url.search}${url.hash}` : url.toString();
    }

    return rewrite(request);
  };
}

function normalizeServer(
  server: InputConfigT['server'],
  rewriteRequestUrl: ((url: string) => string) | undefined
): InputConfigT['server'] {
  if (!server && !rewriteRequestUrl) return undefined;

  let normalized = server;
  if (server?.tls === false) {
    const { tls: _tls, ...options } = server;
    normalized = options;
  }

  return rewriteRequestUrl ? { ...normalized, rewriteRequestUrl } : normalized;
}

function mergeBlockLists(
  base: RegExp | RegExp[] | undefined,
  harmony: RegExp | RegExp[] | undefined
): RegExp[] | undefined {
  const toArray = (value: RegExp | RegExp[] | undefined): RegExp[] => {
    if (value === undefined || value === null) return [];
    return Array.isArray(value) ? value : [value];
  };
  const entries = [
    ...toArray(base),
    ...toArray(harmony),
  ];

  return entries.length > 0 ? entries : undefined;
}

function readPlatformExtensions(
  resolver: unknown
): Record<string, readonly string[] | undefined> {
  if (!resolver || typeof resolver !== 'object') return {};
  const value = (resolver as { unstable_platformExtensions?: unknown }).unstable_platformExtensions;
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, readonly string[] | undefined>
    : {};
}

export function createWithHarmonyConfig({
  createHarmonyMetroConfig,
  mergeConfig,
}: ConfigFactories) {
  if (typeof createHarmonyMetroConfig !== 'function' || typeof mergeConfig !== 'function') {
    throw new ExpoHarmonyMetroError(
      'ERR_EXPO_HARMONY_INVALID_FACTORIES',
      'createWithHarmonyConfig requires Metro configuration functions.'
    );
  }

  return function withHarmonyConfig<T extends InputConfigT>(
    config: T,
    options: WithHarmonyConfigOptions = {}
  ): T & InputConfigT {
    assertObject(config, 'config');
    validateOptions(options);

    if (options.env) Object.assign(process.env, options.env);

    const harmonyPackage = options.reactNativeHarmonyPackageName ?? DefaultReactNativeHarmonyPackage;
    const native = createHarmonyMetroConfig({
      ...options.harmonyConfigOptions,
      reactNativeHarmonyPackageName: harmonyPackage,
    });
    const merged = mergeConfig(config, native);
    const baseResolver = config.resolver?.resolveRequest;
    const harmonyResolver = merged.resolver?.resolveRequest;
    if (typeof harmonyResolver !== 'function') {
      throw new ExpoHarmonyMetroError(
        'ERR_EXPO_HARMONY_INCOMPATIBLE_PEER_DEPENDENCY',
        'createHarmonyMetroConfig() did not return a resolver.resolveRequest function.'
      );
    }

    const conditions = options.conditions ?? ['harmony', 'react-native'];
    const existing = merged.resolver?.unstable_conditionsByPlatform?.[HarmonyPlatform] ?? [];
    const existingPlatformExtensions = readPlatformExtensions(merged.resolver);
    const blockList = mergeBlockLists(config.resolver?.blockList, native.resolver?.blockList);
    const root = options.projectRoot ?? merged.projectRoot ?? process.cwd();
    const normalizePath = createHarmonyPathNormalizer(harmonyPackage, root);
    const bootstrap = getBootstrapModules(harmonyPackage, root);
    const rewriteRequestUrl = wrapRequestUrl(merged.server?.rewriteRequestUrl);
    const server = normalizeServer(merged.server, rewriteRequestUrl);
    const reactPackage = getEntries(options.aliases, 'options.aliases').find(([name]) => name === 'react')?.[1] || 'react';
    const fixedRuntime = !options.resolveRequest && !options.redirects && !options.emptyModules
      && getEntries(options.aliases, 'options.aliases').every(([name]) => name === 'react');

    const environment = Object.keys(process.env).filter(key => key.startsWith('EXPO_PUBLIC_')).sort()
      .map(key => [key, process.env[key]]);
    const cache = process.env.NODE_ENV === 'production'
      ? `${merged.cacheVersion ?? ''}:expo-public:${crypto.createHash('sha256').update(JSON.stringify(environment)).digest('hex')}`
      : merged.cacheVersion;

    const serializer = composeSerializer(merged.serializer, normalizePath, [
      config.serializer,
      native.serializer,
    ], bootstrap);

    if (config.serializer && typeof serializer?.getModulesRunBeforeMainModule === 'function') {
      Object.assign(config.serializer, {
        getModulesRunBeforeMainModule: serializer.getModulesRunBeforeMainModule,
      });
    }

    return {
      ...merged,
      cacheVersion: cache,
      serializer,
      ...(server ? { server } : {}),
      resolver: {
        ...merged.resolver,
        ...(blockList ? { blockList } : {}),
        platforms: [...new Set([
          ...(config.resolver?.platforms ?? []),
          ...(native.resolver?.platforms ?? []),
          ...(merged.resolver?.platforms ?? []),
          HarmonyPlatform,
        ])],
        unstable_conditionsByPlatform: {
          ...merged.resolver?.unstable_conditionsByPlatform,
          [HarmonyPlatform]: [...new Set([...existing, ...conditions])],
        },
        // Register `harmony` through Expo's out-of-tree platform channel. Expo CLI
        // 55.0.33+ folds these extensions into platform-less strict resolution
        // (server routes, DOM components) via `constructPlatformExtensions`, the
        // same mechanism it uses for tvos/macos. Older CLIs ignore the field.
        unstable_platformExtensions: {
          ...existingPlatformExtensions,
          [HarmonyPlatform]: [
            ...(existingPlatformExtensions[HarmonyPlatform] ?? HarmonyPlatformExtensions),
          ],
        },
        resolveRequest: Object.assign(createResolver({
          baseResolver,
          harmonyResolver,
          normalizePath,
          options,
          projectRoot: root,
        }), { harmonyRuntime: { reactPackage, harmonyPackage, fixedRuntime } }),
      },
    } as unknown as T & InputConfigT;
  };
}
