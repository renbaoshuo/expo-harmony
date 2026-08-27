# @expo-harmony/template

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/template)

为 Expo 项目提供 HarmonyOS 原生工程模板，包含 AppScope、Entry 模块、Hvigor、CMake 和 RNOH 宿主代码，适配 Expo SDK 55、React Native 0.84.1 和 RNOH 0.84.1。

该模板由 `@expo-harmony/prebuild-config` 和 `@expo-harmony/cli` 管理，通常无需在应用中直接使用。配置好预构建插件后，运行以下命令生成或更新 `harmony` 原生工程：

```sh
npx expo-harmony prebuild
```

## 说明

模板只包含 Expo Modules Core 和 HarmonyOS 构建所需的基础依赖。应用使用其他 Expo 功能时，需要同时安装对应的官方 JavaScript 包和 `@expo-harmony/*` 原生包，预构建阶段会自动发现并链接这些模块。

模板中的应用名称、包名和 Ability 等内容均为占位值，最终结果由 `@expo-harmony/prebuild-config` 根据 Expo 配置生成。签名密钥、密码、绝对路径、OHPM 缓存、Bundle 和 HAP 等本地或构建产物不会包含在模板中。

原生构建需要 Node.js 20 或更高版本，以及可用的 HarmonyOS SDK/NDK、OHPM 和 Hvigor。Release 构建会通过项目本地的 `@expo-harmony/cli` 生成 Hermes Bundle；如需指定 Node.js 可执行文件，可设置 `EXPO_HARMONY_NODE`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
