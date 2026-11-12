# @react-native-ohos/react-native-screens

为 Expo Router 提供基于官方 `@react-native-ohos/react-native-screens@4.10.0-beta.4` 的兼容产物，配套 Screens JS `4.26.2` 和 RNOH `0.86.1`。

目录和补丁名使用 `scope__package`，将完整 npm 包名 `@react-native-ohos/react-native-screens` 展开为 `react-native-ohos__react-native-screens`。补丁名还包含上游版本及 JS / HAR 目标。

```sh
yarn workspace @expo-harmony/expo-router build
```

构建脚本复制 Router 安装的官方源码，调用 `@expo-harmony/expo-module-scripts/patch` 的 `applyPatchFile()` 分别处理 JS 源码和解压后的 HAR，再生成 `build/`。该目录随 Router 包发布，消费者可直接使用其中的产物。

兼容层提供实验栈、预加载及屏幕生命周期、SafeAreaView。Metro 从此目录解析 Screens 的 JS 入口，autolinking 使用其中的 `build/harmony/screens.har`。
