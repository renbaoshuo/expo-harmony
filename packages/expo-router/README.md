# @expo-harmony/expo-router

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-router)

为 HarmonyOS 上的 React Native 应用提供 Expo Router 的原生集成载体，组合 Linking、Screens 和 Safe Area，并支持按需接入 Gesture Handler、Reanimated 和 Worklets，与官方同版本的 expo-router 配套使用。

安装官方 Expo Router 和 HarmonyOS 集成包：

```sh
npm install expo-router @expo-harmony/expo-router
```

应用入口继续使用官方 `expo-router/entry`，业务代码也应始终从 `expo-router` 导入，不要直接导入 `@expo-harmony/expo-router`：

```json
{
  "main": "expo-router/entry"
}
```

在 `app.json` 中注册官方 `expo-router` Config Plugin。使用 Expo Harmony 预构建时，应将 `@expo-harmony/prebuild-config` 放在其他 Config Plugin 之后：

```json
{
  "expo": {
    "scheme": "example",
    "plugins": [
      "expo-router",
      "@expo-harmony/prebuild-config"
    ],
    "harmony": {
      "bundleName": "com.example.app"
    }
  }
}
```

`@expo-harmony/expo-router` 不提供独立的 Config Plugin；安装该包即表示启用 HarmonyOS 原生集成。如果应用需要手势或动画能力，还需同时安装对应的官方 JavaScript 包和匹配版本的 `@react-native-ohos/react-native-gesture-handler`、`@react-native-ohos/react-native-reanimated`、`@react-native-ohos/react-native-worklets` 原生产物。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
