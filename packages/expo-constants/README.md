# @expo-harmony/expo-constants

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-constants)

为 HarmonyOS 上的 React Native 应用提供 Expo Constants 的原生实现，用于读取应用配置、设备与系统信息以及 HarmonyOS 平台元数据，与官方同版本的 expo-constants 配套使用。

安装本包后必须在 `app.json` 注册相关 Config Plugin，且 Constants 插件必须放在 prebuild 插件之前：

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

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
