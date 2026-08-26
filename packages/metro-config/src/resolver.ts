import fs from 'node:fs';
import path from 'node:path';

import type { InputConfigT } from 'metro-config';

import { HarmonyPlatform } from './constants';
import type { PathNormalizer } from './runtime';

type MetroResolver = NonNullable<NonNullable<InputConfigT['resolver']>['resolveRequest']>;

/** Harmony resolver 使用的 Metro 解析上下文。 */
export type HarmonyResolutionContext = Parameters<MetroResolver>[0];
/** Harmony resolver 返回的 Metro 解析结果。 */
export type HarmonyResolution = ReturnType<MetroResolver>;

export interface HarmonyResolverRequest {
  /** 当前请求的 Metro 解析上下文，可通过 originModulePath 判断导入来源。 */
  context: HarmonyResolutionContext;
  /** 当前尚未解析的 import 模块标识符。 */
  moduleName: string;
  /** 当前请求平台；这些自定义 hook 被调用时始终为 harmony。 */
  platform: string | null;
  /** withHarmonyConfig 最终使用的绝对项目根目录。 */
  projectRoot: string;
  /**
   * 通过原有的 Expo/Metro resolver 解析模块，可保留 Expo Router、
   * TypeScript paths 等能力。platform 默认使用当前请求平台。
   */
  resolve(moduleName: string, platform?: string | null): HarmonyResolution;
  /**
   * 跳过 emptyModules、resolveRequest、redirects 和 aliases，直接通过
   * RNOH resolver 解析。moduleName 和 platform 默认使用当前请求值。
   */
  resolveHarmony(moduleName?: string, platform?: string | null): HarmonyResolution;
}

/**
 * 用于判断模块是否应解析为空模块的规则：精确模块名、正则表达式，
 * 或接收当前请求并返回布尔值的函数。
 */
export type HarmonyModuleMatcher
  = | string
    | RegExp
    | ((request: HarmonyResolverRequest) => boolean);

/**
 * 自定义解析结果：Metro resolution、交给 Expo resolver 解析的模块名、
 * false 表示 empty，null/undefined 表示继续后续匹配。
 */
export type HarmonyRedirectResult = HarmonyResolution | string | false | null | undefined;
/** 静态重定向结果，或接收当前请求并动态返回结果的函数。 */
export type HarmonyRedirect
  = | HarmonyRedirectResult
    | ((request: HarmonyResolverRequest) => HarmonyRedirectResult);

export interface HarmonyResolverOptions {
  /**
   * 模块前缀别名，支持普通对象或 Map、精确匹配和子路径匹配。
   * 多项同时匹配时使用最长前缀。
   */
  aliases?: ReadonlyMap<string, string> | Readonly<Record<string, string>>;
  /**
   * 精确模块重定向，支持普通对象或 Map。目标可以是模块名、false、
   * Metro resolution，或接收当前请求并返回上述结果的函数。
   */
  redirects?:
    | ReadonlyMap<string, HarmonyRedirect>
    | Readonly<Record<string, HarmonyRedirect>>;
  /**
   * 需要解析为空模块的匹配项，可用于屏蔽 Harmony 不支持的依赖。
   * 每项可以是精确模块名、正则表达式或接收当前请求的函数。
   */
  emptyModules?: readonly HarmonyModuleMatcher[];
  /**
   * 只处理 Harmony 请求，适合根据导入来源动态重定向。可以返回 Metro
   * resolution、模块名或 false；返回 null/undefined 时继续依次尝试
   * redirects、aliases，最后进入 RNOH resolver。
   */
  resolveRequest?: (request: HarmonyResolverRequest) => HarmonyRedirectResult;
}

interface ResolverOptions {
  baseResolver: MetroResolver | null | undefined;
  harmonyResolver: MetroResolver;
  normalizePath: PathNormalizer;
  options: HarmonyResolverOptions;
  projectRoot: string;
}

const NoResolution = Symbol('NoResolution');
const DirectoryHarmonyAliases = new Map<string, string | null>();

function getPackageName(moduleName: string): string | null {
  if (moduleName.startsWith('.') || moduleName.startsWith('/')) return null;

  const parts = moduleName.split('/');
  if (moduleName.startsWith('@')) {
    return parts.length >= 2 ? `${parts[0]}/${parts[1]}` : null;
  }

  return parts[0] || null;
}

function getOriginHarmonyAlias(originModulePath: string): string | null {
  let directory = path.dirname(originModulePath);
  const visited: string[] = [];

  while (true) {
    const cached = DirectoryHarmonyAliases.get(directory);
    if (cached !== undefined) {
      visited.forEach(item => DirectoryHarmonyAliases.set(item, cached));
      return cached;
    }

    visited.push(directory);

    const manifestPath = path.join(directory, 'package.json');
    if (fs.existsSync(manifestPath)) {
      try {
        const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as {
          harmony?: { alias?: unknown };
        };
        const alias = typeof manifest.harmony?.alias === 'string'
          ? manifest.harmony.alias
          : null;

        visited.forEach(item => DirectoryHarmonyAliases.set(item, alias));
        return alias;
      } catch {
        visited.forEach(item => DirectoryHarmonyAliases.set(item, null));
        return null;
      }
    }

    const parent = path.dirname(directory);
    if (parent === directory) break;

    directory = parent;
  }

  visited.forEach(item => DirectoryHarmonyAliases.set(item, null));
  return null;
}

