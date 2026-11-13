# @expo-harmony/expo__log-box

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo__log-box)

为 HarmonyOS 上的 React Native 应用提供 Expo LogBox 的原生实现，与官方 `@expo/log-box` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo__log-box @expo/log-box@~57.0.4
```

## 接入

LogBox 是实验功能。配置插件、Metro 和应用构建时都需要将 `EXPO_UNSTABLE_LOG_BOX` 设为 `1` 或 `true`。

### 配置插件

在 `app.json` 的 `plugins` 中注册插件：

```json
{
  "expo": {
    "plugins": ["@expo-harmony/expo__log-box"],
    "harmony": { "bundleName": "com.example.app" }
  }
}
```

### Metro 配置

在 `metro.config.js` 中组合 HarmonyOS 配置和 LogBox 配置：

```js
const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');
const { withLogBox } = require('@expo-harmony/expo__log-box/metro');

module.exports = withLogBox(withHarmonyConfig(getDefaultConfig(__dirname)));
```

运行 prebuild、原生构建和 Metro 时都要设置 `EXPO_UNSTABLE_LOG_BOX=1`，也可以设为 `true`。LogBox 只在 debug 构建中显示。修改开关后，需要重新生成并构建应用。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
