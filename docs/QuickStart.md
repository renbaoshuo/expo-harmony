# 快速开始

本文以 [`apps/demo`](../apps/demo) 为例，介绍如何为现有 Expo 项目接入 HarmonyOS，以及 Metro 如何按平台选择 React Native 实现。

## 环境要求

- Node.js 20.19.4+（20.x）、22.13+（22.x）、24.3+（24.x）或 25+。
- Expo SDK 57 项目（`expo@57.0.31`）。本示例的 CLI 和 prebuild 工具与该版本配套。
- DevEco Studio，带完整的 HarmonyOS SDK（含 HMS 与 OpenHarmony 组件）、OHPM、Hvigor 和 HDC。构建 HAP 时需要，`expo-harmony doctor` 会逐项检查。
- 一台 HarmonyOS 设备，或者在 DevEco Studio Device Manager 里创建的模拟器。

## 安装依赖

以下命令在应用根目录执行。示例共用 React 19.2.3 和 React Native 0.86.3，HarmonyOS 端由 RNOH 0.86.1 提供实现。完整版本见 [Demo 依赖清单](../apps/demo/package.json)。

```sh
npm install --save-exact expo@57.0.31 expo-modules-core@57.0.24 expo-asset@57.0.20 expo-constants@57.0.22
npm install @expo-harmony/cli @expo-harmony/prebuild-config @expo-harmony/metro-config @expo-harmony/expo @expo-harmony/expo-modules-core @expo-harmony/expo-asset @expo-harmony/expo-constants
npm install --save-exact @react-native-oh/react-native-harmony@0.86.1 @react-native-oh/react-native-harmony-cli@0.86.1 hermes-compiler@250829098.0.17
```

