import type { InputConfigT } from 'metro-config';

type MetroResolveRequest = NonNullable<NonNullable<InputConfigT['resolver']>['resolveRequest']>;

/** Harmony resolver 使用的 Metro 解析上下文。 */
export type HarmonyResolutionContext = Parameters<MetroResolveRequest>[0];
/** Harmony resolver 返回的 Metro 解析结果。 */
export type HarmonyResolution = ReturnType<MetroResolveRequest>;

export interface HarmonyResolverRequest {
  /** 当前请求的 Metro 解析上下文。 */
  context: HarmonyResolutionContext;
  /** 尚未解析的 import 模块标识符。 */
  moduleName: string;
  /** 配置的 hook 被调用时始终为 `harmony`。 */
  platform: string | null;
  /** 传给 withHarmonyConfig 的项目根目录。 */
  projectRoot: string;
  /** 通过原有的 Expo/Metro resolver 解析请求。 */
  resolve(moduleName: string, platform?: string | null): HarmonyResolution;
  /** 跳过用户配置的重定向和 hook，直接通过 RNOH 解析请求。 */
  resolveHarmony(moduleName?: string, platform?: string | null): HarmonyResolution;
}

/** 用于判断模块是否应解析为空模块的匹配规则。 */
export type HarmonyModuleMatcher
  = | string
    | RegExp
    | ((request: HarmonyResolverRequest) => boolean);

/** 自定义重定向可以返回的结果。 */
export type HarmonyRedirectResult = HarmonyResolution | string | false | null | undefined;
/** 静态重定向结果，或根据当前请求动态返回结果的函数。 */
export type HarmonyRedirect
  = | HarmonyRedirectResult
    | ((request: HarmonyResolverRequest) => HarmonyRedirectResult);

export interface HarmonyMetroConfigOptions {
  /** 覆盖 RNOH 用来替代 react-native 的包名。 */
  reactNativeHarmonyPackageName?: string;
  /** @internal 当前安装的 RNOH Metro 实现支持的内部选项。 */
  __reactNativeHarmonyPattern?: string;
  /** @internal 当前安装的 RNOH Metro 实现支持的内部选项。 */
  __reactNativeInteropLibraryPackagePattern?: string;
  [option: string]: unknown;
}

export interface WithHarmonyConfigOptions {
  /** 原样返回传入的 config，且不加载 Harmony peer dependencies。 */
  enabled?: boolean;
  /** 默认依次使用 config.projectRoot 和 process.cwd()。 */
  projectRoot?: string;
  /** 默认为 @react-native-oh/react-native-harmony。 */
  reactNativeHarmonyPackageName?: string;
  /** 额外传给 RNOH createHarmonyMetroConfig 的选项。 */
  harmonyConfigOptions?: HarmonyMetroConfigOptions;
  /** 追加到 resolver.unstable_conditionsByPlatform.harmony 的 conditions。 */
  conditions?: readonly string[];
  /** 模块前缀别名，支持精确匹配和子路径匹配。 */
  aliases?: ReadonlyMap<string, string> | Readonly<Record<string, string>>;
  /** 精确模块重定向；字符串目标通过原有的 Expo resolver 解析。 */
  redirects?:
    | ReadonlyMap<string, HarmonyRedirect>
    | Readonly<Record<string, HarmonyRedirect>>;
  /** 需要解析为 Metro empty module 结果的请求匹配项。 */
  emptyModules?: readonly HarmonyModuleMatcher[];
  /**
   * 只处理 Harmony 请求。返回 null/undefined 时继续依次尝试 redirects、
   * aliases，最后交给 RNOH resolver。
   */
  resolveRequest?: (request: HarmonyResolverRequest) => HarmonyRedirectResult;
  /**
   * 加载 Metro 配置时写入的环境变量。默认包含 EXPO_HARMONY=true；
   * 设置为 false 可禁止修改任何环境变量。
   */
  env?: false | Readonly<Record<string, string>>;
}

/** 将 RNOH Harmony 配置合并到现有的 Expo/Metro 配置。 */
export function withHarmonyConfig<T extends InputConfigT>(
  config: T,
  options?: WithHarmonyConfigOptions
): T & InputConfigT;
