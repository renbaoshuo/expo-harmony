# @expo-harmony/expo-network

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-network) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/network/)

为 HarmonyOS 上的 React Native 应用提供 Expo Network 的原生实现，与官方 `expo-network` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install expo-network@~57.0.3 @expo-harmony/expo-network
```

## API 对照表

```ts
import * as Network from 'expo-network';
```

### Hooks

#### `Network.useNetworkState()`

无参数，返回 `NetworkState`。首次渲染时返回空对象，获取到网络状态后更新；订阅期间会随网络状态变化更新。

### Methods

#### `Network.getNetworkStateAsync()`

无参数，返回 `Promise<NetworkState>`，包含系统默认网络的类型、连接状态和互联网可达状态。没有默认网络时，`type` 为 `NONE`，另外两个字段为 `false`；无法识别网络类型或读取网络信息失败时，`type` 为 `UNKNOWN`，`isConnected` 和 `isInternetReachable` 为 `false`。

`isInternetReachable` 仅在系统确认网络可访问互联网且未处于连通性检查状态时为 `true`；VPN 网络还要求系统报告非零下行带宽。该字段表示系统的连通性判断，不保证特定网站可访问。

#### `Network.getIpAddressAsync()`

无参数，返回 `Promise<string>`，包含系统默认网络的 IPv4 地址。没有默认网络或没有可用的 IPv4 地址时返回 `"0.0.0.0"`；读取失败时抛出 `ERR_NETWORK_IP_ADDRESS`。

#### `Network.isAirplaneModeEnabledAsync()`

无参数，返回 `Promise<boolean>`，表示系统飞行模式开关状态。读取失败或系统返回无效值时抛出 `ERR_NETWORK_AIRPLANE_MODE`。HarmonyOS API 21 起，飞行模式相关系统设置项已废弃。

### Event subscriptions

#### `Network.addNetworkStateListener(listener)`

参数 `listener` 接收一个 `NetworkStateEvent`。订阅成功后会收到当前网络状态，之后系统默认网络状态变化时也会收到更新。返回 `EventSubscription`，调用其 `remove()` 方法取消订阅。

### Types

#### `NetworkState`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `type?` | `NetworkStateType` | 当前系统默认网络的类型 |
| `isConnected?` | `boolean` | 网络类型可识别时为 `true`；无网络或类型未知时为 `false` |
| `isInternetReachable?` | `boolean` | 系统是否确认当前默认网络可访问互联网 |

类型声明将这三个字段标为可选；HarmonyOS 返回的网络状态对象始终包含这三个字段。网络类型未知时，系统仍可能确认互联网可达，因此 `isInternetReachable` 可能为 `true`。

#### `NetworkStateEvent`

`NetworkState` 的类型别名，作为 `addNetworkStateListener` 回调的参数。

### Enums

#### `NetworkStateType`

| 成员 | 含义 |
| --- | --- |
| `NONE` | 没有活动网络连接 |
| `UNKNOWN` | 无法识别网络类型 |
| `CELLULAR` | 蜂窝网络 |
| `WIFI` | Wi-Fi |
| `BLUETOOTH` | 蓝牙网络 |
| `ETHERNET` | 以太网 |
| `VPN` | VPN 网络 |

- `WIMAX`：HarmonyOS 不提供对应的网络类型。
- `OTHER`：HarmonyOS 不提供对应的网络类型；无法识别的类型会返回 `UNKNOWN`。

### Error codes

| 错误码 | 触发条件 |
| --- | --- |
| `ERR_NETWORK_IP_ADDRESS` | 读取默认网络或其连接属性失败，或系统返回无效网络句柄。 |
| `ERR_NETWORK_AIRPLANE_MODE` | 读取飞行模式设置失败或设置值无效。 |

### Permissions

读取网络状态和地址需要 `ohos.permission.GET_NETWORK_INFO`。本包已声明此权限，由系统授予，无需弹窗申请。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
