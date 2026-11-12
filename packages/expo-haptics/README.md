# @expo-harmony/expo-haptics

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-haptics) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/haptics/)

为 HarmonyOS 上的 React Native 应用提供 Expo Haptics 的原生实现，与官方同版本的 `expo-haptics` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-haptics expo-haptics@57.0.3
```

## API 对照表

### Methods

#### `Haptics.notificationAsync(type?)`

触发通知类振动，返回 `Promise<void>`；省略 `type` 时使用 `NotificationFeedbackType.Success`。HarmonyOS API 18 及以上先尝试系统通知反馈，再尝试设备支持时可用的振动序列和通用预设；API 13 至 17 使用通用预设。对应效果不可用时会回退为一次定时振动，节奏和强度可能简化。

#### `Haptics.impactAsync(style?)`

触发碰撞类振动，返回 `Promise<void>`；省略 `style` 时使用 `ImpactFeedbackStyle.Medium`。`light` 和 `soft` 使用柔和预设，`medium` 和 `heavy` 使用硬朗预设，`rigid` 使用锐利预设。HarmonyOS API 13 及以上会按设备支持情况使用预设效果；不支持时回退为一次定时振动。硬件不支持调节预设强度时，各样式之间的强度差异可能不明显。

#### `Haptics.selectionAsync()`

触发一次较轻的选择变化振动，返回 `Promise<void>`。设备不支持柔和预设时回退为一次 70 毫秒的定时振动。

#### `Haptics.performAndroidHapticsAsync(type)`

`type` 为 `AndroidHaptics`，返回 `Promise<void>`。

- HarmonyOS 没有对应的 Android 专用振动类型，调用不会产生振动。

### Enums

#### `ImpactFeedbackStyle`

##### `Light` (`'light'`)

表示小型、轻量元素的碰撞反馈。

##### `Medium` (`'medium'`)

表示中等尺寸元素的碰撞反馈。

##### `Heavy` (`'heavy'`)

表示大型、沉重元素的碰撞反馈。

##### `Soft` (`'soft'`)

表示弹性较大的元素的碰撞反馈。

##### `Rigid` (`'rigid'`)

表示弹性较小的元素的碰撞反馈。

#### `NotificationFeedbackType`

##### `Success` (`'success'`)

表示任务成功完成。

##### `Warning` (`'warning'`)

表示任务产生警告。

##### `Error` (`'error'`)

表示任务失败。

#### `AndroidHaptics`

- 其中的振动类型没有对应的 HarmonyOS 系统效果。

### Error codes

#### `ERR_HAPTICS_INVALID_ARGUMENT`

`notificationAsync` 的 `type` 或 `impactAsync` 的 `style` 不是支持的枚举值时，Promise 会以此错误码拒绝，且不会开始振动。

#### `ERR_HAPTICS_VIBRATION`

系统启动振动失败时，Promise 会以此错误码拒绝。

#### `ERR_HAPTICS_DESTROYED`

模块关闭或重载后继续调用时，Promise 会以此错误码拒绝。

### Permissions

#### `ohos.permission.VIBRATE`

振动所需的普通权限，由系统在安装时授予，无需运行时授权。设备没有振动能力时，调用仍会正常完成，但不会产生振动。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
