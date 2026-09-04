# @expo-harmony/expo-linking

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-linking)

为 HarmonyOS 上的 React Native 应用提供 Expo Linking 的原生实现，与官方同版本的 `expo-linking` 配套使用。支持读取初始链接、订阅 Deep Link 事件、打开 URL、判断 URL 是否可处理，以及打开应用设置页。

`http`、`https`、`tel`、`sms` 和应用自身 scheme 会在预构建时自动加入可查询列表。如果需要用 `canOpenURL` 查询其他 scheme，请在 `app.json` 的 `expo.harmony.querySchemes` 中声明：

```json
{
  "expo": {
    "harmony": {
      "querySchemes": ["my-custom-scheme"]
    }
  }
}
```

电话和短信链接需要设备支持对应的系统能力。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
