# @expo-harmony/expo-haptics

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-haptics) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/haptics/)

为 HarmonyOS 上的 React Native 应用提供 Expo Haptics 的原生实现，与官方同版本的 `expo-haptics` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-haptics expo-haptics@55.0.14
```

该原生库会声明 `ohos.permission.VIBRATE` 权限，这是普通级别、安装时授予的权限，应用不需要在 `app.json` 中额外配置。

振动效果取决于设备能力和系统设置，不同设备的实际触感存在差异。设备没有振动器时，调用不会报错，也不会产生振动。

## API 对照表

### Methods

#### `Haptics.notificationAsync(type?)`

返回 `Promise<void>`，触发一次通知类振动。`type` 取 `NotificationFeedbackType`，省略时按 `success` 处理。成功、警告、失败三种类型各有自己的振动节奏和强度。

API 18 及以上在设备支持时使用系统的成功、警告、失败反馈预设，不支持时改用其他振动方式；API 13–17 没有这组预设，改用通用振动效果，节奏与系统预设不同。

传入枚举之外的字符串时抛出 `ERR_HAPTICS_INVALID_ARGUMENT`，在发起振动之前拒绝。

#### `Haptics.impactAsync(style?)`

返回 `Promise<void>`，触发一次碰撞类振动。`style` 取 `ImpactFeedbackStyle`，省略时按 `medium` 处理。`light` 和 `soft` 对应低强度柔和效果，`medium` 和 `heavy` 对应硬朗效果，强度依次升高，`rigid` 对应锐利效果。这些效果从 API 12 起提供，各支持版本上都能用。

传入枚举之外的字符串时抛出 `ERR_HAPTICS_INVALID_ARGUMENT`，在发起振动之前拒绝。

#### `Haptics.selectionAsync()`

返回 `Promise<void>`，触发一次选择变化的振动，强度低于碰撞类。设备不支持所用的柔和效果时，改用一次较短的振动。

> **未实现的内容**
>
> - `performAndroidHapticsAsync()`：Android 专属接口，HarmonyOS 上直接返回，不振动也不报错。

### Enums

#### `ImpactFeedbackStyle`

| 成员       | 值         | 含义                 |
| ---------- | ---------- | -------------------- |
| `Light`    | `'light'`  | 小型轻量元素碰撞     |
| `Medium`   | `'medium'` | 中等尺寸元素碰撞     |
| `Heavy`    | `'heavy'`  | 大型沉重元素碰撞     |
| `Soft`     | `'soft'`   | 弹性大的元素碰撞     |
| `Rigid`    | `'rigid'`  | 弹性小的元素碰撞     |

#### `NotificationFeedbackType`

| 成员      | 值          | 含义         |
| --------- | ----------- | ------------ |
| `Success` | `'success'` | 任务成功完成 |
| `Warning` | `'warning'` | 任务产生警告 |
| `Error`   | `'error'`   | 任务失败     |

> **未实现的内容**
>
> - `AndroidHaptics`：Android 专属枚举，HarmonyOS 上没有实际用途，配合 `performAndroidHapticsAsync()` 使用也不会产生振动。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
