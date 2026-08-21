# @expo-harmony/expo-blur

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-blur)

为 HarmonyOS 上的 React Native 应用提供 `expo-blur` 原生实现。

## 平台说明

- `intensity` 会限制在 `0...100`，并作为 HarmonyOS 原生模糊材质的强度比例；它不是 Android 的像素模糊半径。
- `tint` 会映射到 HarmonyOS 的原生 `BlurStyle` 与亮色/暗色模式。
- `blurMethod`、`blurReductionFactor`、`blurTarget` 是上游 `expo-blur` 标注的 Android 专属能力，在 HarmonyOS 上不生效。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
