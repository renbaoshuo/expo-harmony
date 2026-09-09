# @expo-harmony/expo-intent-launcher

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-intent-launcher) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/intent-launcher/)

为 HarmonyOS 上的 React Native 应用提供 Expo IntentLauncher 的原生实现，与官方同版本的 `expo-intent-launcher` 配套使用。支持启动 UIAbility 并等待结果、打开应用入口和读取应用图标。

## 安装

```bash
npm install @expo-harmony/expo-intent-launcher expo-intent-launcher@55.0.12
```

鸿蒙适配会通过 Autolinking 自动接入，无需额外配置。最低支持 HarmonyOS 5.0.2（API 14），宿主的 `compatibleSdkVersion` 也需满足此要求。

业务代码依旧使用官方包：

```ts
import * as IntentLauncher from 'expo-intent-launcher';

const result = await IntentLauncher.startActivityAsync('com.example.action.EDIT', {
  packageName: 'com.example.target',
  className: 'EditorAbility',
  type: 'text/plain',
  extra: { text: 'Hello' },
});
```

## API 对照表

### Methods

#### `IntentLauncher.startActivityAsync(activityAction, params?)`

返回 `Promise<IntentLauncherResult>`，启动目标 UIAbility 并等待结果。`activityAction` 必须是非空字符串，传入空值或非字符串时抛出 `TypeError`。

`className` 对应 UIAbility 名称，`packageName` 对应 bundleName，只在指定 `className` 时使用 `packageName`，省略则使用当前应用。`data`、`category`、`extra` 分别对应 Want 的 `uri`、`entities` 和 `parameters`，`type` 和 `flags` 原样传给 Want。action、category、flags 和 URI 必须遵循目标 HarmonyOS 应用的协议。

目标 Ability 必须主动返回结果，仅返回调用方前台或把目标转入后台不会完成 Promise。需要支持返回键取消时，应由目标页面调用 `terminateSelfWithResult`。结果码、结果 Want 的 URI 和参数原样透传，分别放入 `resultCode`、`data` 和 `extra`；系统未显式设置时 `data` 和 `extra` 可能缺失，也可能为空字符串或空对象。

等待结果期间再次启动会被拒绝，抛出 `E_ACTIVITY_ALREADY_STARTED`，启动失败后可以重试。无法启动目标 Ability 时抛出 `ERR_INTENT_LAUNCHER_START_ACTIVITY`，例如目标应用不存在、Ability 未导出或未启用。启动其他应用仍受系统规则限制。

#### `IntentLauncher.openApplication(packageName)`

无返回值，查找目标应用启用、导出的桌面入口并启动，`packageName` 对应 bundleName。同步返回，系统异步报告的启动失败只能记录到原生日志。目标应用不存在或没有启用、导出的桌面入口时抛出 `ERR_PACKAGE_NOT_FOUND`，查询失败时抛出 `ERR_INTENT_LAUNCHER_BUNDLE_INFO`，调用启动接口失败时抛出 `ERR_INTENT_LAUNCHER_OPEN_APPLICATION`。查询自身包信息无需额外权限，查询其他应用受系统包信息查询权限与可见性限制。

#### `IntentLauncher.getApplicationIconAsync(packageName)`

返回 `Promise<string>`，目标应用的 PNG 图标，带 `data:image/png;base64,` 前缀，可直接用作图片源。图标读取或编码失败时返回空字符串。目标应用不存在时抛出 `ERR_PACKAGE_NOT_FOUND`，查询失败时抛出 `ERR_INTENT_LAUNCHER_BUNDLE_INFO`。

### Interfaces

#### `IntentLauncherParams`

| 属性          | 类型                   | 说明                                                                                         |
| ------------- | ---------------------- | -------------------------------------------------------------------------------------------- |
| `className`   | `string?`              | 目标 UIAbility 名称，对应 Want 的 `abilityName`。                                            |
| `packageName` | `string?`              | 目标应用 bundleName，对应 Want 的 `bundleName`。只在指定 `className` 时生效，省略时用当前应用的 bundleName。 |
| `data`        | `string?`              | 目标 URI，对应 Want 的 `uri`。                                                               |
| `type`        | `string?`              | MIME 类型，对应 Want 的 `type`。                                                             |
| `category`    | `string?`              | 类别，对应 Want 的 `entities`，只取一个值。                                                  |
| `extra`       | `Record<string, any>?` | 附加参数，对应 Want 的 `parameters`。顶层数值会截断为整数。                                  |
| `flags`       | `number?`              | 标志位，对应 Want 的 `flags`，按 32 位整数截断。                                             |

#### `IntentLauncherResult`

| 属性         | 类型         | 说明                                  |
| ------------ | ------------ | ------------------------------------- |
| `resultCode` | `ResultCode` | 目标 Ability 返回的结果码，原样透传。 |
| `data`       | `string?`    | 结果 Want 的 URI，未设置时不返回。    |
| `extra`      | `object?`    | 结果 Want 的参数，未设置时不返回。    |

### Enums

#### `ResultCode`

| 成员        | 值   |
| ----------- | ---- |
| `Success`   | `-1` |
| `Canceled`  | `0`  |
| `FirstUser` | `1`  |

取值来自 Android，HarmonyOS 上 `resultCode` 由目标 Ability 决定，不做映射，这些成员不能用于判断结果状态。

> **未实现的内容**
>
> - `ActivityAction`：Android 专属枚举，取值是 Android Settings 的 action，HarmonyOS 上没有对应常量。

### Error codes

#### `E_ACTIVITY_ALREADY_STARTED`

等待结果期间再次调用 `startActivityAsync()` 时抛出。

#### `ERR_INTENT_LAUNCHER_START_ACTIVITY`

`startActivityAsync()` 无法启动目标 Ability 时抛出。

#### `ERR_PACKAGE_NOT_FOUND`

目标应用不存在，或应用没有启用、导出的桌面入口时抛出。

#### `ERR_INTENT_LAUNCHER_BUNDLE_INFO`

查询应用信息失败时抛出，例如没有查询其他应用的权限。

#### `ERR_INTENT_LAUNCHER_OPEN_APPLICATION`

`openApplication()` 调用启动接口失败时抛出。

#### `ERR_INTENT_LAUNCHER_DESTROYED`

启动等待期间宿主被销毁时抛出。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