function isUpstreamAliasRequest(request: HarmonyResolverRequest): boolean {
  const packageName = getPackageName(request.moduleName);
  if (!packageName) return false;

  return packageName === getOriginHarmonyAlias(request.context.originModulePath);
}

export function getEntries<T = unknown>(value: unknown, name: string): [string, T][] {
  if (value === undefined) return [];

  if (value instanceof Map) {
    return [...value.entries()] as [string, T][];
  }

  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${name} must be an object.`);
  }

  return Object.entries(value) as [string, T][];
}

function normalizeResolution(result: HarmonyResolution, normalizePath: PathNormalizer): HarmonyResolution {
  if (result?.type !== 'sourceFile' || typeof result.filePath !== 'string') return result;
  const filePath = normalizePath(result.filePath);

  return filePath === result.filePath ? result : { ...result, filePath };
}

function matchesModule(matcher: HarmonyModuleMatcher, request: HarmonyResolverRequest): boolean {
  if (typeof matcher === 'string') return request.moduleName === matcher;

  if (matcher instanceof RegExp) {
    matcher.lastIndex = 0;
    return matcher.test(request.moduleName);
  }

  if (typeof matcher === 'function') return matcher(request);

  throw new TypeError('emptyModules entries must be strings, regular expressions, or functions.');
}

function getRedirect(collection: HarmonyResolverOptions['redirects'], moduleName: string): HarmonyRedirect | typeof NoResolution {
  if (collection === undefined) return NoResolution;

  if (collection instanceof Map) {
    return collection.has(moduleName) ? collection.get(moduleName) : NoResolution;
  }

  const redirects = collection as Readonly<Record<string, HarmonyRedirect>>;
  return Object.prototype.hasOwnProperty.call(redirects, moduleName) ? redirects[moduleName] : NoResolution;
}

function getAlias(aliases: readonly [string, string][], moduleName: string): string | typeof NoResolution {
  for (const [alias, target] of aliases) {
    if (moduleName === alias) return target;
    if (moduleName.startsWith(`${alias}/`)) {
      return `${target}${moduleName.slice(alias.length)}`;
    }
  }

  return NoResolution;
}

function resolveTarget(target: HarmonyRedirect, req: HarmonyResolverRequest): HarmonyResolution | typeof NoResolution {
  const result = typeof target === 'function' ? target(req) : target;

  if (result === undefined || result === null) return NoResolution;
  if (result === false) return { type: 'empty' };
  if (typeof result === 'string') return req.resolve(result);
  if (typeof result === 'object') return result;

  throw new TypeError('A resolver hook must return a Metro resolution, a module name, false, null, or undefined.');
}

function resolveConfiguredRequest(
  options: HarmonyResolverOptions,
  aliases: readonly [string, string][],
  request: HarmonyResolverRequest
): HarmonyResolution {
  if ((options.emptyModules ?? []).some(matcher => matchesModule(matcher, request))) {
    return { type: 'empty' };
  }

  if (options.resolveRequest) {
    const resolution = resolveTarget(options.resolveRequest, request);
    if (resolution !== NoResolution) return resolution;
  }

  const redirect = getRedirect(options.redirects, request.moduleName);
  if (redirect !== NoResolution) {
    const resolution = resolveTarget(redirect, request);
    if (resolution !== NoResolution) return resolution;
  }

  const alias = getAlias(aliases, request.moduleName);
  if (alias !== NoResolution) return request.resolve(alias);

  if (isUpstreamAliasRequest(request)) return request.resolve(request.moduleName);

  return request.resolveHarmony();
}

export function createResolver({
  baseResolver,
  harmonyResolver,
  normalizePath,
  options,
  projectRoot,
}: ResolverOptions): MetroResolver {
  const aliases = getEntries<string>(options.aliases, 'options.aliases')
    .sort(([left], [right]) => right.length - left.length);

  return function resolveRequest(context, moduleName, platform) {
    const metroResolver = context.resolveRequest;
    const resolveBase = (
      targetModuleName: string,
      targetPlatform: string | null = platform,
      targetContext: HarmonyResolutionContext = context
    ): HarmonyResolution => {
      if (!baseResolver) {
        return metroResolver(targetContext, targetModuleName, targetPlatform);
      }

      return baseResolver(
        { ...targetContext, resolveRequest: metroResolver },
        targetModuleName,
        targetPlatform
      );
    };

    if (platform !== HarmonyPlatform) return resolveBase(moduleName, platform);

    const resolveHarmony = (
      targetModuleName: string = moduleName,
      targetPlatform: string | null = platform,
      targetContext: HarmonyResolutionContext = context
    ): HarmonyResolution => {
      const harmonyContext = {
        ...targetContext,
        resolveRequest(
          innerContext: HarmonyResolutionContext,
          innerModuleName: string,
          innerPlatform: string | null
        ) {
          return resolveBase(innerModuleName, innerPlatform, innerContext);
        },
      };

      return harmonyResolver(harmonyContext, targetModuleName, targetPlatform);
    };

    return normalizeResolution(resolveConfiguredRequest(
      options,
      aliases,
      {
        context,
        moduleName,
        platform,
        projectRoot,
        resolve: resolveBase,
        resolveHarmony,
      }
    ), normalizePath);
  };
}
