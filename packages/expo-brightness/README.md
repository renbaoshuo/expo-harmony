# @expo-harmony/expo-brightness

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-brightness) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/brightness/)

为 HarmonyOS 上的 React Native 应用提供 Expo Brightness 的原生实现，与官方同版本的 `expo-brightness` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-brightness expo-brightness
```

## API 对照表

### Hooks

#### `Brightness.usePermissions(options)`

- `options` 可设置 `get` 和 `request`，分别控制挂载时自动查询权限和自动请求权限；默认只查询。
- 返回 `[PermissionResponse | null, request, get]`；后两个函数均返回 `Promise<PermissionResponse>`。权限状态始终为已授权，请求不会弹出对话框。

### Methods

#### `Brightness.getBrightnessAsync()`

返回 `Promise<number>`，当前窗口亮度，范围为 `0` 到 `1`。窗口跟随系统亮度时，读取系统亮度设置并归一化到此范围；开启自动亮度时，返回值可能与屏幕当前的实际亮度不同。

#### `Brightness.setBrightnessAsync(brightnessValue)`

设置当前窗口亮度并返回 `Promise<void>`。`brightnessValue` 为 `0` 到 `1` 的数值，超出范围时会截断到边界，传入 `NaN` 会抛出 `TypeError`。窗口处于前台且获得焦点时设置才会生效。[窗口亮度文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-window-window)

HarmonyOS 6.1.0 起，手机和平板用户在控制中心调整亮度时，窗口会恢复跟随系统。HarmonyOS 5.0.2 起，PC 和 2in1 设备的窗口亮度与系统亮度同步。

#### `Brightness.getSystemBrightnessAsync()`

返回 `Promise<number>`，行为和 `getBrightnessAsync()` 相同，读取当前窗口亮度或窗口跟随系统时的系统亮度设置。

#### `Brightness.setSystemBrightnessAsync(brightnessValue)`

参数范围和行为与 `setBrightnessAsync()` 相同，设置当前窗口亮度并返回 `Promise<void>`，不会直接修改系统亮度设置。

#### `Brightness.restoreSystemBrightnessAsync()`

返回 `Promise<void>`。

- HarmonyOS 上此方法无法将窗口亮度恢复为跟随系统，因此调用不修改亮度。`setBrightnessAsync(-1)` 会将亮度截断为 `0`。

#### `Brightness.isUsingSystemBrightnessAsync()`

返回 `Promise<boolean>`。

- HarmonyOS 上无法通过此方法查询窗口是否跟随系统亮度，因此始终返回 `false`。

#### `Brightness.isAvailableAsync()`

返回 `Promise<boolean>`，在 HarmonyOS 上始终为 `true`。

#### `Brightness.getSystemBrightnessModeAsync()`

返回 `Promise<BrightnessMode>`。

- HarmonyOS 上无法读取系统亮度模式，因此始终返回 `BrightnessMode.UNKNOWN`。

#### `Brightness.setSystemBrightnessModeAsync(brightnessMode)`

`brightnessMode` 为 `BrightnessMode`，返回 `Promise<void>`。

- HarmonyOS 上此方法不修改系统亮度模式。

#### `Brightness.getPermissionsAsync()`

返回 `Promise<PermissionResponse>`，权限状态始终为已授权。

#### `Brightness.requestPermissionsAsync()`

返回 `Promise<PermissionResponse>`，权限状态始终为已授权，不会弹出对话框。

### Event subscriptions

#### `Brightness.addBrightnessListener(listener)`

`listener` 接收 `BrightnessEvent`，返回 `EventSubscription`，可调用 `remove()` 取消订阅。

- HarmonyOS 不提供亮度变化事件，回调不会触发。

### Types

#### `BrightnessEvent`

事件对象包含 `brightness: number`，表示 `0` 到 `1` 范围内的屏幕亮度。HarmonyOS 上此事件不会触发。

#### `PermissionExpiration`

类型为 `'never' | number`；HarmonyOS 上始终为 `'never'`。

#### `PermissionHookOptions`

包含可选布尔值 `get` 和 `request`，分别控制挂载时是否自动查询权限、是否自动请求权限。默认 `get` 为 `true`、`request` 为 `false`。

#### `PermissionResponse`

| 属性 | 类型 | HarmonyOS 上的值 |
| --- | --- | --- |
| `status` | `PermissionStatus` | `'granted'` |
| `granted` | `boolean` | `true` |
| `expires` | `PermissionExpiration` | `'never'` |
| `canAskAgain` | `boolean` | `true` |

### Enums

#### `BrightnessMode`

| 成员 | 值 | 含义 |
| --- | --- | --- |
| `UNKNOWN` | `0` | 无法判断；HarmonyOS 始终返回此值。 |
| `AUTOMATIC` | `1` | 系统根据环境光自动调整亮度。 |
| `MANUAL` | `2` | 系统不自动调整亮度。 |

#### `PermissionStatus`

| 成员 | 值 |
| --- | --- |
| `GRANTED` | `'granted'` |
| `UNDETERMINED` | `'undetermined'` |
| `DENIED` | `'denied'` |

HarmonyOS 的权限接口始终返回 `PermissionStatus.GRANTED`。

### Error codes

#### `ERR_BRIGHTNESS_SYSTEM`

读取系统亮度设置失败或系统未返回有效亮度值时抛出。

### Permissions

HarmonyOS 上读取和设置窗口亮度无需用户授权，权限状态始终为已授权。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
