# @expo-harmony/expo-updates

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-updates) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/updates/)

为 HarmonyOS 上的 React Native 应用提供 Expo Updates 的原生实现，与官方 `expo-updates` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 14（HarmonyOS 5.0.2）。

```bash
npm install @expo-harmony/expo-updates expo-updates@~57.0.26
```

## API 对照表

### Hooks

#### `Updates.useUpdates()`

返回 `UseUpdatesReturnType`。应用检查、下载或准备重载更新时，Hook 会随状态变化更新 `isChecking`、`isDownloading`、`downloadProgress`、`availableUpdate`、`downloadedUpdate`、`checkError` 和 `downloadError` 等字段。HarmonyOS 上下载进度以 `0` 到 `1` 表示；收到回滚指令时，`availableUpdate` 和下载后的 `downloadedUpdate` 会标记为 `ROLLBACK`。`isUpdatePending` 表示是否有已下载、等待重载的更新。

### Constants

#### `Updates.isEnabled`

类型：`boolean`。更新功能是否启用。配置关闭更新、缺少更新服务器地址或运行时版本时为 `false`；开发模式下未将 `updates.useNativeDebug` 设为 `true` 时也为 `false`。更新关闭时仍运行内置资源，检查、下载和额外参数方法会以 `ERR_UPDATES_DISABLED` 拒绝。

#### `Updates.updateId`

类型：`string | null`。当前更新的小写 UUID。更新未启用或没有当前更新 ID 时为 `null`。

#### `Updates.channel`

类型：`string | null`。从 `updates.requestHeaders` 中的 `expo-channel-name` 读取渠道名。HarmonyOS 上未配置该请求头时返回空字符串。

#### `Updates.runtimeVersion`

类型：`string | null`。当前构建配置的运行时版本。更新未启用或未配置时，HarmonyOS 返回空字符串。

#### `Updates.checkAutomatically`

类型：`UpdatesCheckAutomaticallyValue | null`。应用启动时自动检查更新的策略。HarmonyOS 将 `ON_LOAD`、`ON_ERROR_RECOVERY`、`NEVER` 和 `WIFI_ONLY` 分别映射为对应策略；更新未启用时为 `NEVER`。使用 `WIFI_ONLY` 时，设备不是 Wi-Fi 网络或系统无法读取网络状态，就不会进行自动检查。

#### `Updates.localAssets`

类型：`Record<string, string>`。当前更新资源 key 到本地 `file://` 地址的映射；没有可用资源时为空对象。

#### `Updates.isEmergencyLaunch`

类型：`boolean`。当前启动是否因更新初始化或加载失败而回退。发生紧急回退时为 `true`。

#### `Updates.emergencyLaunchReason`

类型：`string | null`。发生紧急回退时的错误信息；没有紧急回退时为 `null`。

#### `Updates.launchDuration`

类型：`number | null`。本次启动准备更新所用的毫秒数。更新未启用时为 `0`。

#### `Updates.isEmbeddedLaunch`

类型：`boolean`。更新启用时，表示当前启动的更新是否为应用包内置更新；HarmonyOS 更新未启用时返回 `false`。

#### `Updates.isUsingEmbeddedAssets`

类型：`boolean`。当前启动 bundle 是否由应用包内置资源提供。

#### `Updates.manifest`

类型：`Partial<Manifest>`。当前运行更新的清单。更新未启用或没有当前清单时为空对象。

#### `Updates.createdAt`

类型：`Date | null`。当前运行更新的创建时间。更新未启用或清单没有创建时间时为 `null`。

### Methods

#### `Updates.checkForUpdateAsync()`

返回 `Promise<UpdateCheckResult>`。向更新服务器检查兼容的新更新，不下载资源。`isAvailable` 为 `true` 时结果包含 `manifest`；没有可用更新时 `reason` 说明服务器无更新或更新未通过选择策略；收到可用的内置更新回滚指令时，`isRollBackToEmbedded` 为 `true`。更新服务器需提供 Expo Updates 协议兼容的 HarmonyOS 更新。请求失败时 Promise 会以对应错误码拒绝。

#### `Updates.fetchUpdateAsync()`

