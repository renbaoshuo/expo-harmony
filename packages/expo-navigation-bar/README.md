# @expo-harmony/expo-navigation-bar

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-navigation-bar)

为 HarmonyOS 上的 React Native 应用提供 Expo NavigationBar 的原生实现和 JavaScript 适配，与官方同版本的 `expo-navigation-bar` 配套使用。支持读取和设置导航栏背景色、按钮样式、显示状态和布局位置，订阅显示状态变化，以及通过配置插件设置启动时的导航栏外观。

如果需要声明启动时应用的导航栏初始设置，请在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-navigation-bar`：

```json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-navigation-bar",
        {
          "backgroundColor": "#FFFFFF",
          "barStyle": "dark",
          "position": "relative",
          "visibility": "visible"
        }
      ]
    ]
  }
}
```

仅在运行时调用导航栏 API 时，不需要配置插件。HarmonyOS 不支持设置导航栏分隔线颜色、Android 导航栏唤出行为或强制对比度；配置插件也不接受 `borderColor`、`behavior` 和 `enforceContrast` 选项。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
