# @expo-harmony/expo-system-ui

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-system-ui)

为 HarmonyOS 上的 React Native 应用提供 Expo SystemUI 的原生实现，支持通过配置插件设置 Root View 背景色和浅色、深色模式，并在运行时读取或更新窗口背景色，与官方同版本的 expo-system-ui 配套使用。

如果需要在 JavaScript 启动前应用 Root View 背景色和界面模式，必须在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-system-ui`，并通过 `harmony` 或 Expo 顶层字段声明对应配置：

```json
{
  "expo": {
    "plugins": ["@expo-harmony/expo-system-ui"],
    "harmony": {
      "bundleName": "com.example.app",
      "backgroundColor": "#FFFFFF",
      "userInterfaceStyle": "automatic"
    }
  }
}
```

`userInterfaceStyle` 支持 `light`、`dark` 和 `automatic`。未提供 HarmonyOS 专用值时，插件会回退读取 Expo 顶层的 `backgroundColor` 和 `userInterfaceStyle`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
