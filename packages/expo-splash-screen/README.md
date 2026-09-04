# @expo-harmony/expo-splash-screen

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-splash-screen)

为 HarmonyOS 上的 React Native 应用提供 Expo SplashScreen 的原生实现，与官方同版本的 `expo-splash-screen` 配套使用。支持控制启动画面的自动隐藏、手动隐藏和淡出过渡，以及通过配置插件设置启动图片、背景色和深色模式资源。

如果需要在预构建时配置 HarmonyOS 原生启动画面，请在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-splash-screen`：

```json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-splash-screen",
        {
          "backgroundColor": "#FFFFFF",
          "image": "./assets/splash.png",
          "imageWidth": 160,
          "resizeMode": "contain",
          "dark": {
            "backgroundColor": "#000000",
            "image": "./assets/splash-dark.png"
          }
        }
      ]
    ]
  }
}
```

`resizeMode` 支持 `contain`、`cover` 和 `native`。修改配置后需要重新 prebuild，使用 `dark` 资源跟随系统外观时，请将 `expo.userInterfaceStyle` 设置为 `automatic`。

运行时可通过 `SplashScreen.preventAutoHideAsync()` 保持启动画面，待应用准备就绪后调用 `SplashScreen.hide()` 或 `SplashScreen.hideAsync()` 隐藏，也可通过 `SplashScreen.setOptions()` 设置淡出效果和时长。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
