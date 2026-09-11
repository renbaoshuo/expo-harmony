# expo-harmony

**让 Expo 驱动的 React Native 应用程序在 HarmonyOS 上运行。**

- 能够使开发者以极少的代码改动，复用现有 Expo 项目的业务代码为应用增加 HarmonyOS 支持。
- 提供众多常用 Expo 模块的 HarmonyOS 实现，减少开发者自行编写原生适配代码的工作量。
- 提供从开发调试到构建打包的完整工具链，支持环境诊断、原生工程生成、HAP 构建、设备安装、应用启动等多项能力。
- 支持 [Expo CNG](https://docs.expo.dev/workflow/continuous-native-generation/)，通过配置生成 HarmonyOS 原生工程，省去人工维护的繁杂流程，也不需要将原生工程在仓库中手动维护，还支持通过 [patch-project](./packages/patch-project/README.md) 自定义可持久化地修改生成后的原生工程。[查看示例工程](https://github.com/renbaoshuo/expo-harmony/tree/master/apps/demo)。
- 支持 [Autolinking](https://docs.expo.dev/modules/autolinking/)，自动链接 Expo 模块和 RNOH 原生模块，无需逐个注册模块、配置构建依赖。
- 支持 [Expo Modules API](https://docs.expo.dev/modules/overview/)，可用 ArkTS 编写原生模块和视图组件，并提供脚手架，为已有 Expo 模块补充 HarmonyOS 支持。

[**查阅快速开始文档 >>**](./docs/QuickStart.md)

> - <small>GitHub 上的主线仓库：[github.com/renbaoshuo/expo-harmony](https://github.com/renbaoshuo/expo-harmony)</small>
> - <small>AtomGit 上的镜像仓库：[atomgit.com/baoshuo/expo-harmony](https://atomgit.com/baoshuo/expo-harmony)</small>

[![G-Star Selected by AtomGit](https://atomgit.com/baoshuo/expo-harmony/star/new_badge.svg)](https://atomgit.com/baoshuo/expo-harmony)

本库目前适配：Expo SDK 55 + RNOH 0.84.1。

## Supported Libraries

已经移植的库都发布在 `@expo-harmony/` 下，具体列表如下：

- [expo-app-metrics](./packages/expo-app-metrics/)：采集应用启动耗时、帧率与内存使用等性能指标。
- [expo-application](./packages/expo-application/)：获取原生应用的 ID、名称和构建版本等信息。
- [expo-asset](./packages/expo-asset/)：下载资源并在其他库中使用。
- [expo-audio](./packages/expo-audio/)：提供音频播放与录制的 API。
- [expo-background-fetch](./packages/expo-background-fetch/)：执行后台抓取任务。
- [expo-background-task](./packages/expo-background-task/)：运行后台任务。
- [expo-battery](./packages/expo-battery/)：获取设备电池信息并监听相关事件。
- [expo-blob](./packages/expo-blob/)：符合 Web 标准的 React Native Blob 实现。
- [expo-blur](./packages/expo-blur/)：模糊其下方所有内容的 React 组件。
- [expo-brightness](./packages/expo-brightness/)：获取和设置屏幕亮度。
- [expo-calendar](./packages/expo-calendar/)：访问系统日历、事件、提醒及相关记录。
- [expo-camera](./packages/expo-camera/)：访问设备摄像头。
- [expo-cellular](./packages/expo-cellular/)：获取用户蜂窝网络服务提供商信息。
- [expo-clipboard](./packages/expo-clipboard/)：读取和写入剪贴板内容。
- [expo-constants](./packages/expo-constants/)：获取在应用整个安装期间保持不变的系统信息。
- [expo-contacts](./packages/expo-contacts/)：访问手机的系统联系人。
- [expo-crypto](./packages/expo-crypto/)：通用的加密操作。
- [expo-device](./packages/expo-device/)：获取设备硬件相关的系统信息。
- [expo-fetch](./packages/expo-fetch/)：提供符合 WinterCG 规范的 Fetch API。
- [expo-file-system](./packages/expo-file-system/)：访问设备上的本地文件系统。
- [expo-font](./packages/expo-font/)：在运行时加载字体并在 React Native 组件中使用。
- [expo-haptics](./packages/expo-haptics/)：访问系统的振动与触感反馈效果。
- [expo-intent-launcher](./packages/expo-intent-launcher/)：启动系统 Intent。
- [expo-keep-awake](./packages/expo-keep-awake/)：在渲染时阻止屏幕休眠的 React 组件。
- [expo-linear-gradient](./packages/expo-linear-gradient/)：渲染渐变视图的 React 组件。
- [expo-linking](./packages/expo-linking/)：创建并打开通用深度链接。
- [expo-live-photo](./packages/expo-live-photo/)：显示实况照片（Live Photo）。
- [expo-location](./packages/expo-location/)：读取地理位置、轮询当前位置或订阅位置更新事件。
- [expo-module-scripts](./packages/expo-module-scripts/)：为 HarmonyOS 下的 Expo Module 提供构建与打包命令支持。
- [expo-modules-autolinking](./packages/expo-modules-autolinking/)：自动链接 Expo 模块和 RNOH 原生模块。
- [expo-modules-core](./packages/expo-modules-core/)：提供 Expo Modules 所需的原生运行时。
- [expo-navigation-bar](./packages/expo-navigation-bar/)：与系统导航栏进行交互。
- [expo-network](./packages/expo-network/)：获取设备网络信息，如 IP 地址、MAC 地址和飞行模式状态。
- [expo-print](./packages/expo-print/)：提供打印功能。
- [expo-router](./packages/expo-router/)：面向 React Native 和 Web 应用的基于文件的路由库。
- [expo-sharing](./packages/expo-sharing/)：与其他应用分享和接收数据。
- [expo-splash-screen](./packages/expo-splash-screen/)：控制原生启动画面的显示行为。
- [expo-status-bar](./packages/expo-status-bar/)：提供与 React Native StatusBar 一致的接口，但其默认值更适合 Expo 环境。
- [expo-system-ui](./packages/expo-system-ui/)：与系统 UI 元素进行交互。
- [expo-task-manager](./packages/expo-task-manager/)：支持可在后台运行的任务。

可以查看 [快速开始](./docs/QUICK_START.md) 获得接入教程。

更多 Expo 库正在移植中，也欢迎贡献更多移植！

> <small>Note: 对于 AtomGit 的用户，烦请移步 [GitHub 仓库](https://github.com/renbaoshuo/expo-harmony) 提起 [Pull Request](https://github.com/renbaoshuo/expo-harmony/pulls)。您可以正常在 AtomGit 上发起 issue 提交问题反馈。</small>

**如果您觉得这个库有帮助到您，请在页面上方给这个仓库点亮一个 Star 🌟～**

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the [MIT](./LICENSE) License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
