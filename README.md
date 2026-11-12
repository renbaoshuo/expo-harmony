# expo-harmony

**让 Expo 驱动的 React Native 应用程序在 HarmonyOS 上运行。**

- 能够使开发者以极少的代码改动，复用现有 Expo 项目的业务代码为应用增加 HarmonyOS 支持。
- 提供众多常用 Expo 模块的 HarmonyOS 实现，减少开发者自行编写原生适配代码的工作量。
- 提供从开发调试到构建打包的完整工具链，支持环境诊断、原生工程生成、HAP 构建、设备安装、应用启动等多项能力。
- 支持 [Expo CNG](https://docs.expo.dev/workflow/continuous-native-generation/)，通过配置生成 HarmonyOS 原生工程，省去人工维护的繁杂流程，也不需要将原生工程在仓库中手动维护，还支持通过 [patch-project](./packages/patch-project/README.md) 自定义可持久化地修改生成后的原生工程。[查看示例工程](https://github.com/renbaoshuo/expo-harmony/tree/master/apps/demo)。
- 支持 Bare Installation，允许开发者在已有的 RNOH 原生工程中集成 Expo Harmony。[查看示例工程](https://github.com/renbaoshuo/expo-harmony/tree/master/apps/bare)。
- 支持 [Autolinking](https://docs.expo.dev/modules/autolinking/)，自动链接 Expo 模块和 RNOH 原生模块，无需逐个注册模块、配置构建依赖。
- 支持 [Expo Modules API](https://docs.expo.dev/modules/overview/)，可用 ArkTS 编写原生模块和 UI 组件，并提供脚手架，为已有 Expo 模块补充 HarmonyOS 支持。

[**查阅快速开始文档 >>**](./docs/QuickStart.md)

> - <small>GitHub 上的主线仓库：[github.com/renbaoshuo/expo-harmony](https://github.com/renbaoshuo/expo-harmony)</small>
> - <small>AtomGit 上的镜像仓库：[atomgit.com/baoshuo/expo-harmony](https://atomgit.com/baoshuo/expo-harmony)</small>

[![G-Star Selected by AtomGit](https://atomgit.com/baoshuo/expo-harmony/star/new_badge.svg)](https://atomgit.com/baoshuo/expo-harmony)

本库目前适配 Expo SDK 55 + RNOH 0.84.1。对于 Expo SDK 57 + RNOH 0.86 的适配，待 RNOH 上游相关三方库完成适配后会尽快跟进。

## Supported Libraries

已经移植的库都发布在 `@expo-harmony/` 下，具体列表如下：

- [expo](./packages/expo/)：提供 Expo 核心包的支持。
- [expo-age-range](./packages/expo-age-range/)：访问用户的年龄范围信息。
- [expo-app-integrity](./packages/expo-app-integrity/)：提供对 App Integrity 服务的访问。
- [expo-app-metrics](./packages/expo-app-metrics/)：采集应用启动耗时、帧率与内存使用等性能指标。
- [expo-application](./packages/expo-application/)：获取原生应用的 ID、名称和构建版本等信息。
- [expo-asset](./packages/expo-asset/)：下载资源并在其他库中使用。
- [expo-audio](./packages/expo-audio/)：提供音频播放与录制的 API。
- [expo-auth-session](./packages/expo-auth-session/)：处理基于浏览器的身份认证。
- [expo-background-fetch](./packages/expo-background-fetch/)：执行后台抓取任务。
- [expo-background-task](./packages/expo-background-task/)：运行后台任务。
- [expo-battery](./packages/expo-battery/)：获取设备电池信息并监听相关事件。
- [expo-blob](./packages/expo-blob/)：符合 Web 标准的 React Native Blob 实现。
- [expo-blur](./packages/expo-blur/)：模糊其下方所有内容的 React 组件。
- [expo-brightness](./packages/expo-brightness/)：获取和设置屏幕亮度。
- [expo-build-properties](./packages/expo-build-properties/)：配置 HarmonyOS 的 SDK、ABI、原生编译器、SO 打包与 release 构建选项。
- [expo-calendar](./packages/expo-calendar/)：访问系统日历、事件、提醒及相关记录。
- [expo-camera](./packages/expo-camera/)：访问设备摄像头。
- [expo-cellular](./packages/expo-cellular/)：获取用户蜂窝网络服务提供商信息。
- [expo-checkbox](./packages/expo-checkbox/)：提供基础复选框功能的 React 组件。
- [expo-clipboard](./packages/expo-clipboard/)：读取和写入剪贴板内容。
- [expo-constants](./packages/expo-constants/)：获取在应用整个安装期间保持不变的系统信息。
- [expo-contacts](./packages/expo-contacts/)：访问手机的系统联系人。
- [expo-crypto](./packages/expo-crypto/)：通用的加密操作。
- [expo-dev-client](./packages/expo-dev-client/)：提供 Expo 开发客户端入口，聚合开发启动器与开发菜单。
- [expo-dev-launcher](./packages/expo-dev-launcher/)：Expo 开发构建的原生启动器，支持项目地址、最近项目、mDNS 发现和系统扫码。
- [expo-dev-menu](./packages/expo-dev-menu/)：Expo 开发菜单的原生实现，提供菜单界面、FAB、偏好和源码浏览。
- [expo-dev-menu-interface](./packages/expo-dev-menu-interface/)：提供 Expo Dev Menu 的管理、桥接、宿主代理和键盘响应接口定义。
- [expo-device](./packages/expo-device/)：获取设备硬件相关的系统信息。
- [expo-document-picker](./packages/expo-document-picker/)：通过系统界面选择文档并读取文件信息。
- [expo-eas-client](./packages/expo-eas-client/)：提供安装级的 EAS 客户端 ID 及由其派生的采样值。
- [expo-file-system](./packages/expo-file-system/)：访问设备上的本地文件系统。
- [expo-font](./packages/expo-font/)：在运行时加载字体并在 React Native 组件中使用。
- [expo-haptics](./packages/expo-haptics/)：访问系统的振动与触感反馈效果。
- [expo-image](./packages/expo-image/)：显示与缓存图片，支持占位图、动画和原生图片引用。
- [expo-image-loader](./packages/expo-image-loader/)：为 ArkTS 模块提供按地址加载图片的服务，没有 JavaScript 接口。
- [expo-image-manipulator](./packages/expo-image-manipulator/)：提供在本地文件系统上处理图片的 API。
- [expo-image-picker](./packages/expo-image-picker/)：调用系统界面从图库选择图片和视频，或使用相机拍照。
- [expo-intent-launcher](./packages/expo-intent-launcher/)：启动系统 Intent。
- [expo-json-utils](./packages/expo-json-utils/)：按字段类型读取 JSON 对象中的值。
- [expo-keep-awake](./packages/expo-keep-awake/)：在渲染时阻止屏幕休眠的 React 组件。
- [expo-linear-gradient](./packages/expo-linear-gradient/)：渲染渐变视图的 React 组件。
- [expo-linking](./packages/expo-linking/)：创建并打开通用深度链接。
- [expo-live-photo](./packages/expo-live-photo/)：显示实况照片（Live Photo）。
- [expo-local-authentication](./packages/expo-local-authentication/)：通过面部或指纹扫描认证用户。
- [expo-localization](./packages/expo-localization/)：读取语言、地区、时区、日历和货币等本地化信息。
- [expo-location](./packages/expo-location/)：读取地理位置、轮询当前位置或订阅位置更新事件。
- [expo-mail-composer](./packages/expo-mail-composer/)：提供使用系统界面撰写和发送电子邮件的功能。
- [expo-manifests](./packages/expo-manifests/)：提供 Expo 更新清单的原生模型，可在原生代码中读取和校验。
- [expo-media-library](./packages/expo-media-library/)：访问设备上的图片和视频等媒体资源。
- [expo-mesh-gradient](./packages/expo-mesh-gradient/)：将类似 SwiftUI 的 MeshGradient View 暴露给 React Native 的模块。
- [@expo/config](./packages/expo__config/)：用于操作 app.json 的库。
- [@expo/config-types](./packages/expo__config-types/)：Expo 配置对象 app.config.ts 的类型。
- [@expo/devtools](./packages/expo__devtools/)：Expo 的 DevTools 插件辅助工具。
- [@expo/dom-webview](./packages/expo__dom-webview/)：专为 Expo DOM 组件设计的 WebView。
- [@expo/env](./packages/expo__env/)：把 .env 文件中的环境变量注入 process.env。
- [@expo/fingerprint](./packages/expo__fingerprint/)：为 React Native 工程生成指纹。
- [@expo/image-utils](./packages/expo__image-utils/)：供 Expo CLI 处理图片的包。
- [@expo/json-file](./packages/expo__json-file/)：读写和修改 JSON 文件的模块。
- [@expo/local-build-cache-provider](./packages/expo__local-build-cache-provider/)：Expo 的本地构建缓存提供者。
- [@expo/log-box](./packages/expo__log-box/)：使用官方 Expo LogBox 界面显示 HarmonyOS 开发构建中的原生与 JavaScript 错误。
- [@expo/metro-runtime](./packages/expo__metro-runtime/)：让 Metro 打包器高级特性生效的工具。
- [@expo/package-manager](./packages/expo__package-manager/)：在项目中查找和安装依赖包。
- [@expo/pkcs12](./packages/expo__pkcs12/)：Node.js 的 PKCS#12 工具。
- [@expo/require-utils](./packages/expo__require-utils/)：可复用的 require 与 Node 模块解析工具。
- [@expo/router-server](./packages/expo__router-server/)：为 Expo Router 项目提供静态渲染与服务端 API。
- [@expo/schema-utils](./packages/expo__schema-utils/)：可复用的 JSON Schema（Draft 04）校验库。
- [@expo/schemer](./packages/expo__schemer/)：Expo 的集中式 schema 校验库。
- [expo-module-scripts](./packages/expo-module-scripts/)：为 HarmonyOS 下的 Expo Module 提供构建与打包命令支持。
- [expo-modules-autolinking](./packages/expo-modules-autolinking/)：自动链接 Expo 模块和 RNOH 原生模块。
- [expo-modules-core](./packages/expo-modules-core/)：提供 Expo Modules 所需的原生运行时。
- [expo-navigation-bar](./packages/expo-navigation-bar/)：与系统导航栏进行交互。
- [expo-network](./packages/expo-network/)：获取设备网络信息，如 IP 地址、MAC 地址和飞行模式状态。
- [expo-notifications](./packages/expo-notifications/)：提供获取推送通知 token 以及展示、调度、接收和响应通知的 API。
- [expo-print](./packages/expo-print/)：提供打印功能。
- [expo-processing](./packages/expo-processing/)：在 Expo 中使用 Processing.js 的工具。
- [expo-router](./packages/expo-router/)：面向 React Native 和 Web 应用的基于文件的路由库。
- [expo-screen-capture](./packages/expo-screen-capture/)：阻止应用界面被截屏或录屏，并监听截图事件。
- [expo-screen-orientation](./packages/expo-screen-orientation/)：管理设备的屏幕方向。
- [expo-secure-store](./packages/expo-secure-store/)：在设备本地加密保存键值对数据。
- [expo-sensors](./packages/expo-sensors/)：访问设备的加速度计、陀螺仪、磁力计、气压计、环境光、设备运动和计步器。
- [expo-sharing](./packages/expo-sharing/)：与其他应用分享和接收数据。
- [expo-sms](./packages/expo-sms/)：查询短信能力，打开系统短信编辑页并预填收件人与正文。
- [expo-speech](./packages/expo-speech/)：使用系统语音合成能力离线朗读文本，支持音色查询与播放控制。
- [expo-splash-screen](./packages/expo-splash-screen/)：控制原生启动画面的显示行为。
- [expo-sqlite](./packages/expo-sqlite/)：提供对可通过 SQLite API 查询的数据库的访问。
- [expo-standard-web-crypto](./packages/expo-standard-web-crypto/)：W3C Crypto API 的部分实现。
- [expo-status-bar](./packages/expo-status-bar/)：提供与 React Native StatusBar 一致的接口，但其默认值更适合 Expo 环境。
- [expo-store-review](./packages/expo-store-review/)：访问用于应用内评价的原生 API。
- [expo-structured-headers](./packages/expo-structured-headers/)：解析和序列化 Structured Fields（RFC 8941）响应头。
- [expo-symbols](./packages/expo-symbols/)：显示系统 Symbol 图标。
- [expo-system-ui](./packages/expo-system-ui/)：与系统 UI 元素进行交互。
- [expo-task-manager](./packages/expo-task-manager/)：支持可在后台运行的任务。
- [expo-tracking-transparency](./packages/expo-tracking-transparency/)：跟踪应用用户并管理跟踪权限。
- [expo-updates](./packages/expo-updates/)：管理应用代码的远程更新。
- [expo-updates-interface](./packages/expo-updates-interface/)：提供 Updates 控制器、开发启动器与状态订阅的接口定义。
- [expo-video](./packages/expo-video/)：提供在应用中实现视频播放的 API。
- [expo-video-thumbnails](./packages/expo-video-thumbnails/)：从视频文件生成可用作缩略图的图片。
- [expo-web-browser](./packages/expo-web-browser/)：提供对系统浏览器的访问，并支持处理重定向。

可以查看 [快速开始](./docs/QuickStart.md) 获得接入教程。

更多 Expo 库正在移植中，也欢迎贡献更多移植！

> <small>Note: 对于 AtomGit 的用户，烦请移步 [GitHub 仓库](https://github.com/renbaoshuo/expo-harmony) 提起 [Pull Request](https://github.com/renbaoshuo/expo-harmony/pulls)。您可以正常在 AtomGit 上发起 issue 提交问题反馈。</small>

**如果您觉得这个库有帮助到您，请在页面上方给这个仓库点亮一个 Star 🌟～**

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the [MIT](./LICENSE) License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
