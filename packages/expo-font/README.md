# @expo-harmony/expo-font

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-font)

为 HarmonyOS 上的 React Native 应用提供 Expo Font 的原生实现，与官方同版本的 `expo-font` 配套使用。支持运行时加载和注册自定义字体、将文字渲染为图片，以及通过配置插件预先打包字体资源。

如果需要在预构建时将字体打包到 HarmonyOS 应用中，请在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-font`：

```json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-font",
        {
          "fonts": ["./assets/fonts/Inter-Regular.ttf"]
        }
      ]
    ]
  }
}
```

仅通过 `Font.loadAsync` 在运行时动态加载字体时，不需要在 `app.json` 中配置字体路径。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
