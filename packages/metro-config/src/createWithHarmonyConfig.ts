import type { InputConfigT } from 'metro-config';

import { DefaultReactNativeHarmonyPackage, HarmonyPlatform } from './constants';
import { createResolver, getEntries, type HarmonyResolverOptions } from './resolver';
import { createHarmonyPathNormalizer, getBootstrapModules } from './runtime';
import { composeSerializer } from './serializer';

/** 透传给 RNOH createHarmonyMetroConfig 的额外配置。 */
export interface HarmonyMetroConfigOptions {
  /** 指定 RNOH 用来替代 react-native 的包名。 */
  reactNativeHarmonyPackageName?: string;
  /** @internal */
  __reactNativeHarmonyPattern?: string;
  /** @internal */
  __reactNativeInteropLibraryPackagePattern?: string;
  [option: string]: unknown;
}

export interface WithHarmonyConfigOptions extends HarmonyResolverOptions {
  /**
   * 是否启用 Harmony 配置，默认为 true。设为 false 时原样返回 config，
   * 且不加载 RNOH 和 metro-config peer dependencies。
   */
  enabled?: boolean;
  /** 项目根目录。默认依次使用 config.projectRoot 和 process.cwd()。 */
  projectRoot?: string;
  /**
   * 指定 RNOH 用来替代 react-native 的包名。
   * 默认为 @react-native-oh/react-native-harmony。
   */
  reactNativeHarmonyPackageName?: string;
  /**
   * 向 RNOH createHarmonyMetroConfig 透传当前 RNOH 版本支持的额外参数。
   * 顶层 reactNativeHarmonyPackageName 会覆盖这里的同名配置。
   */
  harmonyConfigOptions?: HarmonyMetroConfigOptions;
  /**
   * 追加 Harmony 平台的 package exports conditions。默认为
   * ['harmony', 'react-native']；原有 conditions 会被保留并去重。
   */
  conditions?: readonly string[];
  /**
   * 加载配置时写入 process.env 的额外变量。仅在显式配置时写入，默认
   * 不会修改共享 Metro 进程的环境变量；也可设为 false 明确禁止修改。
   */
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
    throw new TypeError(`${name} must be an object.`);
  }
}

function validateOptions(value: unknown): asserts value is WithHarmonyConfigOptions {
  assertObject(value, 'options');

  if (value.resolveRequest !== undefined && typeof value.resolveRequest !== 'function') {
    throw new TypeError('options.resolveRequest must be a function.');
  }
  if (value.emptyModules !== undefined && !Array.isArray(value.emptyModules)) {
    throw new TypeError('options.emptyModules must be an array.');
  }
  if (Array.isArray(value.emptyModules)
    && value.emptyModules.some(matcher => typeof matcher !== 'string' && !(matcher instanceof RegExp) && typeof matcher !== 'function')) {
    throw new TypeError('options.emptyModules entries must be strings, regular expressions, or functions.');
  }

  if (value.conditions !== undefined
    && (!Array.isArray(value.conditions)
      || value.conditions.some(condition => typeof condition !== 'string'))) {
    throw new TypeError('options.conditions must be an array of strings.');
  }

  for (const [alias, target] of getEntries(value.aliases, 'options.aliases')) {
    if (typeof alias !== 'string' || typeof target !== 'string') {
      throw new TypeError('options.aliases must map strings to strings.');
    }
  }

  for (const [moduleName, target] of getEntries(value.redirects, 'options.redirects')) {
    if (typeof moduleName !== 'string') {
      throw new TypeError('options.redirects keys must be strings.');
    }
    if (!['string', 'function', 'object', 'undefined'].includes(typeof target) && target !== false) {
      throw new TypeError(`Unsupported redirect target for "${moduleName}".`);
    }
  }

  if (value.env !== undefined && value.env !== false) {
    for (const [name, envValue] of getEntries(value.env, 'options.env')) {
      if (typeof envValue !== 'string') {
        throw new TypeError(`options.env["${name}"] must be a string.`);
      }
    }
  }
}

