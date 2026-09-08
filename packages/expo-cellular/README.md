# @expo-harmony/expo-cellular

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-cellular) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/cellular/)

为 HarmonyOS 上的 React Native 应用提供 Expo Cellular 的原生实现，与官方同版本的 `expo-cellular` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-cellular expo-cellular@55.0.13
```

HAR 已声明 `ohos.permission.GET_NETWORK_INFO`，这是普通级别、安装时授予的权限，应用不需要在 `app.json` 中额外配置。

## API 对照表

### Hooks

#### `usePermissions(options)`

返回 `[PermissionResponse | null, request, get]`，分别是权限状态、申请权限和查询权限的函数。HarmonyOS 不弹出授权框，三项都直接给出已授权结果。

### Methods

#### `Cellular.getCellularGenerationAsync()`

返回 `Promise<CellularGeneration>`，当前蜂窝网络代际。

双卡设备取默认订阅的 SIM 卡。SIM 卡未插入、未就绪或权限被拒时返回 `UNKNOWN`。代际按当前无线接入技术映射到枚举，无法识别的技术（包括 IWLAN）也返回 `UNKNOWN`。

`CELLULAR_5G` 只对应系统上报的 NR，系统上报其他技术时按对应代际返回。

#### `Cellular.allowsVoipAsync()`

返回 `Promise<boolean | null>`，恒为 `null`。HarmonyOS 没有提供判断运营商是否允许 VoIP 的接口。

#### `Cellular.getIsoCountryCodeAsync()`

返回 `Promise<string | null>`，服务商的 ISO 国家码，小写。取默认订阅 SIM 卡记录的国家码，没有 SIM 卡、SIM 卡未就绪或值为空时返回 `null`。

#### `Cellular.getCarrierNameAsync()`

返回 `Promise<string | null>`，服务商名称，取自 SIM 卡内的服务商名称记录，与当前注册的网络无关。没有 SIM 卡、SIM 卡未就绪或记录为空时返回 `null`。

双卡设备上取默认订阅的卡。这个值与 MCC/MNC 的取卡方式不同，两者可能来自不同的卡。

#### `Cellular.getMobileCountryCodeAsync()`

返回 `Promise<string | null>`，移动国家码（MCC），取 SIM 卡归属 PLMN 的前三位。没有 SIM 卡、SIM 卡未就绪或 PLMN 不是 5 到 6 位数字时返回 `null`。

#### `Cellular.getMobileNetworkCodeAsync()`

返回 `Promise<string | null>`，移动网络码（MNC），取 SIM 卡归属 PLMN 中 MCC 之后的部分，为 2 到 3 位数字。取卡方式与 MCC 相同，返回 `null` 的条件也一致。

#### `Cellular.getPermissionsAsync()`

返回 `Promise<PermissionResponse>`，恒为已授权。查询不读取系统运行时授权状态，也不弹出授权框。

#### `Cellular.requestPermissionsAsync()`

返回 `Promise<PermissionResponse>`，恒为已授权，不弹出授权框，与 `getPermissionsAsync()` 一致。

### Types

#### `PermissionResponse`

| 属性          | 类型                   | 说明             |
| ------------- | ---------------------- | ---------------- |
| `status`      | `PermissionStatus`     | 恒为 `'granted'` |
| `granted`     | `boolean`              | 恒为 `true`      |
| `expires`     | `PermissionExpiration` | 恒为 `'never'`   |
| `canAskAgain` | `boolean`              | 恒为 `true`      |

#### `PermissionExpiration`

`'never' | number`，HarmonyOS 上只返回 `'never'`。

#### `PermissionHookOptions`

`usePermissions` 的选项类型，控制挂载时是否自动查询或申请权限。权限恒为已授权，这些选项不改变结果。

### Enums

#### `PermissionStatus`

| 成员           | 值               |
| -------------- | ---------------- |
| `DENIED`       | `'denied'`       |
| `GRANTED`      | `'granted'`      |
| `UNDETERMINED` | `'undetermined'` |

HarmonyOS 上只返回 `GRANTED`。

#### `CellularGeneration`

| 成员          | 值  | 含义                                             |
| ------------- | --- | ------------------------------------------------ |
| `UNKNOWN`     | `0` | 未连接蜂窝网络或无法判断                         |
| `CELLULAR_2G` | `1` | 2G，含 GSM、1xRTT                                |
| `CELLULAR_3G` | `2` | 3G，含 WCDMA、HSPA、HSPAP、TD-SCDMA、EVDO、EHRPD |
| `CELLULAR_4G` | `3` | 4G，含 LTE、LTE-CA                               |
| `CELLULAR_5G` | `4` | 5G，仅含 NR                                      |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