返回 `Promise<UpdateFetchResult>`。检查并下载兼容的更新。下载到新版本时 `isNew` 为 `true` 并包含 `manifest`；服务器没有新更新时 `isNew` 为 `false`；收到回滚指令并成功处理时 `isRollBackToEmbedded` 为 `true`。下载完成后调用 `Updates.reloadAsync()` 可立即应用，否则在下次冷启动时应用。差分下载默认启用，可通过 `updates.enableBsdiffPatchSupport: false` 关闭；HarmonyOS 上补丁校验失败会尝试完整下载。HarmonyOS 不保证支持 Zstandard 压缩的资源响应，更新服务器应提供未压缩、gzip、deflate 或 Brotli 响应。

#### `Updates.reloadAsync(options?)`

返回 `Promise<void>`，使用最近下载的更新重载应用。`options.reloadScreenOptions` 可设置重载画面的背景色、图片、图片缩放方式、加载指示器和淡出效果。HarmonyOS 显示系统重载画面；图片加载失败时改为显示加载指示器。

#### `Updates.getExtraParamsAsync()`

返回 `Promise<Record<string, string>>`，读取当前额外参数。参数会持久保存，并随更新请求发送；更新未启用时以 `ERR_UPDATES_DISABLED` 拒绝。

#### `Updates.setExtraParamAsync(key, value)`

返回 `Promise<void>`。设置一个额外参数；`value` 为 `null` 或 `undefined` 时删除该参数。参数会持久保存，并随更新请求发送。更新未启用时以 `ERR_UPDATES_DISABLED` 拒绝。

#### `Updates.readLogEntriesAsync(maxAge?)`

返回 `Promise<UpdatesLogEntry[]>`，读取更新日志。`maxAge` 以毫秒为单位，默认最近一小时；HarmonyOS 最多保留并返回最近 24 小时的日志。负数或非有限值会以 `ERR_UPDATES_LOGS` 拒绝。

#### `Updates.clearLogEntriesAsync()`

返回 `Promise<void>`，清除本地保存的更新日志。清除失败时以 `ERR_UPDATES_READ_LOGS` 拒绝。

#### `Updates.setUpdateRequestHeadersOverride(requestHeaders)`

同步返回 `void`。运行时覆盖更新请求头；传 `null` 恢复构建时配置。HarmonyOS 只允许覆盖 `updates.requestHeaders` 已声明的请求头名称，不允许覆盖 `Host`；其他名称会以 `ERR_UPDATES_RUNTIME_OVERRIDE` 拒绝。

#### `Updates.setUpdateURLAndRequestHeadersOverride(configOverride)`

同步返回 `void`。运行时覆盖更新服务器地址和请求头；传 `null` 恢复构建时配置。HarmonyOS 要求应用配置 `updates.disableAntiBrickingMeasures: true`，否则以 `ERR_UPDATES_RUNTIME_OVERRIDE` 拒绝。覆盖配置会持久保存。

### Types

#### `Manifest`

更新清单类型，包含远程更新清单和应用包内置清单。`checkForUpdateAsync()` 与 `fetchUpdateAsync()` 在发现或下载新更新时返回该类型。

#### `UpdateCheckResult`

检查更新的结果联合类型，由 `UpdateCheckResultAvailable`、`UpdateCheckResultNotAvailable` 或 `UpdateCheckResultRollBack` 组成。

#### `UpdateCheckResultAvailable`

`isAvailable` 为 `true`，`manifest` 为可用更新的清单，`isRollBackToEmbedded` 为 `false`。

#### `UpdateCheckResultNotAvailable`

`isAvailable` 和 `isRollBackToEmbedded` 均为 `false`，`manifest` 为 `undefined`，`reason` 为 `UpdateCheckResultNotAvailableReason`。

#### `UpdateCheckResultRollBack`

收到回滚到内置更新的指令时返回。`isRollBackToEmbedded` 为 `true`，`isAvailable` 为 `false`，`manifest` 和 `reason` 为 `undefined`。

#### `UpdateFetchResult`

下载更新的结果联合类型，由 `UpdateFetchResultSuccess`、`UpdateFetchResultFailure` 或 `UpdateFetchResultRollBackToEmbedded` 组成。

#### `UpdateFetchResultSuccess`

下载到新更新时返回：`isNew` 为 `true`、`manifest` 包含更新清单、`isRollBackToEmbedded` 为 `false`。

#### `UpdateFetchResultFailure`

没有下载到新更新时返回：`isNew` 和 `isRollBackToEmbedded` 均为 `false`，`manifest` 为 `undefined`。

#### `UpdateFetchResultRollBackToEmbedded`

