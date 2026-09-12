# 在已有 React Native 工程中接入 Expo Harmony

本文以 [`apps/bare`](../apps/bare) 为例，介绍如何在手工维护的 RNOH 工程中接入 Expo Modules，并使用 `expo-battery` 读取电池信息。接入后的应用保留常规的 React Native 入口，原生代码位于 `harmony/` 目录，不使用 prebuild、CNG 或 Expo Router。

Expo 支持在已有的 React Native 应用中按需引入工具和模块，整体接入步骤见 [官方概览](https://docs.expo.dev/bare/overview/)。[Prebuild 是可选的](https://docs.expo.dev/workflow/continuous-native-generation/#optionality)，因此即使原生工程完全手工维护，也可以继续使用 Expo SDK 和 CLI。此时仍需安装 `expo`，以使用它提供的 Metro、Babel 配置和打包工具。

如果项目中还有 iOS 或 Android 工程，可以按 Expo 的 [安装 Expo Modules 指引](https://docs.expo.dev/bare/installing-expo-modules/) 接入这两个平台。官方指引中的 `install-expo-modules`、Podfile 和 Gradle 配置只覆盖 iOS 和 Android，HarmonyOS 的宿主与构建配置请按下文的说明处理。

## 环境和版本

- Node.js 20 或更高版本。
- DevEco Studio，并安装完整的 HarmonyOS SDK（包含 HMS、OpenHarmony 组件，以及 OHPM、Hvigor 和 HDC 等工具）。
- 一个已有的 RNOH 工程，原生目录位于应用根目录下的 `harmony/`，入口模块目录为 `harmony/entry`。
- 一台 HarmonyOS 设备，或一个在 DevEco Studio Device Manager 中创建的模拟器。

接入时使用的主要版本如下，完整依赖清单可参考 [`apps/bare/package.json`](../apps/bare/package.json)。

**本文以 `expo-battery` 为例，使用其他 Expo 模块时，请按实际情况调整依赖及其版本。**

| 依赖                                                                 | 版本                |
| -------------------------------------------------------------------- | ------------------- |
| `expo`                                                               | `55.0.26`           |
| `expo-modules-core`                                                  | `55.0.25`           |
| `expo-battery`                                                       | `55.0.13`           |
| `react` / `react-native`                                             | `19.2.3` / `0.84.1` |
| `@react-native-oh/react-native-harmony`                              | `0.84.1`            |
| `@react-native-oh/react-native-harmony-cli`                          | `0.84.1`            |
| 原生包 `@rnoh/react-native-openharmony`                              | `0.84.1`            |
| `react-native-worklets` / `@react-native-ohos/react-native-worklets` | `0.7.4` / `1.0.0`   |

只接入 HarmonyOS 平台时，React 和 React Native 的版本跟随 RNOH 即可。项目中已有的 iOS、Android 工程可以保留各自需要的版本；如果需要同时使用两套 React 和 React Native，请参照[两套 React Native 如何共存](./QuickStart.md#两套-react-native-如何共存)配置 Metro 别名。

## 安装依赖

以下命令均在应用根目录执行。首先安装 Expo、各模块的 JS 包和 Harmony 实现：

```sh
npm install expo@55.0.26 expo-modules-core@55.0.25 expo-battery@55.0.13
npm install @expo-harmony/cli @expo-harmony/metro-config @expo-harmony/expo-modules-autolinking @expo-harmony/expo-modules-core @expo-harmony/expo-battery
```

`expo-battery` 提供业务代码使用的 JS API，`@expo-harmony/expo-battery` 提供 HarmonyOS 原生实现，两者都需要安装。`@expo-harmony/expo-modules-core` 是 Expo Modules 的 HarmonyOS 运行时，它还依赖 Worklets。

再安装 RNOH 和 Worklets 相关依赖：

```sh
npm install @react-native-oh/react-native-harmony@0.84.1 @react-native-oh/react-native-harmony-cli@0.84.1
npm install react-native-worklets@0.7.4 @react-native-ohos/react-native-worklets@1.0.0
```

以下打包依赖也需要显式安装：

```sh
npm install @expo/metro-runtime@55.0.12 @expo/metro-config@55.0.26 @expo/log-box@55.0.12
npm install metro@0.83.3 metro-config@0.83.7 hermes-compiler@250829098.0.9
npm install --save-dev @babel/core@7.29.7 @react-native-community/cli@15.1.3
```

安装后请核对各包的 `peerDependencies`，例如当前的 Battery 适配包要求 `expo-battery@55.0.13`。Expo 官方文档中的版本会随 SDK 更新而变化，本文的版本组合以示例工程为准。

## 配置 JS 入口和打包工具

### 保留 AppRegistry 入口

在 `package.json` 中设置入口：

```json
{
  "main": "index.js"
}
```

`app.json` 可以沿用普通 React Native 工程的格式：

```json
{
  "name": "BareBattery",
  "displayName": "Expo Harmony Demo (Bare)"
}
```

`index.js` 注册应用：

```js
import { AppRegistry } from 'react-native';
import App from './App';
import { name } from './app.json';

AppRegistry.registerComponent(name, () => App);
```

`name` 需要与后文原生页面中的 `ExpoRNApp.appKey` 保持一致（示例中均为 `BareBattery`）。应用在系统中显示的名称由 HarmonyOS 原生资源决定，修改这里的 `displayName` 不会对其产生影响。

bare 工程不需要在 `app.json` 中添加 `expo.harmony` 或注册 `@expo-harmony/prebuild-config` 插件。

### 配置 Metro 和 Babel

在 `metro.config.js` 中接入 Harmony 配置，参考 [`apps/bare/metro.config.js`](../apps/bare/metro.config.js)：

```js
const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

module.exports = withHarmonyConfig(getDefaultConfig(__dirname), {
  projectRoot: __dirname,
});
```

Expo 的 [Metro 文档](https://docs.expo.dev/guides/customizing-metro/) 要求 Metro 配置继承自 `expo/metro-config`。在这份配置的基础上调用 `withHarmonyConfig`，即可接入 RNOH 的模块解析和 Expo Modules 的初始化流程；只给 `react-native` 设置别名，无法完成这些初始化。

只构建 HarmonyOS 单平台时，直接使用上面的配置即可；多平台项目可以在 `withHarmonyConfig` 的选项中添加 `enabled: process.env.EXPO_METRO_TARGET === 'harmony'`，`expo-harmony` 命令会自动设置该环境变量。更多选项见 [`@expo-harmony/metro-config`](../packages/metro-config/README.md)。

`babel.config.js` 使用 Expo 预设：

```js
module.exports = { presets: ['babel-preset-expo'] };
```

在 `react-native.config.js` 中加载 RNOH CLI 配置：

```js
module.exports = require('@react-native-oh/react-native-harmony-cli/react-native.config.js');
```

如果已有工程在这个文件中配置了其他平台或依赖，请将 RNOH 的配置合并进去，并保留原有设置。

## 接入 HarmonyOS 原生工程

这一节介绍需要在 `harmony/` 工程中处理的配置，涉及的文件都可以在 [`apps/bare/harmony`](../apps/bare/harmony) 中找到。请将对应的配置合并到已有工程；如果是新建工程，也可以把该目录中的源码和配置作为起点，再修改包名、应用名称、图标等信息。

### 配置来源和目录约定

构建配置写在原生文件中：

| 配置                                     | 文件                                                                              |
| ---------------------------------------- | --------------------------------------------------------------------------------- |
| 应用包名 `bundleName`、版本              | [`AppScope/app.json5`](../apps/bare/harmony/AppScope/app.json5)                   |
| 产品、SDK 版本、模块路径、构建目标、签名 | [`build-profile.json5`](../apps/bare/harmony/build-profile.json5)                 |
| 模块名、入口 Ability、权限               | [`entry/src/main/module.json5`](../apps/bare/harmony/entry/src/main/module.json5) |
| CMake 入口、目标架构                     | [`entry/build-profile.json5`](../apps/bare/harmony/entry/build-profile.json5)     |

自动链接按 `entry/src/main` 这一固定路径查找文件，因此入口模块目录必须是 `harmony/entry`。模块名和 Ability 名可以修改，但要与 `build-profile.json5` 中的模块登记以及 `module.json5` 中的 `mainElement`、`abilities` 保持对应。产品和构建目标会优先选择名为 `default` 的项；没有 `default` 时，可用的候选必须只有一个。

SDK 版本在 `build-profile.json5` 中设置，示例使用最低兼容版本 API 13、目标版本 API 24。添加其他原生模块时，还需要满足这些模块的最低 API 要求。

### 接入 C++ 和 ArkTS 包注册

合并以下文件中的注册与链接配置：

| 文件                                                                                                    | 接入内容                                                                                                                                                                                |
| ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`entry/src/main/cpp/CMakeLists.txt`](../apps/bare/harmony/entry/src/main/cpp/CMakeLists.txt)           | 引入 RNOH、生成的 `autolinking.cmake` 和 codegen 源码，并对 `rnoh_app` 调用 `autolink_libraries`。保留文件开头的 `native-inputs.cmake` 加载，该文件由后文的准备步骤生成，无需手工创建。 |
| [`entry/src/main/cpp/PackageProvider.cpp`](../apps/bare/harmony/entry/src/main/cpp/PackageProvider.cpp) | 调用生成的 `createRNOHPackages`，并注册 `RNOHGeneratedPackage`。                                                                                                                        |
| [`entry/src/main/ets/PackageProvider.ets`](../apps/bare/harmony/entry/src/main/ets/PackageProvider.ets) | 用生成的 ArkTS `createRNOHPackages` 返回原生包列表。                                                                                                                                    |

`RNOHPackagesFactory.h`、`RNOHPackagesFactory.ets` 和 `autolinking.cmake` 都由自动链接生成，无需逐个添加 Battery 等模块。已有的手工注册包可以保留，但同一个包不要同时通过两种方式注册。

### 接入 AbilityStage、Ability、页面和 Worker

先合并 [`EntryAbilityStage.ets`](../apps/bare/harmony/entry/src/main/ets/abilitystage/EntryAbilityStage.ets)，并在 `module.json5` 的 `module.srcEntry` 中登记 `./ets/abilitystage/EntryAbilityStage.ets`。`EntryAbilityStage` 继承 `ExpoAbilityStage`，会在 UIAbility 和后台 ExtensionAbility 启动之前初始化各模块贡献的应用级生命周期订阅器；`ExpoRNAbility` 中的初始化只是兜底，无法覆盖由后台任务冷启动的进程，因此这一步不能省略。如果工程已有自定义 AbilityStage，请在它的 `onCreate` 中先调用 `expoReactHost.initialize(this.context)`，再调用 `expoHarmonyHostProvider.lifecycle.initializeApplication(this.context.getApplicationContext())`，并保留原有的父类逻辑。

[`EntryAbility.ets`](../apps/bare/harmony/entry/src/main/ets/entryability/EntryAbility.ets) 继承 `ExpoRNAbility`，提供页面、宿主扩展和 Worker 入口：

```ts
import type { ExpoHarmonyHostProvider } from '@expo-harmony/expo-modules-core/Autolinking';
import { ExpoRNAbility } from '@expo-harmony/expo-modules-core/Autolinking';
import { expoHarmonyHostProvider } from '../generated/ExpoHarmonyHostProvider';

export default class EntryAbility extends ExpoRNAbility {
  override getPagePath(): string {
    return 'pages/Index';
  }

  protected override getExpoHarmonyHostProvider(): ExpoHarmonyHostProvider {
    return expoHarmonyHostProvider;
  }

  protected override getExpoHarmonyWorkerScriptUrl(): string {
    return 'entry/ets/workers/RNOHWorker.ets';
  }
}
```

请将 [`Index.ets`](../apps/bare/harmony/entry/src/main/ets/pages/Index.ets) 的页面配置合并到原生首页。该页面从 `RNOHCoreContext` 获取运行环境，用 `ExpoRNApp` 创建 RN 实例，实例配置复用 `PackageProvider.ets` 中的 `expoReactHost`，`appKey` 为 `BareBattery`；页面中还包含生成的 `ExpoHarmonyRootView`，供模块挂载宿主 UI。

`PackageProvider.ets` 中的 `ExpoReactHost` 集中声明内嵌 bundle 路径、Worker 脚本和 RN 实例的完整配置。Debug 运行时从 Metro 开发服务加载 JS；Release 和后台冷启动读取的是同一份内嵌 bundle（`hermes_bundle.hbc`）。`ExpoAbilityStage` 会在初始化生命周期订阅器之前先初始化 `ExpoReactHost`，因此只启动后台 ExtensionAbility 的进程也能加载 bundle。

Worker 使用 [`RNOHWorker.ets`](../apps/bare/harmony/entry/src/main/ets/workers/RNOHWorker.ets)，通过 `setupRNOHWorker` 接入同一份包列表。请确认 `module.json5` 的 `abilities[].srcEntry`、页面路由和 Ability 中的 Worker 路径都指向这些文件。

权限、URL Scheme、图标以及模块所需的原生资源都由项目自行维护，config plugin 的选项不会在 bare 构建时写入原生文件。例如，访问 Metro 开发服务需要 `ohos.permission.INTERNET` 权限。

### 配置 OHPM 和 Hvigor

在 [`harmony/oh-package.json5`](../apps/bare/harmony/oh-package.json5) 中声明与 JS 侧配套的 `@rnoh/react-native-openharmony@0.84.1`。Expo Core、Battery 和 Worklets 的 HAR 依赖会在执行自动链接时写入，无需手工添加。

合并以下构建文件：

| 文件                                                                                    | 配置内容                                                                                                                                      |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| [`harmony/hvigor/hvigor-config.json5`](../apps/bare/harmony/hvigor/hvigor-config.json5) | 声明 `@rnoh/hvigor-plugin`，示例中指向 `../../node_modules/@react-native-oh/react-native-harmony-cli/harmony/rnoh-hvigor-plugin-0.84.1.tgz`。 |
| [`harmony/hvigorfile.ts`](../apps/bare/harmony/hvigorfile.ts)                           | 保留 `appTasks` 和 RNOH 项目插件，关闭后者的 bundler，设置 `HERMES_V1_ENABLED=true`，并接入 Expo Harmony 的准备与打包任务。                   |
| [`harmony/entry/hvigorfile.ts`](../apps/bare/harmony/entry/hvigorfile.ts)               | 保留 `hapTasks` 和 RNOH codegen，将 RNOH 插件的 `autolinking` 设为 `null`，由 Expo Harmony 统一处理自动链接。                                 |

这些路径以“应用目录下存在 `node_modules/`”为前提。如果使用 workspace 或其他依赖布局，请检查插件压缩包的路径以及两个 Hvigor 文件中的 `nodeModulesPath`。

根 `hvigorfile.ts` 从 CLI 的公开入口导入两个函数：

```ts
import { prepareHarmonyNativeBuild, bundleHarmonyNativeBuild } from '@expo-harmony/cli/native-build';
```

在 `hvigor.nodesEvaluated` 中调用 `prepareHarmonyNativeBuild(projectRoot, mode)`，其中 `projectRoot` 是包含 `package.json` 的应用根目录，`mode` 为 `debug` 或 `release`。该函数会执行自动链接、安装 OHPM 依赖，并生成 CMake 构建所需的 `native-inputs.cmake` 等文件。

Release 构建还需要注册一个调用 `bundleHarmonyNativeBuild(projectRoot)` 的任务，并安排在目标的 `ProcessResource` 之后、`CompileResource` 之前。完整的任务注册方式见上表中的根 `hvigorfile.ts`。这样从 DevEco Studio 发起 Release 构建时，JS 和资源也会被打包进 HAP。

## 生成自动链接文件

依赖和原生文件配置好后，在应用根目录执行：

```sh
npx expo-harmony-autolinking link --project-root . --harmony-project-path ./harmony
```

该命令会解析已安装的 Expo 和 RNOH 模块，更新 OHPM 依赖，并生成包注册、CMake 和 `ExpoHarmonyHostProvider.ets` 等文件。它不会生成整个 `harmony/` 工程，也不执行 config plugins。

随后安装原生依赖：

```sh
cd harmony
ohpm install --all
cd ..
```

首次从 DevEco Studio 或 Hvigor 发起构建前，需要先完成这一步，以便构建插件能够加载原生依赖。之后，无论是使用 `expo-harmony build`、`expo-harmony run`，还是通过已接入上述任务的 Hvigor 构建，都会按构建模式执行自动链接和依赖准备。新增或删除原生模块后，需要重新构建应用。

## 使用 expo-battery

业务代码仍然从 `expo-battery` 导入，无需改用 Harmony 侧的包名。用于验证接入效果的 `App.tsx` 可以写成：

```tsx
import { useBatteryLevel, useBatteryState, BatteryState } from 'expo-battery';
import { Text, View } from 'react-native';

export default function App() {
  const level = useBatteryLevel();
  const state = useBatteryState();

  return (
    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', gap: 12 }}>
      <Text>电量：{level < 0 ? '未知' : `${Math.round(level * 100)}%`}</Text>
      <Text>电池状态：{BatteryState[state]}</Text>
    </View>
  );
}
```

这两个 Hook 会读取电池状态并订阅变化。电量取值范围为 `0` 到 `1`，无法获取时为 `-1`，因此显示百分比前要先处理未知值。API 用法见 [Expo SDK 55 Battery 文档](https://docs.expo.dev/versions/v55.0.0/sdk/battery/)；HarmonyOS 的返回值和事件行为见 [Battery 适配包说明](../packages/expo-battery/README.md)。

示例应用 [`apps/bare/App.tsx`](../apps/bare/App.tsx) 还调用了 `getPowerStateAsync()`、`isAvailableAsync()` 和 `isBatteryOptimizationEnabledAsync()`，订阅电量、充电状态与低电量模式变化，并在组件卸载时移除监听。运行示例后可以查看电量、电源状态和事件计数，也可以点击“重新读取电池状态”检查当前值。在没有真实电池的模拟器上读到未知电量，并不代表模块接入失败。

## 构建和运行

在 `package.json` 中添加以下脚本：

```json
{
  "scripts": {
    "start:harmony": "expo-harmony start",
    "run:harmony": "expo-harmony run",
    "build:harmony": "expo-harmony build",
    "build:release": "expo-harmony build --variant release",
    "doctor:harmony": "expo-harmony doctor"
  }
}
```

这些命令并不是接入后的必需步骤。自动链接、依赖准备和 Release 打包都已经接入 `harmony/` 工程的 Hvigor 构建，可以继续沿用原有的构建方式，例如在 DevEco Studio 中构建，或使用工程已有的 `hvigorw` 命令和构建脚本。这些构建同样会按构建模式执行自动链接和依赖准备，Release 也会把 JS 和资源打包进 HAP；首次构建前，仍需先完成 [生成自动链接文件](#生成自动链接文件) 一节的初始化步骤。

`expo-harmony` 提供的主要是构建之外的便利：`run` 会选择设备或启动模拟器、安装并启动应用，并管理 Metro 和设备端口映射；`doctor` 用于检查配置和环境。沿用原有构建方式时，Debug 运行所需的 Metro 和端口反向映射需要自行处理，参见下文从 DevEco Studio 构建的说明。

先检查配置和环境，再连接设备或启动模拟器运行：

```sh
npm run doctor:harmony
npm run run:harmony
```

`run` 默认构建 Debug HAP，安装并启动应用，同时启动或复用 Metro。存在多个设备时，可以通过 `npm run run:harmony -- --device <设备ID或模拟器名称>` 选择目标设备。

如需单独启动 Metro，可以在两个终端中使用同一端口：

```sh
npm run start:harmony -- --port 8082
```

```sh
npm run run:harmony -- --port 8082 --no-bundler
```

只构建 HAP，或构建并运行 Release：

```sh
npm run build:harmony
npm run build:release
npm run run:harmony -- --variant release
```

Release 构建会导出 Hermes 字节码和资源，写入 `harmony/entry/src/main/resources/rawfile/`。页面加载的文件名为 `hermes_bundle.hbc`，运行时不依赖 Metro。也可以使用 `npx expo-harmony export:embed` 单独执行导出。

签名在 `harmony/build-profile.json5` 中维护：先填写 `app.signingConfigs`，再由所选产品的 `signingConfig` 引用。不配置签名时可以生成未签名的 HAP；在安装到要求签名的设备之前，需要配置对应的证书和 profile。签名材料和口令不要提交到仓库。

如果要从 DevEco Studio 构建，请打开 `harmony/` 目录，完成 OHPM 安装并选择构建目标。Debug 运行还需要启动 Metro；使用 USB 或模拟器连接时，需要针对当前连接的 HDC 目标设置端口反向映射，例如 `hdc -t <设备ID> rport tcp:8081 tcp:8081`。`expo-harmony run` 会自动处理这一步，`expo-harmony start` 则只启动开发服务。

完整命令参数和工具路径配置见 [CLI 文档](../packages/cli/README.md)。

## 运行仓库里的示例

如果直接使用本仓库，请在仓库根目录执行以下命令，无需重复安装前文列出的 npm 依赖：

```sh
yarn install
yarn build
yarn workspace @expo-harmony/bare doctor:harmony
yarn workspace @expo-harmony/bare run:harmony
```

`yarn build` 会构建工作区内的原生 HAR 和工具包，首次运行前需要先配置好 HarmonyOS 构建环境。构建 Release 时使用：

```sh
yarn workspace @expo-harmony/bare build:release
yarn workspace @expo-harmony/bare run:harmony --variant release
```

## 原生文件的维护

请将手工维护的 `harmony/` 源码和配置提交到代码仓库，构建缓存、`oh_modules/`、HAP 等产物按项目规则忽略，不要照搬 CNG 类型的项目中忽略整个 `harmony/` 目录的规则。

当工程已有 `harmony/` 目录，且不存在 `harmony/.expo-harmony-template` 和 `.expo/harmony/cng-manifest.json` 时，CLI 会将其识别为 bare 工程。构建在 `.expo/harmony/` 下生成的清单和缓存文件并不代表启用了 CNG。

bare 工程不需要执行 `expo-harmony prebuild`，也不使用 `build --sync` 或 `run --sync`。应用包名、权限、资源或原生代码发生变化时，修改对应文件后重新构建即可。遇到配置错误时，先运行 `doctor:harmony`；如果 CLI 要求提供 CNG 清单，请检查工程是否仍带有 CNG 模板标记，这类工程不会自动切换为 bare 模式。
