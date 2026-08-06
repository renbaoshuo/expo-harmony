# @expo-harmony/entry

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/entry)

HarmonyOS 下 Expo 应用的入口。它负责安装 HarmonyOS 必需的 Expo polyfill、执行应用根目录中的自定义 prelude，最后加载 `expo-router/entry`。

## 接入

安装 `@expo-harmony/entry` 和 `@expo-harmony/metro-config`，并在 `package.json` 中把应用入口改为：

```json
{
  "main": "@expo-harmony/entry"
}
```

应用的 `metro.config.js` 需要引入 `@expo-harmony/metro-config`：

```js
'use strict';

const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

const projectRoot = __dirname;
const isHarmony = process.env.EXPO_METRO_TARGET === 'harmony';

module.exports = withHarmonyConfig(getDefaultConfig(projectRoot), {
  enabled: isHarmony,
  projectRoot,
});
```

`withHarmonyConfig` 启用时才会解析应用 prelude。在普通 Expo 启动流程中将 enhancer 设为 `enabled: false` 时，入口直接使用空应用 prelude 并进入 Expo Router（如果设置了平台对应的 prelude 则使用对应的 prelude）。

## 执行顺序

以 `platform=harmony` 为例：

1. Expo 将 `package.json#main` 解析到 `@expo-harmony/entry/index.js`。
2. Metro 为包内的 `require('./prelude')` 选择 `prelude.harmony.js`。
3. 包内 prelude 设置 React Native fetch 模式，并通过 `expo-modules-core` 安装 `globalThis.expo`。
4. `@expo-harmony/metro-config` 从应用根目录解析并执行应用 prelude。
5. 应用 prelude 执行完毕后，入口加载 `expo-router/entry`。

非 Harmony 平台使用包内的空 `prelude.js`，不会干预 iOS 或 Android 通过原生 `ExpoModulesCore` 安装的运行时。

应用 prelude 按以下优先级解析：

1. `prelude.<platform>.js`
2. `prelude.js`
3. 包内空实现

## 包内预置的 Harmony polyfill

`prelude.harmony.js` 会在任何应用代码和 Expo Router 之前执行：

```js
process.env.EXPO_PUBLIC_USE_RN_FETCH = '1';

const { installExpoGlobalPolyfill } = require('expo-modules-core/src/polyfill/dangerous-internal');

installExpoGlobalPolyfill();
```

`expo-modules-core` 使用 peer dependency，以便始终复用应用当前 Expo SDK 对应的版本。安装函数自身是幂等的。

## 编写应用 prelude

应用可以在项目根目录提供 `prelude.harmony.js`，用于执行平台相关的初始化：

```js
'use strict';

// Web Crypto 等依赖应用原生模块的 polyfill 仍由应用提供。
require('./harmony-polyfill/crypto-polyfill.harmony');

// ...
```

## Bundle 入口

HarmonyOS 原生端的开发 bundle URL 必须使用 Expo virtual entry，才能读取 `package.json#main`：

```text
http://localhost:8082/.expo/.virtual-metro-entry.bundle?platform=harmony&dev=true&minify=false&modulesOnly=false&runModule=true
```

普通的 `/index.bundle` 或 `/index.harmony.bundle` 会绕过 Expo 的 virtual-entry 重写，无法以 `package.json#main` 作为唯一入口来源。

RNOH Release 打包命令需要实际文件路径时，先让 Expo 解析入口：

```js
const { resolveEntryPoint } = require('expo/config/paths');

const entryFile = resolveEntryPoint(projectRoot, { platform: 'harmony' });
```

再把 `entryFile` 传给 `bundle-harmony --entry-file`。

这样开发与生产构建都会使用同样的入口逻辑，确保应用 prelude 在任何情况下都能被执行。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the [MIT](./LICENSE) License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
