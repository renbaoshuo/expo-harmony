# @expo-harmony/metro-config

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/metro-config) | [Expo Metro 配置文档](https://docs.expo.dev/guides/customizing-metro/)

本包用于在 Expo 项目的 Metro 配置中加入 HarmonyOS 支持。

## 安装

本包适配 Expo SDK 57。

```bash
npm install @expo-harmony/metro-config @expo-harmony/expo-modules-core
```

## 配置 Metro

在项目根目录的 `metro.config.js` 中，将 Expo 默认配置传给 `withHarmonyConfig`：

```js
const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

const projectRoot = __dirname;
const config = getDefaultConfig(projectRoot);

module.exports = withHarmonyConfig(config, { projectRoot });
```

如果同一份 Metro 配置也用于 Android 或 iOS，可以只在 HarmonyOS 构建时启用 HarmonyOS 配置：

```js
const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

const projectRoot = __dirname;
const isHarmony = process.env.EXPO_METRO_TARGET === 'harmony';
const config = getDefaultConfig(projectRoot);

module.exports = withHarmonyConfig(config, {
  enabled: isHarmony,
  projectRoot,
});
```

`enabled` 默认为 `true`。设为 `false` 时会原样返回传入的 Metro 配置。通过 `expo-harmony start` 启动 HarmonyOS 开发服务时，CLI 会设置 `EXPO_METRO_TARGET=harmony`。

## 替换 HarmonyOS 模块

如果某个依赖没有适配 HarmonyOS，可以用 `aliases` 指向适配文件，或用 `redirects` 替换单个模块。`redirects` 的目标可以是模块名；设为 `false` 时，该模块会解析为空模块。`emptyModules` 则可以按模块名、正则表达式或函数匹配需要留空的模块。

这些规则只影响 HarmonyOS bundle，Android 和 iOS 仍使用 Expo 的模块解析配置。

```js
const path = require('node:path');
const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

const projectRoot = __dirname;
const config = getDefaultConfig(projectRoot);

module.exports = withHarmonyConfig(config, {
  projectRoot,
  aliases: {
    'my-library': path.resolve(projectRoot, 'src/harmony/my-library'),
  },
  redirects: {
    'legacy-module': 'my-library',
    'unsupported-module': false,
  },
  emptyModules: [/MaterialSymbols/u],
});
```

需要根据导入来源选择不同模块时，可以使用 `resolveRequest`。例如，下面的配置会在 `screens` 目录中的文件导入 `my-library` 时，改为解析 HarmonyOS 入口：

```js
const path = require('node:path');
const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

const projectRoot = __dirname;
const config = getDefaultConfig(projectRoot);

module.exports = withHarmonyConfig(config, {
  projectRoot,
  resolveRequest({ context, moduleName, resolve }) {
    const screensPath = `${path.sep}screens${path.sep}`;
    if (moduleName === 'my-library' && context.originModulePath.includes(screensPath)) {
      return resolve('my-library/harmony');
    }
    return null;
  },
});
```

返回 `null` 或 `undefined` 时，会继续使用其他 HarmonyOS 模块解析规则。`resolve` 可以调用 Expo 的默认解析过程；需要跳过自定义规则并直接解析 HarmonyOS 模块时，可以使用 `resolveHarmony`。

配置项按 `emptyModules`、`resolveRequest`、`redirects`、`aliases` 的顺序处理，未匹配的模块会交给 HarmonyOS 模块解析器继续查找。`aliases` 支持模块名前缀，多个别名都匹配时会使用最长前缀。

## 调整 HarmonyOS 模块解析

`conditions` 用于补充 HarmonyOS 的 package exports 条件，默认包含 `harmony` 和 `react-native`。如果项目使用其他 React Native HarmonyOS 包，可以通过 `reactNativeHarmonyPackageName` 指定包名；该包提供额外 Metro 选项时，可以放在 `harmonyConfigOptions` 中：

```js
const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

const config = getDefaultConfig(__dirname);

module.exports = withHarmonyConfig(config, {
  conditions: ['harmony', 'react-native'],
  reactNativeHarmonyPackageName: '@react-native-oh/react-native-harmony',
  harmonyConfigOptions: {
    // 填写所用 React Native HarmonyOS 包支持的 Metro 选项。
  },
});
```

## 与其他 Metro 配置组合

如果项目还使用 NativeWind 等 Metro 配置增强器，先将 Expo 默认配置传给 `withHarmonyConfig`，再将结果传给其他增强器：

```js
const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');
const { withNativeWind } = require('nativewind/metro');

const config = withHarmonyConfig(getDefaultConfig(__dirname));
module.exports = withNativeWind(config, { input: './global.css' });
```

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
