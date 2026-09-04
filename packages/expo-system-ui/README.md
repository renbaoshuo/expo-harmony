# @expo-harmony/expo-system-ui

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-system-ui)

为 HarmonyOS 上的 React Native 应用提供 Expo SystemUI 的原生实现，与官方同版本的 `expo-system-ui` 配套使用。支持运行时读取和设置窗口背景色，以及通过配置插件设置初始背景色和浅色、深色或跟随系统的界面模式。

如果需要在 JavaScript 启动前应用背景色和界面模式，请在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-system-ui`：

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

`harmony.backgroundColor` 和 `harmony.userInterfaceStyle` 优先于 Expo 顶层的同名配置。`userInterfaceStyle` 支持 `light`、`dark` 和 `automatic`，默认值为 `light`。

仅通过 `SystemUI.getBackgroundColorAsync` 和 `SystemUI.setBackgroundColorAsync` 在运行时读取和设置背景色时，不需要配置插件。运行时设置的背景色会持久化；传入 `null` 会清除保存的背景色，并恢复当前界面模式的默认背景色。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
