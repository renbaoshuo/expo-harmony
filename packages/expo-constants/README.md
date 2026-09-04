# @expo-harmony/expo-constants

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-constants)

为 HarmonyOS 上的 React Native 应用提供 Expo Constants 的原生实现，用于读取应用配置、设备与系统信息以及 HarmonyOS 平台元数据，与官方同版本的 `expo-constants` 配套使用。

安装本包后必须在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-constants`，并启用 `@expo-harmony/prebuild-config`：

```json
{
  "expo": {
    "plugins": [
      "@expo-harmony/expo-constants",
      "@expo-harmony/prebuild-config"
    ]
  }
}
```

应用代码仍从官方 `expo-constants` 包导入，HarmonyOS 原生模块由 Expo Modules 自动链接；Constants Config Plugin 会将公开的 Expo 配置写入应用资源，供运行时读取。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