function wrapRequestUrl(
  rewriteRequestUrl: ((url: string) => string) | undefined
): ((url: string) => string) | undefined {
  if (typeof rewriteRequestUrl !== 'function') return undefined;

  return function rewriteHarmonyRequestUrl(requestUrl) {
    let url;
    const relative = requestUrl.startsWith('/');

    try {
      url = relative ? new URL(requestUrl, 'http://localhost') : new URL(requestUrl);
    } catch {
      return rewriteRequestUrl(requestUrl);
    }

    // RNOH requests index.bundle by convention. Expo's native clients request
    // this virtual entry so Metro can resolve package.json "main" correctly.
    if (url.pathname === '/index.bundle' && url.searchParams.get('platform') === HarmonyPlatform) {
      url.pathname = ExpoVirtualEntryPath;
      requestUrl = relative ? `${url.pathname}${url.search}${url.hash}` : url.toString();
    }

    return rewriteRequestUrl(requestUrl);
  };
}

function normalizeServer(
  server: InputConfigT['server'],
  rewriteRequestUrl: ((url: string) => string) | undefined
): InputConfigT['server'] {
  if (!server && !rewriteRequestUrl) return undefined;

  let normalized = server;
  if (server?.tls === false) {
    const { tls: _disabledTls, ...metroServer } = server;
    normalized = metroServer;
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
  const blockList = [
    ...toArray(base),
    ...toArray(harmony),
  ];

  return blockList.length > 0 ? blockList : undefined;
}

export function createWithHarmonyConfig({
  createHarmonyMetroConfig,
  mergeConfig,
}: ConfigFactories) {
  if (typeof createHarmonyMetroConfig !== 'function' || typeof mergeConfig !== 'function') {
    throw new TypeError('createWithHarmonyConfig requires Metro configuration functions.');
  }

  return function withHarmonyConfig<T extends InputConfigT>(
    config: T,
    options: WithHarmonyConfigOptions = {}
  ): T & InputConfigT {
    assertObject(config, 'config');
    validateOptions(options);

    if (options.env) Object.assign(process.env, options.env);

    const harmonyPackage = options.reactNativeHarmonyPackageName ?? DefaultReactNativeHarmonyPackage;
    const harmonyConfig = createHarmonyMetroConfig({
      ...options.harmonyConfigOptions,
      reactNativeHarmonyPackageName: harmonyPackage,
    });
    const mergedConfig = mergeConfig(config, harmonyConfig);
    const baseResolver = config.resolver?.resolveRequest;
    const harmonyResolver = mergedConfig.resolver?.resolveRequest;
    if (typeof harmonyResolver !== 'function') {
      throw new TypeError('createHarmonyMetroConfig() did not return a resolver.resolveRequest function.');
    }

    const conditions = options.conditions ?? ['harmony', 'react-native'];
    const existingConditions = mergedConfig.resolver?.unstable_conditionsByPlatform?.[HarmonyPlatform] ?? [];
    const blockList = mergeBlockLists(config.resolver?.blockList, harmonyConfig.resolver?.blockList);
    const projectRoot = options.projectRoot ?? mergedConfig.projectRoot ?? process.cwd();
    const normalizePath = createHarmonyPathNormalizer(harmonyPackage, projectRoot);
    const bootstrap = getBootstrapModules(harmonyPackage, projectRoot);
    const rewriteRequestUrl = wrapRequestUrl(mergedConfig.server?.rewriteRequestUrl);
    const server = normalizeServer(mergedConfig.server, rewriteRequestUrl);
    const serializer = composeSerializer(mergedConfig.serializer, normalizePath, [
      config.serializer,
      harmonyConfig.serializer,
    ], bootstrap);

    if (config.serializer && typeof serializer?.getModulesRunBeforeMainModule === 'function') {
      Object.assign(config.serializer, {
        getModulesRunBeforeMainModule: serializer.getModulesRunBeforeMainModule,
      });
    }

    return {
      ...mergedConfig,
      serializer,
      ...(server ? { server } : {}),
      resolver: {
        ...mergedConfig.resolver,
        ...(blockList ? { blockList } : {}),
        platforms: [...new Set([
          ...(config.resolver?.platforms ?? []),
          ...(harmonyConfig.resolver?.platforms ?? []),
          ...(mergedConfig.resolver?.platforms ?? []),
          HarmonyPlatform,
        ])],
        unstable_conditionsByPlatform: {
          ...mergedConfig.resolver?.unstable_conditionsByPlatform,
          [HarmonyPlatform]: [...new Set([...existingConditions, ...conditions])],
        },
        resolveRequest: createResolver({
          baseResolver,
          harmonyResolver,
          normalizePath,
          options,
          projectRoot,
        }),
      },
    } as unknown as T & InputConfigT;
  };
}
