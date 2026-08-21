# @expo-harmony/expo-navigation-bar

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-navigation-bar)

为 HarmonyOS 上的 React Native 应用提供 Expo NavigationBar 的原生实现和 JavaScript 适配，支持设置导航栏背景色、按钮样式、显示状态和布局位置，并可通过配置插件在 JavaScript 启动前应用初始设置，与官方同版本的 expo-navigation-bar 配套使用。

如果需要在 JavaScript 启动前应用导航栏初始设置，必须在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-navigation-bar`：

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

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
