# @expo-harmony/prebuild-config

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/prebuild-config)

为 Expo 项目提供 HarmonyOS 默认预构建配置，将 `expo.harmony` 转换为可重复生成的原生工程状态。它基于 `@expo-harmony/template` 配置 AppScope、Entry 模块、资源、Hvigor、CMake 和 RNOH 宿主代码，同时完成 Expo 原生模块自动链接并生成 CNG 清单。

## 安装

```sh
npm install @expo-harmony/prebuild-config
```

## 基础用法

在 `app.json` 中启用插件并声明 HarmonyOS 配置：

```json
{
  "expo": {
    "name": "Example",
    "slug": "example",
    "version": "1.0.0",
    "plugins": ["@expo-harmony/prebuild-config"],
    "harmony": {
      "bundleName": "com.example.app",
      "versionCode": 1,
      "deviceTypes": ["phone", "tablet"]
    }
  }
}
```

使用 Expo Harmony CLI 生成或更新原生工程：

```sh
npx expo-harmony prebuild
```

需要使用字体、启动屏或其他 HarmonyOS 配置插件时，应将这些插件放在 `@expo-harmony/prebuild-config` 之前，由本包最后注册 Harmony Base Mods：

```json
{
  "expo": {
    "plugins": [
      "@expo-harmony/expo-font",
      [
        "@expo-harmony/expo-splash-screen",
        {
          "image": "./assets/splash.png",
          "backgroundColor": "#FFFFFF"
        }
      ],
      "@expo-harmony/expo-system-ui",
      "@expo-harmony/prebuild-config"
    ],
    "harmony": {
      "bundleName": "com.example.app"
    }
  }
}
```

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
