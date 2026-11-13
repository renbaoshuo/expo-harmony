# @expo-harmony/expo-constants

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-constants) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/constants/)

为 HarmonyOS 上的 React Native 应用提供 Expo Constants 的原生实现，与官方 `expo-constants` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 14（HarmonyOS 5.0.2）。

```bash
npm install @expo-harmony/expo-constants expo-constants@~57.0.22
```

## API 对照表

### Constants

#### `Constants.appOwnership`

类型：`AppOwnership | null`

始终返回 `null`。该属性已弃用。

#### `Constants.debugMode`

类型：`boolean`

调试构建返回 `true`，发布构建返回 `false`。

#### `Constants.deviceName`

类型：`string`

依次返回设备市场名、产品型号；都不可用时使用 `HarmonyOS <deviceType>`，仍不可用则返回 `HarmonyOS device`。

#### `Constants.deviceYearClass`

类型：`null`

始终返回 `null`。该属性已弃用。

#### `Constants.easConfig`

类型：`EASConfig | null`

使用内嵌配置时返回该配置；使用 Expo Updates 清单时返回其中的 `extra.eas`。没有对应配置时返回 `null`。

#### `Constants.executionEnvironment`

类型：`ExecutionEnvironment`

始终返回 `'bare'`。

#### `Constants.expoConfig`

类型：`ExpoConfig | null`

使用内嵌配置时返回该配置；启动 Expo Updates 下载的更新时返回清单中的 `extra.expoClient`。配置缺失或无效时返回 `null`。

#### `Constants.expoGoConfig`

类型：`ExpoGoConfig | null`

使用内嵌配置时返回该配置；使用 Expo Updates 清单时返回其中的 `extra.expoGo`。没有对应配置时返回 `null`。

#### `Constants.expoRuntimeVersion`

- HarmonyOS 上不提供此字段；启用 `expo-updates` 时，可通过 `Updates.runtimeVersion` 获取运行时版本。

#### `Constants.expoVersion`

- HarmonyOS 上不运行 Expo Go，因此不提供 Expo Go 版本。

#### `Constants.experienceUrl`

- HarmonyOS 应用没有对应的运行时地址。

#### `Constants.isDetached`

- HarmonyOS 应用不提供此字段。

#### `Constants.intentUri`

- HarmonyOS 应用不提供此字段。

#### `Constants.isHeadless`

类型：`boolean`

TaskManager 为后台任务冷启动的实例返回 `true`；普通界面启动时返回 `false`。应用进入后台不会改变该值。

#### `Constants.linkingUri`

- HarmonyOS 应用没有对应的运行时地址。

#### `Constants.manifest`

类型：`EmbeddedManifest | null`

内嵌的 Expo 配置对象。使用 Expo Updates 清单、配置缺失或读取失败时返回 `null`。该属性已弃用。

#### `Constants.manifest2`

类型：`ExpoUpdatesManifest | null`

Expo Updates 提供的清单；没有该清单时返回 `null`。

#### `Constants.platform`

类型：`PlatformManifest | undefined`

应用信息包含 `harmony` 字段。系统未能提供有效的应用信息时返回 `undefined`。

| 属性          | 类型     | 说明          |
| ------------- | -------- | ------------- |
| `bundleName`  | `string` | 应用包名      |
| `versionName` | `string` | 应用版本名    |
| `versionCode` | `number` | 应用版本号    |
| `deviceType`  | `string` | 设备类型      |
| `apiVersion`  | `number` | 系统 API 版本 |
| `osFullName`  | `string` | 系统版本全名  |

#### `Constants.sessionId`

类型：`string`

当前 React Native 运行时的随机标识。新建或重载运行时时会生成新的标识。

#### `Constants.statusBarHeight`

类型：`number`

状态栏高度，单位为 vp，会随窗口模式和状态栏可见性变化。无界面启动、读取失败或高度无效时返回 `0`。

#### `Constants.systemFonts`

类型：`string[]`

设备提供的系统字体名称列表，去重并按名称排序。无界面启动或读取失败时返回空数组。

#### `Constants.systemVersion`

类型：`string`

设备的系统显示版本。

### Methods

#### `Constants.getWebViewUserAgentAsync()`

返回 `Promise<string | null>`，即系统 WebView 的默认用户代理字符串。读取失败时返回 `null`。该值与 `fetch` 请求使用的用户代理不一定相同。

### Types

#### `NativeConstants`

`Constants` 对象的属性和方法类型。

#### `PlatformManifest`

HarmonyOS 应用信息类型，包含 `harmony` 字段；字段含义见 `Constants.platform`。

#### `AndroidManifest`

- HarmonyOS 不提供对应的应用清单类型。

#### `IOSManifest`

- HarmonyOS 不提供对应的应用清单类型。

#### `WebManifest`

- HarmonyOS 不提供对应的应用清单类型。

#### `EASConfig`

`Constants.easConfig` 的类型；取值行为见对应属性。

#### `ExpoGoConfig`

`Constants.expoGoConfig` 的类型；取值行为见对应属性。

#### `ExpoGoPackagerOpts`

- HarmonyOS 应用不提供 Expo Go 客户端配置。

#### `ClientScopingConfig`

- HarmonyOS 应用不提供客户端作用域配置。

#### `Manifest`

Expo Updates 清单类型，与 `ExpoUpdatesManifest` 对应。

#### `ManifestAsset`

Expo Updates 清单中资源条目的类型。

#### `ManifestExtra`

Expo Updates 清单 `extra` 字段的类型。

### Enums

#### `AppOwnership`

HarmonyOS 上 `Constants.appOwnership` 始终返回 `null`，不会返回 `AppOwnership.Expo`。

#### `ExecutionEnvironment`

HarmonyOS 上 `Constants.executionEnvironment` 始终返回 `ExecutionEnvironment.Bare`。

#### `UserInterfaceIdiom`

- HarmonyOS 应用信息不提供此分类。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
