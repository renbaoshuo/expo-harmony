# @expo-harmony/expo-updates-interface

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-updates-interface)

为 HarmonyOS 上的 React Native 应用提供 Expo Updates 状态接口的原生实现，与官方同版本的 `expo-updates-interface` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-updates-interface
```

## API 对照表

### Methods

#### `UpdatesControllerRegistry.requestDevelopmentLauncherInitialization(bundleName)`

登记 `bundleName` 对应应用包的开发启动器初始化请求。返回 `void`。

#### `UpdatesControllerRegistry.isDevelopmentLauncherInitializationRequested(bundleName)`

查询 `bundleName` 对应应用包是否有待处理的开发启动器初始化请求。返回 `boolean`。

#### `UpdatesControllerRegistry.completeDevelopmentLauncherInitialization(bundleName)`

完成 `bundleName` 对应应用包的开发启动器初始化请求。返回 `void`。

#### `UpdatesDevLauncherInterface.reset()`

清除当前选中的开发更新。返回 `void`。

#### `UpdatesDevLauncherInterface.isValidUpdatesConfiguration(configuration)`

检查 `configuration: Record<string, ESObject>` 是否可用于获取开发更新。返回 `boolean`。

#### `UpdatesDevLauncherInterface.fetchUpdateWithConfiguration(configuration, callback, deferActivation?)`

按 `configuration: Record<string, ESObject>` 获取开发更新，通过 `callback: UpdatesDevLauncherCallback` 报告清单、进度和结果。`deferActivation` 默认为 `false`；设为 `true` 时，收到成功结果后可调用其 `activate()` 确认选用该更新。返回 `void`。

### Event subscriptions

#### `UpdatesInterface.subscribeToUpdatesStateChanges(listener)`

订阅更新状态变化，`listener` 类型为 `UpdatesStateChangeListener`。返回 `UpdatesStateChangeSubscription`。只有活动的更新控制器会发送状态事件；控制器未活动时不会发送事件，订阅的 `getContext()` 返回 `null`。

#### `UpdatesStateChangeListener.updatesStateDidChange(event)`

更新状态变化时调用。`event` 类型为 `Record<string, ESObject>`，包含本次事件的数据。返回 `void`。

#### `UpdatesStateChangeSubscription.remove()`

取消订阅，之后不再收到状态事件。返回 `void`；重复调用无副作用。

#### `UpdatesStateChangeSubscription.getContext()`

读取当前状态快照，返回 `UpdatesNativeInterfaceStateContext | null`。快照时间字段为 `Date`；控制器未活动时返回 `null`。

### Types

#### `UpdatesControllerRegistry`

`controller` 是可读写属性，类型为 `UpdatesInterface | undefined`。读取当前控制器；没有可用控制器时为 `undefined`。可将实现 `UpdatesInterface` 的控制器设为当前控制器。

#### `UpdatesInterface`

更新控制器提供的属性如下：

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `isEnabled` | `boolean` | 更新功能是否启用。 |
| `runtimeVersion` | `string \| null` | 当前更新配置的运行时版本；无可用配置时为 `null`。 |
| `updateUrl` | `string \| null` | 当前更新配置的服务地址；无可用配置时为 `null`。HarmonyOS 上以字符串表示。 |
| `requestHeaders` | `Record<string, string> \| null` | 当前配置的请求头副本；无可用配置时为 `null`。 |
| `launchedUpdateId` | `string \| null` | 当前运行更新的 ID；没有时为 `null`。 |
| `embeddedUpdateId` | `string \| null` | 随应用打包的更新 ID；没有时为 `null`。 |
| `launchAssetPath` | `string \| null` | 当前更新启动资源在本机上的路径；没有时为 `null`。 |

#### `UpdatesDevLauncherInterface`

开发启动器控制器在 `UpdatesInterface` 基础上提供以下属性：

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `configuredUpdateUrl` | `string \| null \| undefined` | 应用打包时配置的更新服务地址；不可用时为 `null`，实现也可省略此属性。 |
| `updatesInterfaceCallbacks` | `UpdatesInterfaceCallbacks \| undefined` | 接收开发启动器重载请求的回调；未设置时为 `undefined`。 |

#### `UpdatesInterfaceCallbacks`

宿主重载回调：

| 方法 | 说明 |
| --- | --- |
| `onRequestRelaunch()` | 开发启动器请求重载应用时调用。返回 `void`。 |

#### `UpdatesDevLauncherCallback`

开发更新获取过程的回调：

| 方法 | 参数及返回值 | 说明 |
| --- | --- | --- |
| `onManifestLoaded(manifest)` | `manifest: Record<string, ESObject>`；返回 `boolean` | 清单加载后调用。返回 `false` 会中止该更新，随后 `onSuccess` 收到 `null`。 |
| `onProgress(successful, failed, total)` | 三个参数均为 `number`；返回 `void` | 报告成功、失败和总资源数。 |
| `onSuccess(update)` | `update: UpdatesDevLauncherResult \| null`；返回 `void` | 更新获取结束；没有可用更新或清单回调中止下载时，`update` 为 `null`。 |
| `onFailure(error)` | `error: Error \| null`；返回 `void` | 更新获取失败时调用。 |

#### `UpdatesDevLauncherResult`

开发更新获取成功后的结果：

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `manifest` | `Record<string, ESObject>` | 更新清单。 |
| `launchAssetPath` | `string` | 启动资源在本机上的路径。 |
| `activate` | `(() => void) \| undefined` | `deferActivation` 为 `true` 时用于选用该更新；最多调用一次。重置或选用另一更新后，该回调失效。 |

#### `UpdatesNativeInterfaceStateContext`

由 `UpdatesStateChangeSubscription.getContext()` 返回的状态快照：

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `isUpdateAvailable` | `boolean` | 是否有可用更新。 |
| `isUpdatePending` | `boolean` | 是否有已下载并等待重载生效的更新。 |
| `isChecking` | `boolean` | 是否正在检查更新。 |
| `isDownloading` | `boolean` | 是否正在下载更新。 |
| `isRestarting` | `boolean` | 应用是否正在重载。 |
| `restartCount` | `number` | 本次会话内重载次数。 |
| `latestManifest` | `Record<string, ESObject> \| null` | 最近一次获取的更新清单；没有时为 `null`。 |
| `downloadedManifest` | `Record<string, ESObject> \| null` | 已下载更新的清单；没有时为 `null`。 |
| `rollback` | `UpdatesRollback \| null` | 回滚信息；没有时为 `null`。 |
| `checkError` | `Record<string, string> \| null` | 最近一次检查更新的错误信息；没有时为 `null`。 |
| `downloadError` | `Record<string, string> \| null` | 最近一次下载更新的错误信息；没有时为 `null`。 |
| `downloadProgress` | `number` | 当前下载进度，范围为 `0` 到 `1`。 |
| `lastCheckForUpdateTime` | `Date \| null` | 最近一次检查更新的时间；尚未检查时为 `null`。 |
| `sequenceNumber` | `number` | 状态变化序号，每次变化递增。 |
| `downloadStartTime` | `Date \| null` | 最近一次下载开始时间；下载开始后有值。 |
| `downloadFinishTime` | `Date \| null` | 最近一次下载完成时间；下载完成后有值。 |

#### `UpdatesRollback`

回滚信息：

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `commitTime` | `Date` | 回滚提交时间。 |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
