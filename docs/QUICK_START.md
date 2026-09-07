# 快速开始

这篇文档以 [`apps/demo`](../apps/demo) 为参照，主要讲解两方面的内容：怎么把一个现有的 Expo 项目跑上 HarmonyOS，以及怎么让 iOS、Android 和 HarmonyOS 各用各的 React Native 版本。demo 是本仓库的示例应用，下面每段配置都能在它的目录里找到对应文件。

## 环境要求

- Node.js 20 或更高版本。
- Expo SDK 55 项目（`expo@55.0.26`）。当前工具链按 SDK 55 适配，`@expo-harmony/cli` 和 `@expo-harmony/prebuild-config` 的 peerDependencies 都锁在这个版本上。
- DevEco Studio，带完整的 HarmonyOS SDK（含 HMS 与 OpenHarmony 组件）、OHPM、Hvigor 和 HDC。构建 HAP 时需要，`expo-harmony doctor` 会逐项检查。
- 一台 HarmonyOS 设备，或者在 DevEco Studio Device Manager 里创建的模拟器。

## 安装依赖

```sh
npm install @expo-harmony/cli @expo-harmony/metro-config @react-native-oh/react-native-harmony@0.84.1 @react-native-oh/react-native-harmony-cli@0.84.1 react-harmony@npm:react@19.2.3
```

几点说明：

