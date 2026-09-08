# @expo-harmony/expo-brightness

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-brightness) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/brightness/)

为 HarmonyOS 上的 React Native 应用提供 Expo Brightness 的原生实现，与官方同版本的 `expo-brightness` 配套使用。支持读取和设置当前窗口的亮度。

## 安装

```bash
npm install @expo-harmony/expo-brightness expo-brightness@55.0.13
```

## API 对照表

### Hooks

#### `usePermissions(options)`

返回 `[PermissionResponse | null, request, get]`，分别是权限状态、请求权限和查询权限的函数。窗口亮度不需要授权，状态恒为已授权，请求时不弹出对话框。

### Methods

#### `Brightness.getBrightnessAsync()`

返回 `Promise<number>`，当前窗口亮度，取值 0 到 1。窗口没有单独设置过亮度时返回系统亮度。

#### `Brightness.getPermissionsAsync()`

返回 `Promise<PermissionResponse>`，恒为已授权。窗口亮度不需要授权。

#### `Brightness.getSystemBrightnessAsync()`

返回 `Promise<number>`，取值与 `getBrightnessAsync()` 一致。

#### `Brightness.getSystemBrightnessModeAsync()`

返回 `Promise<BrightnessMode>`，恒为 `BrightnessMode.UNKNOWN`。

#### `Brightness.isAvailableAsync()`

返回 `Promise<boolean>`，恒为 `true`。

#### `Brightness.isUsingSystemBrightnessAsync()`

返回 `Promise<boolean>`，恒为 `false`。

#### `Brightness.requestPermissionsAsync()`

返回 `Promise<PermissionResponse>`，恒为已授权，不弹出对话框。

#### `Brightness.restoreSystemBrightnessAsync()`

返回 `Promise<void>`，空操作，窗口亮度不会恢复为跟随系统。

#### `Brightness.setBrightnessAsync(brightnessValue)`

返回 `Promise<void>`，设置当前窗口亮度。`brightnessValue` 取值 0 到 1，超出范围会被截断，传入 `NaN` 抛出 `TypeError`。只修改当前窗口，不改动系统亮度设置；窗口处于前台且获焦时生效。

#### `Brightness.setSystemBrightnessAsync(brightnessValue)`

返回 `Promise<void>`，取值与边界处理和 `setBrightnessAsync()` 一致，只设置当前窗口亮度，不修改系统亮度设置。

#### `Brightness.setSystemBrightnessModeAsync(brightnessMode)`

返回 `Promise<void>`，空操作，不修改系统亮度模式。

### Event Subscriptions

> **未实现的内容**
>
> - `Brightness.addBrightnessListener(listener)`：HarmonyOS 没有对应的亮度变化事件，可以订阅和移除，但回调不会触发。

### Types

#### `BrightnessEvent`

| 属性         | 类型     |
| ------------ | -------- |
| `brightness` | `number` |

该事件在 HarmonyOS 上不会触发。

#### `PermissionExpiration`

`'never' | number`，恒为 `'never'`。

#### `PermissionHookOptions`

`usePermissions` 的选项类型。HarmonyOS 上不影响权限结果。

#### `PermissionResponse`

| 属性          | 类型                   | 说明             |
| ------------- | ---------------------- | ---------------- |
| `status`      | `PermissionStatus`     | 恒为 `'granted'` |
| `granted`     | `boolean`              | 恒为 `true`      |
| `expires`     | `PermissionExpiration` | 恒为 `'never'`   |
| `canAskAgain` | `boolean`              | 恒为 `true`      |

### Enums

#### `BrightnessMode`

| 成员        | 值  | 含义                             |
| ----------- | --- | -------------------------------- |
| `UNKNOWN`   | `0` | 无法判断，HarmonyOS 上只返回该值 |
| `AUTOMATIC` | `1` | 由系统根据环境光自动调整亮度     |
| `MANUAL`    | `2` | 亮度保持不变，不由系统调整       |

#### `PermissionStatus`

`'granted' | 'denied' | 'undetermined'`，HarmonyOS 上恒为 `'granted'`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
