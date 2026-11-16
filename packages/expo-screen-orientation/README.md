# @expo-harmony/expo-screen-orientation

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-screen-orientation) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/screen-orientation/)

为 HarmonyOS 上的 React Native 应用提供 Expo ScreenOrientation 的原生实现，与官方 `expo-screen-orientation` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-screen-orientation expo-screen-orientation@~57.0.3
```

## API 对照表

### Methods

- `lockAsync(orientationLock: OrientationLock): Promise<void>`：设置当前窗口的方向策略。`DEFAULT` 使用系统默认策略；`ALL`、`PORTRAIT`、`LANDSCAPE` 分别允许所有方向、纵向或横向自动旋转；`PORTRAIT_UP`、`PORTRAIT_DOWN`、`LANDSCAPE_LEFT`、`LANDSCAPE_RIGHT` 固定到对应方向。传入 `OTHER` 时不改变当前策略；传入 `UNKNOWN` 时以 `ERR_SCREEN_ORIENTATION_INVALID_LOCK` 拒绝。
- `unlockAsync(): Promise<void>`：将方向策略恢复为 `DEFAULT`。
- `getOrientationAsync(): Promise<Orientation>`：读取当前方向。HarmonyOS SDK API 23 及以上且支持窗口方向转换时按窗口方向解析；无法转换或使用较低版本时按窗口所在显示器的方向解析。窗口尺寸无效或显示器暂不可用时返回 `Orientation.UNKNOWN`。
- `getOrientationLockAsync(): Promise<OrientationLock>`：读取当前窗口策略；当前策略无法映射到 `OrientationLock` 时返回 `OrientationLock.OTHER`。
- `getPlatformOrientationLockAsync(): Promise<HarmonyPlatformOrientationInfo>`：返回包含 `screenOrientationConstantHarmony` 的对象，值为当前的 HarmonyOS [`window.Orientation`](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-window-e/) 数值。
- `lockPlatformAsync(options: HarmonyPlatformOrientationInfo): Promise<void>`：通过 `screenOrientationConstantHarmony` 指定 HarmonyOS `window.Orientation` 数值，包括 `0`（`UNSPECIFIED`）。
- `supportsOrientationLockAsync(orientationLock: OrientationLock): Promise<boolean>`：检查策略和设备的窗口旋转能力。`OTHER`、`UNKNOWN`、二合一设备及缺少窗口管理能力的设备返回 `false`。分屏、自由窗口等场景由系统决定何时应用策略。

### Event subscriptions

- `addOrientationChangeListener(listener: OrientationChangeListener): Subscription`：订阅当前窗口的显示方向变化，包含系统报告的 180° 转向。回调接收 `orientationLock` 和 `orientationInfo`。返回的订阅可调用 `subscription.remove()` 移除。
- `removeOrientationChangeListener(subscription: Subscription): void`：移除指定订阅；此方法已弃用，建议调用 `subscription.remove()`。
- `removeOrientationChangeListeners(): void`：移除所有方向变化订阅；此方法已弃用。

### Types

- `HarmonyPlatformOrientationInfo`：可从 `@expo-harmony/expo-screen-orientation` 导入的类型，补充 `screenOrientationConstantHarmony` 字段。
- `ScreenOrientationInfo`：包含当前 `orientation`；HarmonyOS 不提供尺寸等级字段。
- `OrientationChangeEvent`：包含当前的 `orientationLock` 和 `orientationInfo`。
- `OrientationChangeListener`：类型为 `(event: OrientationChangeEvent) => void`。
- `Subscription`：方向变化监听的订阅类型，可调用 `remove()` 取消订阅。

### Enums

- `Orientation`：`UNKNOWN = 0`、`PORTRAIT_UP = 1`、`PORTRAIT_DOWN = 2`、`LANDSCAPE_LEFT = 3`、`LANDSCAPE_RIGHT = 4`。
- `OrientationLock`：可应用的策略为 `DEFAULT = 0`、`ALL = 1`、`PORTRAIT = 2`、`PORTRAIT_UP = 3`、`PORTRAIT_DOWN = 4`、`LANDSCAPE = 5`、`LANDSCAPE_LEFT = 6`、`LANDSCAPE_RIGHT = 7`。`OTHER = 8` 表示当前策略无法映射到这些值；`UNKNOWN = 9` 不是可应用的策略。

未实现项：

- `SizeClassIOS`：HarmonyOS 不提供尺寸等级数据。
- `WebOrientation` 和 `WebOrientationLock`：HarmonyOS 不提供这些方向枚举对应的窗口方向值。

### Error codes

- `ERR_SCREEN_ORIENTATION_INVALID_LOCK`：传入 `OrientationLock.UNKNOWN`。
- `ERR_SCREEN_ORIENTATION_INVALID_PLATFORM_LOCK`：所传 HarmonyOS 方向数值无效或不可用。
- `ERR_SCREEN_ORIENTATION_UNSUPPORTED_LOCK`：当前设备不支持方向锁定。
- `ERR_SCREEN_ORIENTATION_WINDOW`：当前没有可用的 UIAbility 窗口。
- `ERR_SCREEN_ORIENTATION_DESTROYED`：方向模块运行环境已销毁。
- `ERR_SCREEN_ORIENTATION_CONVERSION`：HarmonyOS 无法转换当前窗口方向信息。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors)

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
