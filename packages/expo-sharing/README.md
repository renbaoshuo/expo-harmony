# @expo-harmony/expo-sharing

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-sharing)

为 HarmonyOS 上的 React Native 应用提供 Expo Sharing 的原生实现，与官方同版本的 `expo-sharing` 配套使用。支持通过系统分享面板分享本地文件、接收其他应用分享的文本、链接和文件，以及将接收的文件复制到应用缓存中。

## 安装

```bash
npm install @expo-harmony/expo-sharing expo-modules-core@55.0.25 expo-sharing@55.0.20
```

如果需要接收其他应用的分享，请在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-sharing`：

```json
{
  "expo": {
    "plugins": ["@expo-harmony/expo-sharing"]
  }
}
```

插件默认接收文本、文件和 HTTP(S) 链接，单次最多接收 50 个文件。可以通过 `utds`、`maxFileSupported`、`allowMultiple` 和 `abilityName` 调整接收类型、文件数量、多文件支持和目标 Ability；目标 Ability 必须已存在并设置 `exported: true`。解析接收的文件时，单个文件上限为 100 MiB，单次分享的总大小上限为 250 MiB。

重复分享同一文件会刷新接收结果。解析失败后可调用 `refreshSharePayloads` 重试；清空接收状态不会删除已经返回的缓存文件 URI。链接解析保留原始 `value`，`contentUri` 指向重定向后的地址。

仅通过 `Sharing.shareAsync` 分享本地文件时，不需要配置插件。HarmonyOS 系统分享面板不支持自定义标题，`dialogTitle` 参数不会生效。

本包的原生实现依赖宿主 Ability 的生命周期事件，对应的订阅器已在包内声明，业务代码无需额外处理。CNG 工程由 prebuild 自动生成所需入口；Bare 工程需按 [接入说明](https://github.com/renbaoshuo/expo-harmony/blob/master/docs/BareInstallation.md) 手动接入 AbilityStage 和 ExpoRNAbility。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
