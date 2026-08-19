# @expo-harmony/config-plugins

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/config-plugins)

为 Expo Config Plugins 提供 HarmonyOS 平台扩展，包括 `expo.harmony` 配置类型、Harmony Base Mods、原生工程文件与资源 Mod、路径解析及插件资源归属管理。

## 安装

```sh
npm install @expo-harmony/config-plugins
```

## 配置类型

在 `app.config.js` 中可使用 `defineExpoHarmonyConfig` 声明 HarmonyOS 配置：

```js
const { defineExpoHarmonyConfig } = require('@expo-harmony/config-plugins');

module.exports = defineExpoHarmonyConfig({
  name: 'Example',
  slug: 'example',
  platforms: ['ios', 'android', 'harmony'],
  plugins: ['@expo-harmony/prebuild-config'],
  harmony: {
    bundleName: 'com.example.app',
    versionCode: 1,
  },
});
```

## 编写 HarmonyOS 配置插件

使用对应的 Mod 修改生成后的 HarmonyOS 原生配置。例如，向 `module.json5` 添加信息：

```js
const { withModuleJson } = require('@expo-harmony/config-plugins');

module.exports = function withExampleMetadata(config) {
  return withModuleJson(config, (mod) => {
    const moduleConfig = mod.modResults.module || {};
    const metadata = Array.isArray(moduleConfig.metadata)
      ? moduleConfig.metadata
      : [];

    mod.modResults.module = {
      ...moduleConfig,
      metadata: [...metadata, { name: 'example.enabled', value: 'true' }],
    };
    return mod;
  });
};
```

包内提供 JSON、文本、资源、自动链接等 Harmony Mod。常用入口包括 `withModuleJson`、`withAppJson`、`withStrings`、`withColors`、`withMedia`、`withCMakeLists`、`withHarmonyDangerousMod` 等，可以在 export 中查看完整列表。

`withHarmonyBaseMods` 负责注册所有 Harmony Base Mods，通常由 `@expo-harmony/prebuild-config` 调用，应用和第三方配置插件无需重复注册。`registerHarmonyConfigPlugin` 可声明插件拥有的资源或 Ability 字段，避免多个插件在生成阶段产生归属冲突。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
