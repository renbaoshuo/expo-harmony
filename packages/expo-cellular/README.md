# @expo-harmony/expo-cellular

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-cellular) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/cellular/)

为 HarmonyOS 上的 React Native 应用提供 Expo Cellular 的原生实现，与官方 `expo-cellular` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-cellular expo-cellular@~57.0.2
```

## API 对照表

### Hooks

#### `usePermissions(options?)`

返回 `[PermissionResponse | null, request, get]`，分别是权限状态、申请权限和查询权限的函数。挂载后状态初始为 `null`，查询完成后为已授权。HarmonyOS 不弹出授权框。

### Methods

#### `Cellular.getCellularGenerationAsync()`

返回 `Promise<CellularGeneration>`，表示当前蜂窝网络代际。使用默认数据 SIM 卡的网络类型；设备通过 Wi-Fi 联网时仍可返回蜂窝网络代际。SIM 卡未就绪、权限不可用、蜂窝网络信息不可用或网络类型无法识别时返回 `UNKNOWN`。5G 仅对应系统上报的 NR；其他未映射类型（包括 IWLAN）返回 `UNKNOWN`。

#### `Cellular.allowsVoipAsync()`

返回 `Promise<boolean | null>`。

- HarmonyOS 不提供运营商 VoIP 状态查询，因此始终返回 `null`。

#### `Cellular.getIsoCountryCodeAsync()`

返回 `Promise<string | null>`，服务商的 ISO 国家码，字母为小写。优先使用默认语音 SIM 卡；未设置有效的默认语音卡或设备不支持语音通话时使用默认数据卡。没有就绪的 SIM 卡或记录为空时返回 `null`。

#### `Cellular.getCarrierNameAsync()`

返回 `Promise<string | null>`，SIM 卡中记录的服务商名称，与当前注册的网络无关。优先使用默认语音 SIM 卡；未设置有效的默认语音卡或设备不支持语音通话时使用默认数据卡。没有就绪的 SIM 卡或记录为空时返回 `null`。

#### `Cellular.getMobileCountryCodeAsync()`

返回 `Promise<string | null>`，SIM 卡归属 PLMN 的 MCC（三位移动国家码）。依次使用默认数据、短信和语音 SIM 卡；SIM 卡未就绪或 PLMN 不是 5 到 6 位数字时返回 `null`。

#### `Cellular.getMobileNetworkCodeAsync()`

返回 `Promise<string | null>`，SIM 卡归属 PLMN 中 MCC 之后的 MNC（两位或三位移动网络码）。SIM 卡选择顺序及返回 `null` 的条件与 `getMobileCountryCodeAsync()` 相同。

### Types

#### `PermissionResponse`

- `status: PermissionStatus`：始终为 `'granted'`。
- `granted: boolean`：始终为 `true`。
- `expires: PermissionExpiration`：始终为 `'never'`。
- `canAskAgain: boolean`：始终为 `true`。

#### `PermissionExpiration`

类型为 `'never' | number`。HarmonyOS 上只返回 `'never'`。

#### `PermissionHookOptions`

`usePermissions` 的可选参数，包含以下布尔值：

- `get`：挂载时自动查询权限，默认 `true`。
- `request`：挂载时自动申请权限，默认 `false`。HarmonyOS 不会显示授权框；若同时设为 `true`，只执行申请。

### Enums

#### `CellularGeneration`

- `UNKNOWN = 0`：未连接蜂窝网络或无法判断。
- `CELLULAR_2G = 1`：系统上报 GSM 或 1xRTT。
- `CELLULAR_3G = 2`：系统上报 WCDMA、HSPA、HSPAP、TD-SCDMA、EVDO 或 EHRPD。
- `CELLULAR_4G = 3`：系统上报 LTE 或 LTE-CA。
- `CELLULAR_5G = 4`：系统上报 NR。

#### `PermissionStatus`

- `DENIED = 'denied'`
- `GRANTED = 'granted'`
- `UNDETERMINED = 'undetermined'`

HarmonyOS 上只返回 `GRANTED`。

### Error codes

#### `ERR_CELLULAR_GENERATION`

系统查询蜂窝网络类型失败时抛出；权限、能力或 SIM 卡不可用等情况返回 `UNKNOWN`。

#### `ERR_CELLULAR_SIM`

系统查询 SIM 卡信息失败时抛出；SIM 卡不存在或系统不支持相关信息时返回 `null`。

### Permissions

#### `Cellular.getPermissionsAsync()`

返回 `Promise<PermissionResponse>`。HarmonyOS 上返回已授权状态，不弹出授权框。

#### `Cellular.requestPermissionsAsync()`

返回 `Promise<PermissionResponse>`。HarmonyOS 上返回已授权状态，不弹出授权框，与 `getPermissionsAsync()` 一致。

#### `ohos.permission.GET_NETWORK_INFO`

本包声明此普通权限以读取网络信息；HarmonyOS 在安装时授予，无需弹窗申请。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
