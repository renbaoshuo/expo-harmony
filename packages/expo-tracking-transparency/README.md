# @expo-harmony/expo-tracking-transparency

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-tracking-transparency) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/tracking-transparency/)

为 HarmonyOS 上的 React Native 应用提供 Expo Tracking Transparency 的原生实现，与官方 `expo-tracking-transparency` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-tracking-transparency expo-tracking-transparency@~57.0.2
```

## API 对照表

### Hooks

#### `TrackingTransparency.useTrackingPermissions(options?)`

`options` 可选，类型为 `PermissionHookOptions`。`get` 默认为 `true`，表示挂载时查询权限；`request` 默认为 `false`，设为 `true` 时挂载后请求权限。返回 `[PermissionResponse | null, requestPermission, getPermission]`，后两个方法分别请求和查询权限。

### Methods

#### `TrackingTransparency.getTrackingPermissionsAsync()`

无参数，返回 `Promise<PermissionResponse>`，查询跨应用跟踪权限状态，不显示授权对话框。响应的 `expires` 始终为 `'never'`。

HarmonyOS SDK API 20 及以上可直接查询完整权限状态。API 13–19 未授权时，根据此前请求权限的结果区分 `denied` 与 `undetermined`；如果用户在系统设置中修改了权限，状态可能无法准确区分。

#### `TrackingTransparency.requestTrackingPermissionsAsync()`

无参数，返回 `Promise<PermissionResponse>`，请求跨应用跟踪权限。已授权时返回当前状态；未授权时由系统处理请求。用户拒绝或系统不再允许请求后，`canAskAgain` 为 `false`。并发调用共用一次请求结果。

#### `TrackingTransparency.isAvailable()`

无参数，返回 `boolean`。HarmonyOS 始终返回 `true`，表示接口可用，不代表已经获得授权。

#### `TrackingTransparency.getAdvertisingId()`

接口签名返回 `string | null`，无参数。

- HarmonyOS 只提供异步 OAID 读取；调用此方法会以 `ERR_UNAVAILABLE` 抛出，请改用 `getAdvertisingIdAsync()`。

#### `getAdvertisingIdAsync()`

从 `@expo-harmony/expo-tracking-transparency` 导入。无参数，返回 `Promise<string | null>`。获得权限时读取 OAID；未授权、标识符为空或全零时返回 `null`。读取期间权限被撤回时也返回 `null`。读取失败且权限仍有效时，Promise 以 `ERR_TRACKING_TRANSPARENCY_ADVERTISING_ID` 拒绝。

### Types

#### `PermissionResponse`

权限查询和请求方法的返回类型，包含 `status`、`granted`、`canAskAgain` 和 `expires`。`status` 为 `PermissionStatus`；`granted` 表示是否已授权；`canAskAgain` 表示是否还能再次请求；HarmonyOS 上 `expires` 始终为 `'never'`。

#### `PermissionExpiration`

权限过期时间类型。HarmonyOS 上该权限长期有效，取值为 `'never'`。

#### `PermissionHookOptions`

传给 `useTrackingPermissions` 的选项：`get?: boolean` 控制挂载时是否查询权限，默认 `true`；`request?: boolean` 控制挂载时是否请求权限，默认 `false`。

### Enums

#### `PermissionStatus`

| 成员 | 值 | 含义 |
| --- | --- | --- |
| `GRANTED` | `'granted'` | 已授权 |
| `DENIED` | `'denied'` | 已拒绝 |
| `UNDETERMINED` | `'undetermined'` | 尚未决定 |

### Error codes

#### `ERR_TRACKING_TRANSPARENCY_BACKGROUND`

应用未处于前台或没有界面时，请求尚未授权的跨应用跟踪权限会以此错误码拒绝。

#### `ERR_TRACKING_TRANSPARENCY_PERMISSION`

宿主应用未声明有效的 `ohos.permission.APP_TRACKING_CONSENT`，或系统无法处理该权限请求时，查询或请求会以此错误码拒绝。

#### `ERR_TRACKING_TRANSPARENCY_ADVERTISING_ID`

读取 OAID 失败且跨应用跟踪权限仍有效时，`getAdvertisingIdAsync()` 以此错误码拒绝。

#### `ERR_UNAVAILABLE`

HarmonyOS 不支持同步的 `getAdvertisingId()`，调用时会以此错误码抛出。

### Permissions

#### `ohos.permission.APP_TRACKING_CONSENT`

宿主应用需声明此权限，才能查询或请求跨应用跟踪权限，以及读取 OAID。未声明或声明无效时，查询和请求会以 `ERR_TRACKING_TRANSPARENCY_PERMISSION` 拒绝；未授权时，`getAdvertisingIdAsync()` 返回 `null`。系统设置中的「要求应用请求关联」开关会影响是否显示授权对话框；关闭时系统可能直接授予权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
