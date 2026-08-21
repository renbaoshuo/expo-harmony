# @expo-harmony/expo-splash-screen

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-splash-screen)

为 HarmonyOS 上的 React Native 应用提供 Expo SplashScreen 的原生实现，支持通过配置插件设置启动画面的图片、背景色及深色模式资源，并在运行时控制自动隐藏、手动隐藏和淡出过渡，与官方同版本的 expo-splash-screen 配套使用。

如果需要配置 HarmonyOS 原生启动画面，必须在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-splash-screen`：

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

`resizeMode` 支持 `contain`、`cover` 和 `native`。重新 prebuild 后，插件会将图片、背景色和深色模式资源写入 HarmonyOS 原生工程。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
