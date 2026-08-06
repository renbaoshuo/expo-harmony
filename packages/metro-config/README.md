# @expo-harmony/metro-config

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/metro-config)

用于将 Expo Metro 配置与 React Native OpenHarmony（RNOH）组合起来，使 Expo 项目能够同时支持 HarmonyOS。

这个包会隔离 Expo 与 RNOH 的 resolver 调用链：

- Android、iOS 和 Web 请求继续使用 Expo 原有的 resolver。
- Harmony 请求先经过项目自定义的重定向规则，再进入 RNOH resolver。
- 当 RNOH 需要解析具体文件或依赖时，会重新委托给原有的 Expo resolver，因而能够保留 Expo Router、TypeScript paths 等 Expo 能力。

## 基础用法

按照下面的逻辑修改项目的 `metro.config.js`：

```js
'use strict';

const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

const projectRoot = __dirname;
const isHarmony = process.env.EXPO_METRO_TARGET === 'harmony';
let config = getDefaultConfig(projectRoot);

config = withHarmonyConfig(config, {
  enabled: isHarmony,
  projectRoot,
});

module.exports = config;
```

当 `enabled` 为 `false` 时，`withHarmonyConfig` 会直接返回传入的配置，且不会加载 RNOH 依赖。因此，应用可以将 `@react-native-oh/react-native-harmony` 放在 `optionalDependencies` 中，没有安装 Harmony 工具链的 Android、iOS 开发者也不会受到影响。

使用 Expo CLI 启动 Metro，并由 Harmony 原生应用发起 Harmony bundle 请求，例子如下：

```json
{
  "scripts": {
    "start": "expo start",
    "harmony": "cross-env EXPO_METRO_TARGET=harmony expo start --port 8082 --localhost"
  }
}
```

Harmony 原生端通过 Expo virtual entry 请求 bundle：

```text
/.expo/.virtual-metro-entry.bundle?platform=harmony&dev=true&minify=false&modulesOnly=false&runModule=true
```

Expo Metro 会把这个 URL 重写到 `package.json#main` 解析出的实际入口。不要向 Expo CLI 传递 `--harmony`，这样会导致无法正常启动。

当 `package.json#main` 使用 `@expo-harmony/entry` 时，入口包会先安装 HarmonyOS 所需的 Expo polyfill，再按以下顺序从应用根目录解析 prelude：

1. `prelude.<platform>.js`
2. `prelude.js`
3. 入口包中的空实现

入口配置、应用 prelude 和其他高阶用法参见 [`@expo-harmony/entry` 文档](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/entry#readme)。

## 配置

配置项覆盖了实际 Expo/RNOH 项目常见的适配场景：

```js
const path = require('node:path');

config = withHarmonyConfig(config, {
  // 是否启用 Harmony 配置，默认为 true。
  // false 时原样返回 config，且不会加载 RNOH 和 metro-config peer dependencies。
  enabled: isHarmony,

  // 项目根目录。
  // 默认依次使用 config.projectRoot 和 process.cwd()。
  projectRoot,

  // 指定 RNOH 用来替代 react-native 的包名。
  // 不配置时默认使用 @react-native-oh/react-native-harmony。
  reactNativeHarmonyPackageName: '@react-native-oh/react-native-harmony',

  // 向 RNOH createHarmonyMetroConfig 透传当前 RNOH 版本支持的额外参数。
  // 顶层 reactNativeHarmonyPackageName 会覆盖这里的同名配置。
  harmonyConfigOptions: {
    // 在这里填写 RNOH 的高级 Metro 配置。
  },

  // 追加 Harmony 平台的 package exports conditions。
  // 默认为 ['react-native']；原有 conditions 会被保留并去重。
  conditions: ['react-native'],

  // 加载配置时写入 process.env 的额外变量。
  // 默认总会写入 EXPO_HARMONY=true；设置 env: false 可完全禁止修改环境变量。
  env: {
    IS_HARMONY: 'true',
  },

  // 模块前缀别名，支持普通对象或 Map、精确匹配和子路径匹配。
  // 多项同时匹配时使用最长前缀；例如：
  // react/jsx-runtime 会变成 react-harmony/jsx-runtime，
  // @/components 会变成 <projectRoot>/components。
  aliases: {
    '@': projectRoot,
    api: path.join(projectRoot, 'api'),
    components: path.join(projectRoot, 'components'),
    react: 'react-harmony',
  },

  // 精确模块重定向，支持普通对象或 Map。每个目标可以是：
  // - 字符串会交给原有的 Expo resolver 解析；
  // - false 会返回 Metro 的 empty 结果；
  // - Metro resolution 对象；
  // - 接收当前请求并返回上述结果的函数。
  redirects: {
    'expo-blur': path.join(projectRoot, 'harmony-adapters/expo-blur.harmony.js'),
    'react-native-screens/experimental': false,
    '@/components/toolbox-icons': {
      type: 'sourceFile',
      filePath: path.join(projectRoot, 'components/toolbox-icons.harmony.tsx'),
    },
  },

  // 将匹配项解析为空模块，可用于屏蔽 Harmony 不支持的依赖。
  // 每项可以是精确模块名、正则表达式，或接收当前请求并返回布尔值的函数。
  emptyModules: [/MaterialSymbols/u],

  // 只处理 Harmony 请求，适合根据导入来源进行动态重定向。
  // 可以返回 Metro resolution、交给 Expo resolver 解析的模块名或 false；
  // 返回 null/undefined 会继续尝试 redirects、aliases，最后进入 RNOH resolver。
  // resolve() 可直接调用 Expo resolver；resolveHarmony() 可跳过自定义规则调用 RNOH resolver。
  resolveRequest({ context, moduleName, resolve, resolveHarmony }) {
    if (moduleName === './SplashScreen' && context.originModulePath.includes(`${path.sep}expo-splash-screen${path.sep}`)) {
      return {
        type: 'sourceFile',
        filePath: path.join(projectRoot, 'harmony-adapters/SplashScreen.native.js'),
      };
    }
  },
});
```

Harmony 请求的 resolver 匹配顺序如下：

1. `emptyModules`
2. `resolveRequest`
3. 精确匹配的 `redirects`
4. 前缀匹配的 `aliases`，优先使用最长匹配项
5. RNOH resolver

## 与其他 Metro enhancer 组合

通用的 Metro enhancer 应在 `withHarmonyConfig` 之后应用：

```js
const { withNativeWind } = require('nativewind/metro');

config = withHarmonyConfig(config, harmonyOptions);
module.exports = withNativeWind(config, { input: './global.css' });
```

这样 `env` 中的 Harmony 环境变量也能在 NativeWind 等后续配置读取时生效。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the [MIT](./LICENSE) License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
