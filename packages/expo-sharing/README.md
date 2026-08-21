# @expo-harmony/expo-sharing

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-sharing)

为 HarmonyOS 上的 React Native 应用提供 Expo Sharing 的原生实现，支持校验并分享本地文件、根据 MIME 类型或扩展名匹配系统分享目标、接收 Share Kit 传入的数据，以及拉起 HarmonyOS 系统原生分享面板，与官方同版本的 expo-sharing 配套使用。

如果需要接收其他应用的分享，必须在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-sharing`：

```json
{
  "expo": {
    "plugins": ["@expo-harmony/expo-sharing"]
  }
}
```

另外，HarmonyOS Share Kit 没有分享面板标题选项，因此传入 `dialogTitle` 不会生效。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