下载处理得到内置更新回滚时返回：`isNew` 为 `false`、`isRollBackToEmbedded` 为 `true`，`manifest` 为 `undefined`。

#### `UpdatesLogEntry`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `timestamp` | `number` | 日志时间，Unix 纪元起的毫秒数。 |
| `message` | `string` | 日志内容。 |
| `code` | `UpdatesLogEntryCode` | 日志代码。 |
| `level` | `UpdatesLogEntryLevel` | 日志级别。 |
| `updateId` | `string?` | 关联的更新 ID。 |
| `assetId` | `string?` | 关联的资源 ID 或 key。 |
| `stacktrace` | `string[]?` | 错误日志的堆栈；最多包含 20 项。 |

#### `LocalAssets`

类型：`Record<string, string>`。资源 key 到 HarmonyOS 本地 `file://` 地址的映射。

#### `ReloadScreenOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `backgroundColor` | `string?` | 背景颜色，默认白色。 |
| `image` | `string \| number \| ReloadScreenImageSource?` | 重载画面图片。 |
| `imageResizeMode` | `'contain' \| 'cover' \| 'center' \| 'stretch'?` | 图片缩放方式，默认 `contain`。 |
| `imageFullScreen` | `boolean?` | 图片是否铺满屏幕，默认 `false`。 |
| `fade` | `boolean?` | 隐藏画面时是否淡出，默认 `false`。 |
| `spinner` | `object?` | 加载指示器选项，包含 `enabled`、`color` 和 `size`（`small`、`medium`、`large`）。未传图片时默认显示指示器。 |

#### `ReloadScreenImageSource`

图片来源对象。`url` 为图片地址；`width`、`height` 和 `scale` 可选，用于确定非全屏图片的显示尺寸。

#### `CurrentlyRunningInfo`

`useUpdates()` 返回的当前运行信息，包含 `updateId`、`channel`、`createdAt`、`isEmbeddedLaunch`、`isEmergencyLaunch`、`emergencyLaunchReason`、`launchDuration`、`manifest` 和 `runtimeVersion`。HarmonyOS 上未设置的可选值为 `undefined`。

#### `UpdateInfo`

当前可用或已下载更新的信息联合类型，由 `UpdateInfoNew` 或 `UpdateInfoRollback` 组成。

#### `UpdateInfoNew`

新更新的信息，包含 `type: UpdateInfoType.NEW`、`updateId`、`createdAt` 和 `manifest`。

#### `UpdateInfoRollback`

回滚到内置更新的信息，包含 `type: UpdateInfoType.ROLLBACK` 和回滚时间 `createdAt`；`updateId` 和 `manifest` 为 `undefined`。

#### `UseUpdatesReturnType`

`useUpdates()` 的返回类型，包含当前运行信息、更新可用或待重载状态、检查与下载状态、下载进度、最近检查时间、错误，以及 `availableUpdate` 和 `downloadedUpdate`。

### Enums

#### `UpdatesCheckAutomaticallyValue`

| 成员 | 值 | 说明 |
| --- | --- | --- |
| `ON_LOAD` | `'ON_LOAD'` | 启动时检查更新。 |
| `ON_ERROR_RECOVERY` | `'ON_ERROR_RECOVERY'` | 错误恢复启动时检查更新。 |
| `WIFI_ONLY` | `'WIFI_ONLY'` | 仅在 Wi-Fi 网络下自动检查更新。 |
| `NEVER` | `'NEVER'` | 不自动检查更新。 |

#### `UpdateCheckResultNotAvailableReason`

| 成员 | 值 | 说明 |
| --- | --- | --- |
| `NO_UPDATE_AVAILABLE_ON_SERVER` | `'noUpdateAvailableOnServer'` | 服务器没有可用更新或回滚指令。 |
| `UPDATE_REJECTED_BY_SELECTION_POLICY` | `'updateRejectedBySelectionPolicy'` | 更新不适用于当前运行时或未通过更新选择策略。 |
| `UPDATE_PREVIOUSLY_FAILED` | `'updatePreviouslyFailed'` | 此设备上的更新此前启动失败。 |
| `ROLLBACK_REJECTED_BY_SELECTION_POLICY` | `'rollbackRejectedBySelectionPolicy'` | 回滚指令未通过更新选择策略。 |
| `ROLLBACK_NO_EMBEDDED` | `'rollbackNoEmbeddedConfiguration'` | 应用没有可回滚的内置更新。 |

