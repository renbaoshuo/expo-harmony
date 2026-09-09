# expo-harmony

**让 Expo 驱动的 React Native 应用程序在 HarmonyOS 上运行。**

- 复用现有 Expo 项目的业务代码，以少量代码改动为应用增加 HarmonyOS 支持。
- 提供从开发调试到构建打包的工具链，支持环境诊断、原生工程生成、HAP 构建、设备安装和应用启动。
- 支持 [Expo CNG](https://docs.expo.dev/workflow/continuous-native-generation/)，通过配置生成 HarmonyOS 原生工程，省去人工维护的繁杂流程。
- 支持 [Autolinking](https://docs.expo.dev/modules/autolinking/)，自动链接 Expo 模块和 RNOH 原生模块，无需逐个注册模块、配置构建依赖。
- 支持 [Expo Modules API](https://docs.expo.dev/modules/overview/)，可用 ArkTS 编写原生模块和视图组件，并提供脚手架，为已有 Expo 模块补充 HarmonyOS 支持。

[**查阅快速开始文档 >>**](./docs/QUICK_START.md)

AtomGit 上的镜像仓库：[atomgit.com/baoshuo/expo-harmony](https://atomgit.com/baoshuo/expo-harmony)

[![G-Star Selected by AtomGit](https://atomgit.com/baoshuo/expo-harmony/star/new_badge.svg)](https://atomgit.com/baoshuo/expo-harmony)

本库目前适配：Expo SDK 55 + RNOH 0.84.1。

## Supported Libraries

已经移植的库都发布在 `@expo-harmony/` 下，具体列表如下：

- [expo-app-metrics](./packages/expo-app-metrics/)
- [expo-application](./packages/expo-application/)
- [expo-asset](./packages/expo-asset/)
- [expo-audio](./packages/expo-audio/)
- [expo-background-fetch](./packages/expo-background-fetch/)
- [expo-background-task](./packages/expo-background-task/)
- [expo-battery](./packages/expo-battery/)
- [expo-blob](./packages/expo-blob/)
- [expo-blur](./packages/expo-blur/)
- [expo-brightness](./packages/expo-brightness/)
- [expo-camera](./packages/expo-camera/)
- [expo-cellular](./packages/expo-cellular/)
- [expo-clipboard](./packages/expo-clipboard/)
- [expo-constants](./packages/expo-constants/)
- [expo-crypto](./packages/expo-crypto/)
- [expo-fetch](./packages/expo-fetch/)
- [expo-file-system](./packages/expo-file-system/)
- [expo-font](./packages/expo-font/)
- [expo-haptics](./packages/expo-haptics/)
- [expo-keep-awake](./packages/expo-keep-awake/)
- [expo-linear-gradient](./packages/expo-linear-gradient/)
- [expo-linking](./packages/expo-linking/)
- [expo-location](./packages/expo-location/)
- [expo-module-scripts](./packages/expo-module-scripts/)
- [expo-modules-autolinking](./packages/expo-modules-autolinking/)
- [expo-modules-core](./packages/expo-modules-core/)
- [expo-navigation-bar](./packages/expo-navigation-bar/)
- [expo-network](./packages/expo-network/)
- [expo-print](./packages/expo-print/)
- [expo-router](./packages/expo-router/)
- [expo-sharing](./packages/expo-sharing/)
- [expo-splash-screen](./packages/expo-splash-screen/)
- [expo-status-bar](./packages/expo-status-bar/)
- [expo-system-ui](./packages/expo-system-ui/)
- [expo-task-manager](./packages/expo-task-manager/)

可以查看 [快速开始](./docs/QUICK_START.md) 获得接入教程。

更多 Expo 库正在移植中，也欢迎贡献更多移植！

**如果您觉得这个库有帮助到您，请在页面上方给这个仓库点亮一个 Star 🌟～**

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the [MIT](./LICENSE) License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
