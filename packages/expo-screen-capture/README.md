# @expo-harmony/expo-screen-capture

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-screen-capture) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/screen-capture/)

为 HarmonyOS 上的 React Native 应用提供 Expo ScreenCapture 的原生实现，与官方 `expo-screen-capture` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-screen-capture expo-screen-capture@~57.0.4
```

## API 对照表

### Hooks

#### `usePermissions(options?)`

返回 `[PermissionResponse | null, requestPermission, getPermission]`。HarmonyOS 上截图监听不需要运行时授权，权限状态始终为已授权。

#### `usePreventScreenCapture(key?)`

组件挂载期间阻止当前应用窗口被截屏或录屏，卸载时解除保护。`key` 默认为 `'default'`，用于区分多个保护调用；只有对应的保护都解除后，窗口才恢复可截屏和录屏。

#### `useScreenshotListener(listener)`

组件挂载期间监听截图，卸载时移除监听。回调不接收参数。

### Methods

#### `isAvailableAsync()`

返回 `Promise<boolean>`，HarmonyOS 上始终为 `true`。

#### `preventScreenCaptureAsync(key?)`

启用当前应用窗口的隐私模式，返回 `Promise<void>`。默认 `key` 为 `'default'`；每个 `key` 对应一项保护。保护期间，窗口内容不能被截屏或录屏，应用退到后台时多任务预览由系统遮罩或模糊处理。最后一项保护解除前，窗口保持受保护状态。若宿主已启用隐私模式，本包不会在解除保护时关闭该模式。

#### `allowScreenCaptureAsync(key?)`

释放对应 `key` 的保护，返回 `Promise<void>`。默认 `key` 为 `'default'`；释放最后一项保护后，窗口恢复可截屏和录屏。释放失败时 Promise 以 `ERR_SCREEN_CAPTURE_RELEASE` 拒绝，可以再次调用重试。

#### `enableAppSwitcherProtectionAsync(blurIntensity?)`

- HarmonyOS 不提供应用切换器模糊保护，调用会抛出 `UnavailabilityError`。

#### `disableAppSwitcherProtectionAsync()`

- HarmonyOS 不提供应用切换器模糊保护，调用会抛出 `UnavailabilityError`。

### Event subscriptions

#### `addScreenshotListener(listener)`

返回 `Subscription`。应用处于前台且存在监听时，检测到截图会调用 `listener`；回调不接收参数。HarmonyOS API 20 及以上会在系统完成控制中心或快捷键截屏，以及滚动截屏结束时触发。API 13–19 会在控制中心或整屏截屏后触发。回调表示系统检测到截图，不表示图片已成功保存，也不提供图片或文件路径。没有录屏开始或结束事件。

#### `removeScreenshotListener(subscription)`

移除指定的截图监听。此方法已弃用，请改用 `subscription.remove()`。

### Types

#### `PermissionHookOptions`

作为 `usePermissions(options)` 的选项，可设置 `get` 和 `request`，分别控制是否在组件挂载时查询或请求权限。

#### `PermissionResponse`

| 属性 | 类型 | HarmonyOS 返回值 |
| --- | --- | --- |
| `status` | `PermissionStatus` | `'granted'` |
| `granted` | `boolean` | `true` |
| `canAskAgain` | `boolean` | `true` |
| `expires` | `PermissionExpiration` | `'never'` |

#### `Subscription`

`addScreenshotListener(listener)` 返回的监听订阅对象。调用 `subscription.remove()` 可移除监听。

### Enums

#### `PermissionStatus`

`GRANTED`、`DENIED` 和 `UNDETERMINED` 分别表示已授权、已拒绝和未确定。HarmonyOS 上权限状态始终为 `GRANTED`。

### Error codes

#### `ERR_SCREEN_CAPTURE_WINDOW`

没有可用的应用窗口时，启用截屏保护会失败。

#### `ERR_SCREEN_CAPTURE_DESTROYED`

应用运行环境已销毁后调用截屏保护方法时失败。

#### `ERR_SCREEN_CAPTURE_RELEASE`

解除窗口隐私模式失败时抛出；可以重试 `allowScreenCaptureAsync()`。

### Permissions

#### `getPermissionsAsync()`

返回 `Promise<PermissionResponse>`，结果始终表示已授权。

#### `requestPermissionsAsync()`

返回 `Promise<PermissionResponse>`，结果始终表示已授权，不会弹出授权对话框。

#### `ohos.permission.PRIVACY_WINDOW`

用于开启窗口隐私模式。系统在应用安装时授予此权限，不会弹出授权对话框。截图监听不需要相册、存储或其他运行时权限。[HarmonyOS 权限说明](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/permissions-for-all/)

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors)

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
