# @expo-harmony/expo-constants

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-constants) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/constants/)

为 HarmonyOS 上的 React Native 应用提供 Expo Constants 的原生实现，用于读取应用配置、设备与系统信息以及 HarmonyOS 平台元数据，与官方同版本的 `expo-constants` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-constants expo-constants@55.0.17
```

鸿蒙适配的原生模块会通过 Autolinking 自动接入。最低支持 HarmonyOS 5.0.2（API 14），宿主的 `compatibleSdkVersion` 也需满足此要求。

本包需要在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-constants`，并将 `@expo-harmony/prebuild-config` 放在它后面：

```json
{
  "expo": {
    "plugins": [
      "@expo-harmony/expo-constants",
      "@expo-harmony/prebuild-config"
    ]
  }
}
```

Constants Config Plugin 会把公开的 Expo 配置写入应用资源（`entry/src/main/resources/rawfile/app.config`），供运行时读取 `expoConfig`、`easConfig` 等配置字段；并在生成的 `harmony/hvigorfile.ts` 中注册构建期刷新，公开配置变更后无需重新 prebuild，下次构建会自动更新。

业务代码依旧使用官方包：

```ts
import Constants from 'expo-constants';

const config = Constants.expoConfig;
const { bundleName, deviceType } = Constants.platform.harmony;
```

## API 对照表

### Constants

#### `Constants.appOwnership`

类型：`AppOwnership | null`

恒为 `null`。HarmonyOS 上没有 Expo Go，该属性已弃用。

#### `Constants.debugMode`

类型：`boolean`

调试构建返回 `true`，发布构建返回 `false`。

#### `Constants.deviceName`

类型：`string`

设备名称。依次取产品市场名和产品型号；都为空时用设备类型拼成 `HarmonyOS <deviceType>`，仍为空则返回 `HarmonyOS device`。

#### `Constants.deviceYearClass`

类型：`null`

恒为 `null`。该属性已弃用，HarmonyOS 没有设备年份分级。

#### `Constants.easConfig`

类型：`EASConfig | null`

HarmonyOS 上不使用 EAS，取值与 `expoConfig` 相同；读不到配置时为 `null`。

#### `Constants.executionEnvironment`

类型：`ExecutionEnvironment`

恒为 `'bare'`。

#### `Constants.expoConfig`

类型：`ExpoConfig | null`

内嵌的 Expo 配置对象，由配置插件写入应用资源。读不到时返回 `null`。

#### `Constants.expoGoConfig`

类型：`ExpoGoConfig | null`

HarmonyOS 上不运行 Expo Go，取值与 `expoConfig` 相同；读不到配置时为 `null`。

#### `Constants.isHeadless`

类型：`boolean`

恒为 `false`。

#### `Constants.manifest`

类型：`EmbeddedManifest | null`

内嵌的 Expo 配置对象，与 `expoConfig` 同源。读不到时返回 `null`。该属性已弃用。

#### `Constants.manifest2`

类型：`null`

恒为 `null`。HarmonyOS 上不使用 EAS Update，没有远程清单。

#### `Constants.platform`

类型：`PlatformManifest`

平台清单，HarmonyOS 上只有 `harmony` 字段：

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

当前应用会话的随机标识。不同应用、同应用的不同次启动都不同。

#### `Constants.statusBarHeight`

类型：`number`

状态栏高度，单位为 vp，取系统默认区域的上边距。读取失败时返回 `0`。

#### `Constants.systemFonts`

类型：`string[]`

系统字体名称列表，去重后按名称排序。读取失败时返回空数组。

#### `Constants.systemVersion`

类型：`string`

系统版本，取设备的产品版本号。官方声明为 `number`，这里返回字符串。

> **未实现的内容**
>
> - `experienceUrl`、`linkingUri`：Expo Go 和开发服务器的运行时地址，HarmonyOS 上没有对应的取值来源。
> - `expoVersion`：Expo Go 的版本，HarmonyOS 上不运行 Expo Go。
> - `expoRuntimeVersion`：Expo Updates 的运行时版本，HarmonyOS 上不使用 Expo Updates。
> - `intentUri`：Android 的启动 Intent 地址，HarmonyOS 上没有对应的取值来源。
> - `isDetached`：旧版 detach 工作流遗留的属性，HarmonyOS 上没有对应的取值来源。

### Methods

#### `Constants.getWebViewUserAgentAsync()`

返回 `Promise<string | null>`，WebView 的默认用户代理字符串。读取失败时返回 `null`。该值与 `fetch` 请求使用的用户代理不一定相同。

### Types

#### `NativeConstants`

`Constants` 的类型，包含上面列出的属性和方法。

#### `PlatformManifest`

平台清单类型。HarmonyOS 上只有 `harmony` 字段，字段含义见 `Constants.platform`。

#### `EASConfig`、`ExpoGoConfig`

清单类型别名。HarmonyOS 上对应的 `easConfig` 和 `expoGoConfig` 取值与 `expoConfig` 相同。

> **未实现的内容**
>
> - `AndroidManifest`、`IOSManifest`、`WebManifest`：其他平台的清单类型，HarmonyOS 上没有取值来源。
> - `ExpoGoPackagerOpts`、`ClientScopingConfig`：Expo Go 与 EAS 的清单类型，HarmonyOS 上不产生这类数据。
> - `Manifest`、`ManifestAsset`、`ManifestExtra`：远程清单及其资源类型，HarmonyOS 上没有远程清单来源。

### Enums

#### `ExecutionEnvironment`

| 成员          | 值              | 含义                             |
| ------------- | --------------- | -------------------------------- |
| `Bare`        | `'bare'`        | 维护原生工程的 React Native 应用 |
| `Standalone`  | `'standalone'`  | 发布构建                         |
| `StoreClient` | `'storeClient'` | Expo Go 或开发客户端             |

HarmonyOS 上只返回 `Bare`。

> **未实现的内容**
>
> - `AppOwnership`：Expo Go 专属枚举，已弃用；HarmonyOS 上 `appOwnership` 恒为 `null`。
> - `UserInterfaceIdiom`：只在 `IOSManifest` 中使用，HarmonyOS 上没有取值来源。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