- `@react-native-oh/react-native-harmony` 是 RNOH 的 JS 侧运行时，`@react-native-oh/react-native-harmony-cli` 是它的配套 CLI，两者版本必须配套，当前是 0.84.1。
- `react-harmony` 是一个 npm alias，实际安装 `react@19.2.3`，装在 `react-harmony` 这个名字下。为什么需要第二份 react，见 [后文](#两套-react-native-如何共存)。
- 项目里每个要在 HarmonyOS 上用到的 Expo 模块，再装一个同名的 `@expo-harmony/expo-*` 包，例如 `expo-constants` 配 `@expo-harmony/expo-constants`。已移植的列表见 [仓库 README](../README.md#supported-libraries)。装完可以用 `npx expo-harmony modules list` 检查，它会列出每个模块是否支持 Harmony。

## 配置 app.json

demo 的配置在 [`apps/demo/app.json`](../apps/demo/app.json)，要改三处。

第一，`platforms` 加 `harmony`：

```json
"platforms": ["ios", "android", "harmony"]
```

第二，`plugins` 注册 `@expo-harmony/prebuild-config`，放在最后。它注册 Harmony 的 Base Mods，其他 Harmony 插件要排在它前面：

```json
"plugins": [
  "expo-router",
  "expo-font",
  "@expo-harmony/expo-font",
  "@expo-harmony/expo-splash-screen",
  "@expo-harmony/prebuild-config"
]
```

官方插件和 `@expo-harmony/expo-*` 插件成对出现：前者管 iOS 和 Android，后者管 HarmonyOS。demo 里 `expo-splash-screen` 和 `@expo-harmony/expo-splash-screen` 的参数只差图标格式，鸿蒙环境是可以用 SVG 的。

第三，加 `harmony` 配置块：

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
- `targetApiVersion` 和 `compatibleSdkVersion` 默认分别为 24（HarmonyOS 6.1.1）和 13（HarmonyOS 5.0.1）。应用的最低兼容版本须不低于所有原生依赖的要求：`expo-constants` 为 14、`expo-fetch` 为 20、`expo-file-system` 为 21，因此 demo 显式设置为 21。
- 权限声明会写进生成的 `module.json5`。

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
  // RNOH 0.84 和 Expo SDK 55 的 React 渲染层版本不同
  aliases: { react: 'react-harmony' },
});
```

- 所有 `expo-harmony` 命令都会在 CLI 入口自动设置 `EXPO_HARMONY=1` 和 `EXPO_METRO_TARGET=harmony` 并传递给子进程；无需在命令前添加 `cross-env`。应用配置和插件也可以使用这些变量判断 Harmony 环境。
- `enabled` 为 false 时 `withHarmonyConfig` 原样返回配置，也不加载 RNOH 的依赖。
- `aliases` 把 `react` 指到 `react-harmony`，是两套版本共存的关键一环。
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
- `--no-bundler`：连接已经在跑的 Metro，不起新的。

不指定 `--device` 时，优先用已连接设备；没有设备就等启动中的模拟器，否则自动拉起唯一的本地模拟器。自动拉起需要 DevEco Studio 6.1.0 或更新版本。

iOS 和 Android 的命令没有任何变化，`expo run:ios`、`expo run:android` 照旧。

## 签名

不配置签名只会收到警告，不影响未签名构建。要往真机装 Release 包，需要签名材料：证书、私钥库和 profile 文件，DevEco Studio 可以生成。把它们写成一个 JSON 文件，字段和 DevEco Studio 写进 `build-profile.json5` 的 `signingConfigs` 一致：`certpath`、`storeFile`、`profile`、`storePassword`、`keyAlias`、`keyPassword`、`signAlg`。

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

## 两套 React Native 如何共存

RNOH 和官方 React Native 是两条发布线，版本对不齐是常态：Expo SDK 锁自己的 `react-native`，RNOH 锁自己的，RNOH 多数时候落后于官方最新版。expo-harmony 不要求两边一致，做法是把两套都装进同一个 `node_modules`，打包时按平台分流。demo 当前的组合：

| | iOS / Android | HarmonyOS |
| --- | --- | --- |
| React Native | `react-native@0.83.6`（Expo SDK 55 指定） | `@react-native-oh/react-native-harmony@0.84.1`（RNOH，基于 RN 0.84.1） |
| React | `react@19.2.0` | `react-harmony`（即 `react@19.2.3`） |
| 原生构建 | CocoaPods / Gradle | OHPM + Hvigor，依赖 `@rnoh/react-native-openharmony@0.84.1` |

### Metro 按平台分流

`EXPO_METRO_TARGET` 不是 `harmony` 时，`withHarmonyConfig` 原样返回配置，iOS/Android/Web 的打包走 Expo 原有 resolver，下面的规则一条都不生效。

是 `harmony` 时，Harmony 请求先经过重定向规则，再进 RNOH resolver；RNOH 解析具体文件时又委托回 Expo 原有 resolver，所以 Expo Router、TypeScript paths 这些能力都保留。重定向规则有三种来源：

- `import 'react-native'` 由 RNOH resolver 换成 `@react-native-oh/react-native-harmony`。这是 RNOH 自带的规则，`withHarmonyConfig` 只是把它的 resolver 接进来。
- `import 'react'` 命中 metro.config.js 里的 `aliases`，换成 `react-harmony`。
- 适配包在自己的 package.json 里声明 `harmony.alias`。`@react-native-ohos/react-native-reanimated` 的声明长这样：

  ```json
  {
    "harmony": {
      "alias": "react-native-reanimated",
      "redirectInternalImports": true
    }
  }
  ```

业务代码不用改，仍然写 `import { View } from 'react-native'` 和 `import { useState } from 'react'`。

### 为什么要第二份 react

一个 bundle 里只能有一个 react 实例，出现两个会报 hooks 错误。RNOH 0.84 的渲染层配 react 19.2.3，Expo SDK 55 锁 react 19.2.0，两边不能共用，也不能只留一份。于是用 npm alias 装出 `react-harmony`：harmony 打包时，所有 `react` 导入都指向它；iOS/Android 打包时这条别名不生效，继续用 19.2.0。RNOH 升级时，`react-harmony` 指向的版本跟着调。

### 第三方库

有 RNOH 社区适配的库，官方包和适配包成对安装。demo 的组合：

| 官方包 | 版本 | RNOH 适配包 | 版本 |
| --- | --- | --- | --- |
| `react-native-reanimated` | 4.2.1 | `@react-native-ohos/react-native-reanimated` | 4.0.2-beta.1 |
| `react-native-gesture-handler` | 2.30.0 | `@react-native-ohos/react-native-gesture-handler` | 2.30.1 |
| `react-native-worklets` | 0.7.4 | `@react-native-ohos/react-native-worklets` | 1.0.0 |

适配包声明了 `harmony.alias`，业务代码 import 官方包名即可，不用写条件导入。适配包的版本跟着 RNOH 走，不跟官方包对齐，功能上会有差距，升级前看对应仓库的说明。

没有适配包的库分两种。纯 JS 的库直接用，两个平台共用。带原生代码的库在 HarmonyOS 上没有实现，要么找替代，要么用 `@expo-harmony/metro-config` 的 `redirects`、`emptyModules`、`resolveRequest` 在 harmony 打包时替换或屏蔽，写法见[它的 README](../packages/metro-config/README.md)。

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
