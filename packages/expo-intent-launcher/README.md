# @expo-harmony/expo-intent-launcher

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-intent-launcher) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/intent-launcher/)

为 HarmonyOS 上的 React Native 应用提供 Expo Intent Launcher 的原生实现，与官方同版本的 `expo-intent-launcher` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 14（HarmonyOS 5.0.2）。

```bash
npm install @expo-harmony/expo-intent-launcher expo-intent-launcher
```

## API 对照表

### Methods

#### `IntentLauncher.startActivityAsync(activityAction, params?)`

`activityAction` 是非空的 HarmonyOS Want action 字符串；空字符串或非字符串会抛出 `TypeError`。`params` 可省略，返回 `Promise<IntentLauncherResult>`，启动目标 UIAbility 并等待它返回结果。应用切换前后台时 Promise 会继续等待；目标 UIAbility 可以结束自身并返回结果，也可以返回结果后继续运行。

`className` 指定目标 UIAbility 名称。指定 `className` 时，`packageName` 指定目标应用的 bundleName；省略 `packageName` 时使用当前应用。未指定 `className` 时，`packageName` 不生效。`data`、`type`、`category` 和 `extra` 分别对应 Want 的 URI、MIME 类型、单个实体和附加参数；URI 与 MIME 类型可以同时指定。action、实体、URI 和 `flags` 需符合目标应用支持的 HarmonyOS Want 约定。若要临时授予目标 Ability 读取文件 URI 的权限，可传入相应的 Want 标志，例如 `FLAG_AUTH_READ_URI_PERMISSION`（`0x00000001`）。[HarmonyOS Want Flags 参考](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-app-ability-wantconstant/#flags)

`extra` 只支持 HarmonyOS Want 可传递的类型，函数不能作为参数跨 Ability 传递。顶层数值会向零取整并限制在系统支持的 64 位整数范围内；嵌套对象和数组中的数值不取整。超出 JavaScript 安全整数范围的值不能保证精确表示。`flags` 会向零取整并限制在 32 位整数范围内。[HarmonyOS Want 参考](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-app-ability-want/)

返回对象中的 `resultCode` 由目标 UIAbility 决定，并按 HarmonyOS 返回值原样传回；系统未设置结果 URI 或附加参数时，`data` 或 `extra` 可能省略。请按目标应用的协议解释结果码。[HarmonyOS UIAbilityContext 参考](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-inner-application-uiabilitycontext/)

等待结果期间再次启动会以 `E_ACTIVITY_ALREADY_STARTED` 拒绝。无法启动目标 UIAbility 时以 `ERR_INTENT_LAUNCHER_START_ACTIVITY` 拒绝。

#### `IntentLauncher.openApplication(packageName)`

`packageName` 是目标应用的 bundleName。方法返回 `void`，同步发起启动而不等待目标应用完成启动。API 24 及以上使用系统提供的目标应用启动入口；API 14–23 要求目标应用具有已启用、已导出的桌面入口 UIAbility。目标应用不存在或没有符合条件的入口时抛出 `ERR_PACKAGE_NOT_FOUND`。查询应用信息失败时抛出 `ERR_INTENT_LAUNCHER_BUNDLE_INFO`；启动时发生同步错误则抛出 `ERR_INTENT_LAUNCHER_OPEN_APPLICATION`。

打开本应用无需查询应用信息的权限；打开其他应用需要下文所列的应用信息查询权限。

#### `IntentLauncher.getApplicationIconAsync(packageName)`

`packageName` 是目标应用的 bundleName。返回 `Promise<string>`：成功时为带 `data:image/png;base64,` 前缀的 PNG 图标，可直接作为图片源；图标读取或编码失败时返回空字符串。读取本应用图标无需查询应用信息的权限，读取其他应用图标需要下文所列的应用信息查询权限。目标应用不存在时以 `ERR_PACKAGE_NOT_FOUND` 拒绝；查询应用信息失败时以 `ERR_INTENT_LAUNCHER_BUNDLE_INFO` 拒绝。

### Types

#### `IntentLauncherParams`

| 属性 | 类型 | HarmonyOS 行为 |
| --- | --- | --- |
| `className` | `string?` | 目标 UIAbility 名称，对应 Want 的 `abilityName`。 |
| `packageName` | `string?` | 目标 bundleName；仅在指定 `className` 时生效，省略时使用当前应用的 bundleName。 |
| `data` | `string?` | Want URI。 |
| `type` | `string?` | Want MIME 类型，可与 `data` 同时指定。 |
| `category` | `string?` | 单个 Want entity。 |
| `extra` | `Record<string, any>?` | Want 附加参数；顶层数值向零取整并限制在系统支持的 64 位整数范围内。 |
| `flags` | `number?` | Want 标志位；向零取整并限制在 32 位整数范围内。 |

#### `IntentLauncherResult`

| 属性 | 类型 | HarmonyOS 行为 |
| --- | --- | --- |
| `resultCode` | `ResultCode` | 目标 UIAbility 返回的结果码，按系统返回值原样传回。 |
| `data` | `string?` | 结果 Want 中的 URI；未设置时可能省略。 |
| `extra` | `object?` | 结果 Want 中的附加参数；未设置时可能省略。 |

### Enums

#### `ActivityAction`

- 预定义设置操作在 HarmonyOS 上没有对应 action；请传入目标应用支持的 HarmonyOS action 字符串。

#### `ResultCode`

| 成员 | 值 |
| --- | --- |
| `Success` | `-1` |
| `Canceled` | `0` |
| `FirstUser` | `1` |

- 返回码由目标 UIAbility 决定；这些枚举成员不对应 HarmonyOS 上的固定结果状态。

### Error codes

#### `E_ACTIVITY_ALREADY_STARTED`

前一次 `startActivityAsync()` 仍在等待结果时再次调用而抛出。

#### `ERR_INTENT_LAUNCHER_START_ACTIVITY`

HarmonyOS 无法启动目标 UIAbility 时抛出。

#### `ERR_PACKAGE_NOT_FOUND`

目标应用不存在，或没有符合要求的已启用、已导出的桌面入口 UIAbility 时抛出。

#### `ERR_INTENT_LAUNCHER_BUNDLE_INFO`

查询目标应用信息失败时抛出，例如读取其他应用信息时未获所需权限。

#### `ERR_INTENT_LAUNCHER_OPEN_APPLICATION`

`openApplication()` 发起启动时发生同步错误而抛出。

#### `ERR_INTENT_LAUNCHER_DESTROYED`

等待启动结果期间宿主被销毁，或宿主销毁后调用 API 时抛出。

### Permissions

#### `ohos.permission.GET_BUNDLE_INFO_PRIVILEGED`

查询其他应用的启动入口或读取其他应用图标时需要此权限。查询或读取本应用信息不需要此权限。此权限面向符合条件的企业应用开放，须按[华为申请说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/permissions-for-enterprise-apps#ohospermissionget_bundle_info_privileged)申请。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