- RNOH JS 包、RNOH CLI 和原生 HAR 版本配套。Expo 初始化会加载 Asset 和 Constants，因此两者的 Harmony 实现也随应用自动链接。
- `hermes-compiler` 作为应用的直接依赖，与 RNOH HAR 内嵌的 Hermes 配套，供运行时契约和 Release 字节码编译使用。
- 业务代码使用的 Expo 模块需要对应的 Harmony 适配包。已移植模块见 [仓库 README](../README.md#supported-libraries)，安装后可用 `npx expo-harmony modules list` 查看自动链接结果。

## 配置 app.json

demo 的配置在 [`apps/demo/app.json`](../apps/demo/app.json)，要改四处。

第一，`platforms` 加 `harmony`：

```json
"platforms": ["ios", "android", "harmony"]
```

第二，`experiments` 开启 `outOfTreePlatforms`：

```json
"experiments": {
  "outOfTreePlatforms": true
}
```

第三，`plugins` 注册 `@expo-harmony/prebuild-config`，放在最后。它注册 Harmony 的 Base Mods，其他 Harmony 插件要排在它前面：

```json
"plugins": [
  "expo-router",
  "@expo-harmony/expo-constants",
  "expo-font",
  "@expo-harmony/expo-font",
  "@expo-harmony/expo-splash-screen",
  "@expo-harmony/prebuild-config"
]
```

官方插件和 `@expo-harmony/expo-*` 插件成对出现：前者管 iOS 和 Android，后者管 HarmonyOS。demo 里 `expo-splash-screen` 和 `@expo-harmony/expo-splash-screen` 的参数只差图标格式，鸿蒙环境是可以用 SVG 的。

第四，加 `harmony` 配置块：

```json
"harmony": {
  "bundleName": "com.example.app",
  "label": "Example",
  "icon": "./assets/icon.svg",
  "versionCode": 1,
  "permissions": [
    {
      "name": "ohos.permission.CAMERA",
      "reason": "$string:camera_permission_reason",
      "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
    }
  ]
}
```

- `bundleName` 是应用包名，必填。
- `targetSdkVersion` 和 `compatibleSdkVersion` 默认分别为 24（HarmonyOS 6.1.1）和 20（HarmonyOS 6.0.0）。通过 [expo-build-properties](../packages/expo-build-properties/README.md) 配置 SDK、ABI、SO 打包和 release 选项。应用的最低兼容版本须满足所有原生依赖的要求，Demo 的通知和网格渐变模块要求至少 API 23。
- `expo.harmony.permissions` 会写入生成的 `module.json5`。HarmonyOS 还会在构建时合并所用 HAR 的权限声明。上例的 `CAMERA` 用于应用内嵌相机，系统拍照选择器不需要它。[华为 HAR 打包说明](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/har-package/) · [CameraPicker API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-camerapicker/)

选取照片、视频、联系人或文件时，使用系统选择器可以将访问范围限定为用户选中的内容。确需全库访问等受限能力时，由应用开发者按业务场景向华为提交申请，并按各模块的说明在 `expo.harmony.permissions` 声明权限。验证受限接口的正向流程时，签名 Profile 需要包含对应 ACL，并允许在目标调试设备上安装。已提交申请的应用可按华为流程使用试用调试 Profile。发布时使用包含获批 ACL 的发布 Profile。对于 `user_grant` 权限，应用安装后还要在运行时取得用户授权。[华为受限开放权限](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions) · [调试与发布 Profile 配置](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-appgallery-25/)

部分权限在本地调试和上架时适用不同规则。例如 `FILE_ACCESS_PERSIST` 从 API 12 起可直接声明用于本地调试，上架仍需申请。[华为文件持久化访问权限说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions#ohospermissionfile_access_persist)

## 配置 metro.config.js

demo 的 [`apps/demo/metro.config.js`](../apps/demo/metro.config.js)：

```js
'use strict';

const { getDefaultConfig } = require('expo/metro-config');
const { withHarmonyConfig } = require('@expo-harmony/metro-config');

const projectRoot = __dirname;
const isHarmony = process.env.EXPO_METRO_TARGET === 'harmony';
const config = getDefaultConfig(projectRoot);

module.exports = withHarmonyConfig(config, {
  enabled: isHarmony,
  projectRoot,
});
```

- 所有 `expo-harmony` 命令都会在 CLI 入口自动设置 `EXPO_HARMONY=1` 和 `EXPO_METRO_TARGET=harmony` 并传递给子进程；无需在命令前添加 `cross-env`。应用配置和插件也可以使用这些变量判断 Harmony 环境。
- `enabled` 为 false 时 `withHarmonyConfig` 原样返回配置，也不加载 RNOH 的依赖。
- demo 里还有一段给 expo-router 补 `nodeModulesPaths` 的代码，那是 Yarn workspace 布局下的处理，单包项目用不到。

`package.json` 里照抄 demo 加这几个脚本：

```json
{
  "scripts": {
    "start:harmony": "expo-harmony start",
    "run:harmony": "expo-harmony run",
    "prebuild:harmony": "expo-harmony prebuild",
    "check:harmony": "expo-harmony prebuild . --check",
    "doctor:harmony": "expo-harmony doctor"
  }
}
```

要手动起一个只服务 Harmony 的 Metro：

```sh
npm run start:harmony
# 需要指定参数时 ↓
npm run start:harmony -- --port 8081 --reset-cache
```

支持 `--port <number>`（默认 8081）和 `--clear` / `--reset-cache` / `-c` 清除缓存。这个命令只启动开发服务，不构建或启动原生应用，需要在另一个终端构建并运行时使用 `expo-harmony run --no-bundler`，两边的端口要一致。不要给 Expo CLI 传 `--harmony` 参数，会起不来。

`--host <IP 或主机名>` 用于指定二维码、manifest 和 bundle URL 中提供给设备的地址。未指定时会自动检测并降低常见虚拟网卡的优先级。Metro 仍监听所有网络接口。若服务已运行，需要停止后重新指定地址。

## 生成 HarmonyOS 原生工程

```sh
npm run prebuild:harmony
```

这个命令用 Expo CNG 生成 `harmony/` 目录，里面有 AppScope、entry 模块、Hvigor、CMake 和 RNOH 宿主代码，并完成 Expo 原生模块的自动链接。执行前先跑一遍 doctor（这个阶段不要求构建工具就绪），有阻塞错误会中止。

把 `harmony/` 加进 `.gitignore`，demo 的写法：

```
/harmony/
```

这个目录是生成物，demo 没有提交它。要重新生成，用 `expo-harmony prebuild --clean`。要在 CI 里校验工程和配置是否同步，用 `expo-harmony prebuild --check`：无差异时退出码 0，有差异时列出变更并以 2 退出。

## 构建并运行

接上设备，或者起好模拟器，然后：

```sh
npm run run:harmony
```

`run` 依次做环境诊断、构建 HAP、安装、启动应用。Debug 模式下它还会起一个 Metro（自动带上 `EXPO_METRO_TARGET=harmony`），日志接管终端，Ctrl+C 退出。端口上已有 Metro 在运行时直接复用。

常用选项：

- `--variant release`：走生产导出，把 Hermes 字节码嵌进 HAP，不启动 Metro。
- `--device <id-or-name>`：选已连接的设备，或按名称启动本地模拟器。存在多个候选目标时必须指定。
- `--port <number>`：Metro 端口和设备反向映射端口，默认 8081。
- `--host <IP 或主机名>`：指定本次启动的 Metro 对外公布的地址；已有服务的地址应在启动服务时指定。
- `--no-bundler`：连接已经在跑的 Metro，不起新的。

不指定 `--device` 时，优先用已连接设备；没有设备就等启动中的模拟器，否则自动拉起唯一的本地模拟器。自动拉起需要 DevEco Studio 6.1.0 或更新版本。

各步骤（OHPM 安装、Hvigor 构建、等待模拟器等）的超时默认值可以通过 `EXPO_HARMONY_<操作名大写下划线>_TIMEOUT_MS` 环境变量调整，例如 `EXPO_HARMONY_OHPM_INSTALL_TIMEOUT_MS`（默认 30 分钟）。完整列表见 [CLI README 的超时一节](../packages/cli/README.md#超时)。

iOS 和 Android 的命令没有任何变化，`expo run:ios`、`expo run:android` 照旧。

## 签名

尚未创建签名材料时，可以先省略签名配置来生成未签名工程，再使用 DevEco Studio 创建证书、私钥库和 Profile。应用显式选定签名配置后，若文件或材料缺失、无效，prebuild 会报错并中止，包括首次生成和 `--clean`。将签名配置写成 JSON 文件，字段与 DevEco Studio 写入 `build-profile.json5` 的 `signingConfigs` 一致，包括 `certpath`、`storeFile`、`profile`、`storePassword`、`keyAlias`、`keyPassword` 和 `signAlg`。

签名文件不能放在 `harmony/` 里，`--clean` 会把目录删掉。demo 的做法是放在外面，用 [`apps/demo/app.config.js`](../apps/demo/app.config.js) 按环境变量注入：

```js
'use strict';

module.exports = ({ config }) => {
  const signingConfigFile = process.env.EXPO_HARMONY_SIGNING_CONFIG_FILE;
  return {
    ...config,
    harmony: {
      ...config.harmony,
      ...(signingConfigFile ? { signingConfigFile } : {}),
    },
  };
};
```

函数收到的 `config` 就是 `app.json` 解析出来的配置，在上面追加 `harmony.signingConfigFile`。这样签名路径和密钥口令都不进 git。

## Metro 如何按平台选择实现

| 依赖 | iOS / Android | HarmonyOS |
| --- | --- | --- |
| React Native | `react-native@0.86.3` | `@react-native-oh/react-native-harmony@0.86.1` |
| React | `react@19.2.3` | `react@19.2.3` |
| 原生构建 | CocoaPods / Gradle | OHPM / Hvigor，依赖 `@rnoh/react-native-openharmony@0.86.1` |

HarmonyOS 打包时，`withHarmonyConfig` 应用 Harmony 重定向并接入 RNOH resolver。RNOH 将 `react-native` 映射到平台实现，再委托原有 Expo resolver 解析具体文件，因此 Expo Router 和 TypeScript paths 继续生效。其他平台使用 Expo 的默认解析规则。各平台均从 `react` 导入同一版本。

### 原生依赖

Demo 使用 React Native Screens `4.26.2` 和 Safe Area Context `5.6.2` 的 JS 接口。Harmony 侧原生包由 Expo Harmony Router 带入，分别是 Screens `4.10.0-beta.4` 和 Safe Area Context `5.6.4`。Worklets JS 使用 `0.11.4`，Core 带入 Harmony Worklets `1.1.0-beta.1`。

适配包可通过 `harmony.alias` 和内部重定向提供同名入口。纯 JS 库可沿用原有依赖。其他解析选项见 [Metro 配置说明](../packages/metro-config/README.md)。

### 业务代码里的平台判断

`Platform.OS === 'harmony'`。Metro 注册了 harmony 平台，`.harmony.tsx`、`.harmony.ts` 这类平台后缀文件也按 RN 的后缀规则解析。demo 的 `app/_layout.tsx` 里有一个状态栏颜色的判断可以参照。

### 原生层

iOS 的依赖在 Pods 里，Android 的在 Gradle 里，HarmonyOS 的在 `harmony/oh-package.json5` 里：`@rnoh/react-native-openharmony` 和各模块的 HAR 由 OHPM 安装、Hvigor 构建。三层互不引用，删掉 `harmony/` 重新 prebuild 只影响 HarmonyOS。

## 排错

- 跑不起来就先 `npm run doctor:harmony`。它检查配置、插件注册、Metro、依赖版本、SDK、构建工具和签名，有 error 时以非零状态退出，照着输出改。
- `modules list` 标出某个模块不支持 Harmony：装对应的 `@expo-harmony/expo-*` 包，或按上文屏蔽。
- 端口被占用：`--port` 换端口。
- 模拟器拉不起来：需要 DevEco Studio 6.1.0+，并且先在 Device Manager 里创建过实例；首次使用的协议和登录要在 IDE 里处理。启动日志在 `.expo/harmony/emulator.log`。

## 命令速查

| 命令 | 作用 |
| --- | --- |
| `expo-harmony prebuild` | 生成或更新 `harmony/` 原生工程 |
| `expo-harmony prebuild --check` | 校验工程与配置是否同步，不改文件 |
| `expo-harmony prebuild --clean` | 删除并重新生成受管理的 `harmony/` |
| `expo-harmony start` | 起一个只服务 Harmony 的 Metro |
| `expo-harmony run` | 构建 HAP，安装并启动，Debug 下顺带起 Metro |
| `expo-harmony build` | 只构建 HAP，不装不启 |
| `expo-harmony export:embed` | 导出 Hermes 字节码、资源和 Source Map 写入原生工程 |
| `expo-harmony doctor` | 环境和配置诊断 |
| `expo-harmony modules list` | 列出模块及 Harmony 支持情况 |

完整参数说明见 [`@expo-harmony/cli` 的 README](../packages/cli/README.md)。
