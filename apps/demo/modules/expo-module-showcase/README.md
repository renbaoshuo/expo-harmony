# Expo Modules 测试模块

Demo 的本地 Expo module，由 `apps/demo/modules` 自动发现。在首页打开 **Expo Modules 测试**，所有功能都在同一个页面内按卡片手动执行；打开应用不会自动运行测试或重载运行时。

## 目录

- `src/`：三端共用的接口类型、模块加载及原生视图入口。
- `android/`：Kotlin 模块、SharedObject / SharedRef、原生 View 与全屏 Dialog 页面。
- `ios/`：Swift 模块、SharedObject / SharedRef、原生 ExpoView 与 UIViewController 页面。
- `harmony/library/src/main/ets/`：对应的 ArkTS 模块、共享对象、ExpoView 与 ArkUI 原生页面。
- `../../src/expoModules/`：测试页、共享对象卡片、原生组件卡片。页面复用 demo 的 `Panel`、`ActionButton`、`ResultPanel` 和主题颜色。

两个原生模块在各平台的名称均为 `ExpoModuleShowcase`、`ExpoModuleShowcaseConsumer`。后者用于验证原生对象跨模块传递。三端暴露同一套接口，不在 JavaScript 中模拟原生实现。

## 运行

从仓库根目录执行：

```sh
yarn workspace @expo-harmony/demo run:android
yarn workspace @expo-harmony/demo run:ios
yarn workspace expo-module-showcase harmony:build
yarn workspace @expo-harmony/demo run:harmony
```

修改原生代码后需要重新编译开发构建；Harmony 还需先重新生成本地模块 HAR。包安装不会自动调用 Harmony 工具链，Android / iOS 开发无需安装该工具链。Expo Go 不包含本地模块；缺少模块时此页会显示构建提示，其他演示仍可使用。Web 显示平台说明，不执行原生测试。

Harmony 本地构建通过 demo 的 `node_modules/@expo-harmony/expo-modules-core` 链接使用仓库中的 Core HAR，通过项目级 OHPM override 解析依赖；模块自身的依赖声明仍采用版本号。这也保证临时目录中的 `prebuild --check` 能解析同一依赖。

Android / iOS 使用 Expo SDK 55 对应的 React Native 0.83.6 和 React 19.2.0。Harmony 使用 RNOH 0.84.1，Metro 仅在 Harmony 构建中将 `react`（含 JSX 子路径）映射到 `react-harmony`（React 19.2.3），与该平台的 renderer 保持一致。

Harmony release 导出通过 RNOH 解析 `hermes-compiler`（本 demo 为 `250829098.0.9`，HBC 98），避免误用 Android / iOS 的 Hermes 编译器。

`react-native-screens` 统一使用 4.26.2。Harmony 的 Metro 搜索路径包含 Router 工作区的 `node_modules`，以发现 Yarn 隔离安装的 Screens 和 Safe Area 平台实现。

### HarmonyOS 模拟器

可按照[华为模拟器命令行文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)启动已有模拟器。macOS 上 DevEco Studio 的默认路径为：

```sh
/Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator -list -details
/Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator -start '<模拟器名称>' -bootMode coldboot
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc list targets
yarn workspace @expo-harmony/demo run:harmony:release --sync --device <设备 ID>
```

release 构建包含 JS bundle，安装后可直接检查卡片，无需保持 Metro 运行。修改原生代码后使用 `--sync` 重新生成并构建本地模块；检查 release 生成结果时使用 `EXPO_HARMONY_BUILD_TYPE=release yarn workspace @expo-harmony/demo check:harmony`。原生页面会根据系统安全区留出状态栏和导航区域。

## 手动检查

| 卡片 | 操作与预期 |
| --- | --- |
| 原生实现 | 在三端分别确认 platform 与 Kotlin / Swift / ArkTS 来源。 |
| 同步与异步 | 修改文本，两个回显均返回原文；错误测试收到 `ERR_SHOWCASE` 后显示成功。 |
| 事件 | 订阅后发送，计数增加；取消后发送，计数不再变化；离开页面移除监听。 |
| 共享对象 | 创建、同步 / 异步增加、通过属性归零、发送对象事件，验证同模块和跨模块的对象身份；释放后重新创建。SharedRef 保留身份和文本，在测试结束时释放。 |
| 原生组件 | 修改标题、通过 prop 增加、点击原生按钮、通过 ref 增加；仅后两项触发事件。卸载后重新挂载并检查布局。 |
| 原生页面 | 打开后增加计数，完成时接收新值；取消或系统返回时保留上次传入值。重复打开检查初值，旋转及调整字体后检查布局。 |
| 生命周期 | 读取快照，切换前后台、增加和取消事件订阅，再读取并比较对应计数。 |

页面关闭会移除事件订阅并释放共享对象。原生页面返回前保持打开按钮禁用；各平台也会拒绝重复打开，并在模块销毁时关闭页面。iOS 使用全屏导航容器，通过“取消”或“完成”返回；Android / HarmonyOS 同时支持系统返回。

原生 UI 的颜色、间距与圆角和 `apps/demo/src/theme.ts` 保持一致。各平台独立使用系统原生控件，因此字体与导航行为仍遵循平台习惯。