#### `UpdatesLogEntryCode`

| 成员 | 值 |
| --- | --- |
| `NONE` | `'None'` |
| `NO_UPDATES_AVAILABLE` | `'NoUpdatesAvailable'` |
| `UPDATE_ASSETS_NOT_AVAILABLE` | `'UpdateAssetsNotAvailable'` |
| `UPDATE_SERVER_UNREACHABLE` | `'UpdateServerUnreachable'` |
| `UPDATE_HAS_INVALID_SIGNATURE` | `'UpdateHasInvalidSignature'` |
| `UPDATE_CODE_SIGNING_ERROR` | `'UpdateCodeSigningError'` |
| `UPDATE_FAILED_TO_LOAD` | `'UpdateFailedToLoad'` |
| `ASSETS_FAILED_TO_LOAD` | `'AssetsFailedToLoad'` |
| `JS_RUNTIME_ERROR` | `'JSRuntimeError'` |
| `INITIALIZATION_ERROR` | `'InitializationError'` |
| `UNKNOWN` | `'Unknown'` |

#### `UpdatesLogEntryLevel`

| 成员 | 值 |
| --- | --- |
| `TRACE` | `'trace'` |
| `DEBUG` | `'debug'` |
| `INFO` | `'info'` |
| `WARN` | `'warn'` |
| `ERROR` | `'error'` |
| `FATAL` | `'fatal'` |

#### `UpdateInfoType`

| 成员 | 值 | 说明 |
| --- | --- | --- |
| `NEW` | `'new'` | 可下载并启动的新更新。 |
| `ROLLBACK` | `'rollback'` | 回滚到应用包内置更新。 |

### Error codes

#### `ERR_UPDATES_DISABLED`

更新功能未启用时调用检查、下载、读取额外参数或设置额外参数，或尝试覆盖更新配置。

#### `ERR_UPDATES_RELOAD`

无法使用当前更新重载应用。

#### `ERR_UPDATES_CHECK`

检查更新遇到未归类的错误。传输、协议、清单或签名错误可能返回相应的具体错误码。

#### `ERR_UPDATES_FETCH`

下载更新遇到未归类的错误。资源、校验或签名错误可能返回相应的具体错误码。

#### `ERR_UPDATES_READ_LOGS`

读取或清除本地更新日志失败。

#### `ERR_UPDATES_LOGS`

`readLogEntriesAsync(maxAge)` 的 `maxAge` 为负数或非有限值。

#### `ERR_UPDATES_RUNTIME_OVERRIDE`

更新服务器地址覆盖未启用，或请求头覆盖了构建配置未声明的名称或 `Host`。

#### `ERR_UPDATES_ARGUMENT`

重载画面的颜色、图片、尺寸、缩放方式或加载指示器参数无效。

#### `ERR_UPDATES_RELOAD_SCREEN`

HarmonyOS 无法显示原生重载画面。

#### `ERR_UPDATES_HTTP`

更新服务器或资源服务器返回非成功 HTTP 状态码。

#### `ERR_UPDATES_PROTOCOL`

服务器返回的 Expo Updates 协议版本不受支持。

#### `ERR_UPDATES_MANIFEST`

更新清单或资源描述无效，或与 HarmonyOS 所需的资源结构不兼容。

#### `ERR_UPDATES_DIRECTIVE`

服务器返回的回滚指令无效。

#### `ERR_UPDATES_CODE_SIGNING`

清单或更新响应的签名校验失败。

#### `ERR_UPDATES_ASSET`

更新资源无法读取、写入或处理。

#### `ERR_UPDATES_ASSET_HASH`

更新资源的 SHA-256 校验值不匹配。

#### `ERR_UPDATES_PATCH`

HarmonyOS 无法应用差分更新，且完整下载重试仍返回差分资源。

#### `ERR_UPDATES_CONFIGURATION`

更新服务器地址、请求头或运行时覆盖配置无效。

#### `ERR_UPDATES_DATABASE`

更新存储无法打开、迁移或通过完整性检查。

### Permissions

#### HarmonyOS 网络权限

更新检查和下载需要网络访问，`WIFI_ONLY` 策略需要读取网络连接类型。本包声明 `ohos.permission.INTERNET` 和 `ohos.permission.GET_NETWORK_INFO`；应用无需另外申请运行时权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
