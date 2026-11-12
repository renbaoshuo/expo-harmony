# @expo-harmony/expo-app-metrics

[GitHub 仓库](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-app-metrics)

为 HarmonyOS 上的 React Native 应用提供 Expo App Metrics 的原生实现，与官方同版本的 `expo-app-metrics` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-app-metrics expo-app-metrics
```

## API 对照表

### Components

#### `AppMetricsRoot`

应用首次渲染后记录 `timeToFirstRender`。设置 `errorBoundaryFallback` 后，根组件也会捕获渲染错误并显示指定内容；传入 `null` 时捕获错误后不显示内容。

#### `AppMetricsRoot.wrap(Component)`

返回一个用 `AppMetricsRoot` 包裹的组件。

#### `AppMetricsErrorBoundary`

捕获子树的渲染错误，将错误和组件堆栈作为非致命日志记录，并显示 `fallback`。`fallback` 可以是 React 节点、接收 `error` 和 `resetError` 的函数，或 `null`。

### Hooks

#### `useNetworkRequestObserver(options?)`

订阅当前 React Native 实例发出的网络请求。`filter.hosts` 按主机名筛选，`filter.methods` 按请求方法筛选；更新筛选条件时会继续使用当前订阅。`onStarted` 和 `onCompleted` 分别接收请求开始和完成事件。

### Methods

#### `markFirstRender()`

记录启动后首次 React 渲染所需时间。若调用时尚无可用的前台启动时间，则不记录该指标。

#### `markInteractive(attributes?)`

记录启动到应用可交互的时间。可通过 `attributes.routeName` 和 `attributes.params` 附加路由名及自定义参数。HarmonyOS 可用的电池、低电量模式、热状态、网络状态和请求摘要会附加到该指标；系统无法读取的字段会省略。

#### `getAppStartupTimesAsync()`

返回已记录的启动时间。HarmonyOS 可记录 `bundleLoadTime`、`timeToFirstRender` 和 `timeToInteractive`。

- 不提供 `coldLaunchTime` 或 `warmLaunchTime`：HarmonyOS 不区分冷启动和暖启动。
- 不提供 `loadTime`：HarmonyOS 不提供此启动时间读数。

#### `getFrameRateMetricsAsync()`

读取帧率统计，包括渲染帧、丢帧、慢帧、冻结帧和耗时。窗口界面可用后才开始采集；采集尚未开始时会以 `ERR_APP_METRICS_FRAME_METRICS_UNAVAILABLE` 拒绝。

#### `getMemoryUsageSnapshotAsync()`

读取当前内存快照，包含应用已用物理内存和可用内存，单位为字节。API 13 至 19 也支持读取；如果系统未提供所需内存数据，调用会失败。

#### `takeMemoryUsageSnapshotAsync(sessionId?)`

读取内存快照。传入会话 ID 时，也会把物理内存和可用内存记录到该会话；不传会话 ID 时只返回快照。

#### `getMainSession()`

获取当前应用进程的主会话。应用每次启动都会有一条主会话。安装 `expo-updates` 时，会话还会包含当前更新信息，并记录成功下载更新所用的时间。

#### `getForegroundSession()`

获取当前前台会话；应用进入后台后返回 `null`。会话包含该会话的指标和日志。

#### `Session.isActive()`

读取该会话当前是否仍处于活动状态。

#### `Session.getEndDate()`

读取会话结束时间；会话仍处于活动状态时返回 `null`。

#### `Session.getMetrics()`

读取该会话记录的指标。

#### `Session.getLogs()`

读取该会话记录的日志。

#### `Session.addMetric(metric)`

向该会话添加单条自定义指标。输入需包含有效的 `category`、`name`、`value` 和可选的 ISO 时间戳。

#### `startSession()`

创建一个自定义会话并返回会话 ID。

#### `stopSession(sessionId)`

结束指定的自定义会话。

#### `addCustomMetricToSession(metric)`

向指定会话添加自定义指标。`metric` 需要包含 `sessionId`、`category`、`name` 和有限数值 `value`；`timestamp`、`routeName`、`params` 和 `updateId` 可选。

#### `logEvent(name, options?)`

向主会话添加日志。可设置 `body`、`attributes` 和 `severity`；严重级别默认为 `info`。

#### `setGlobalAttributes(attributes?)`

设置后续指标和日志共用的属性。记录自身的同名属性优先；传入 `null`、`undefined` 或空对象可清除全局属性。

#### `reportError(error)`

记录 JavaScript 错误信息，包括消息、堆栈和是否致命。使用 `AppMetricsErrorBoundary` 时，错误记录还会包含组件堆栈。

#### `getInactiveSessions()`

获取本地保留的已结束会话，按开始时间从新到旧排列；每条记录包括指标、日志和可用的崩溃报告。会话数据保留七天。此方法适用于检查本地数据。

#### `getAllCrashReports()`

获取系统提供的应用进程崩溃报告，按接收时间从新到旧排列。系统未能关联会话的报告，其 `sessionId` 为 `null`。

- 应用冻结记录为非致命的 `app.freeze` 日志，不作为进程崩溃报告。

#### `getStoredEntries()`

读取设备本地保存的所有指标记录。

#### `clearStoredEntries()`

清除设备本地保存的会话、指标、日志和崩溃报告。

### Event subscriptions

#### `NetworkRequestObserver`

创建观察器后，可通过 `addListener` 订阅 `requestStarted` 和 `requestCompleted`，并通过 `setFilter` 更新主机名或请求方法筛选条件。只观察当前 React Native 实例发出的请求；工作线程或绕过该实例网络接口发出的请求不会产生事件。

#### `requestStarted`

请求开始时触发，事件包含请求 `id`、`url`、`method` 和 `startedAt`。对应的完成事件使用相同 `id`。

#### `requestCompleted`

请求完成时触发，事件包含状态码、错误描述、总耗时及重定向列表。

- `networkProtocol`、`requestBytesSent` 和 `responseBytesReceived` 为 `null`：HarmonyOS 不提供网络协议和收发字节数。
- `redirects` 在系统未提供重定向链时为空数组。

### Types

#### `AppStartupTimes`

启动时间字段为可选项。

- HarmonyOS 不填充 `loadTime`：HarmonyOS 不提供此启动时间读数。
- HarmonyOS 不填充 `coldLaunchTime` 或 `warmLaunchTime`：HarmonyOS 不区分冷启动和暖启动。

#### `MemoryUsageSnapshot`

HarmonyOS 提供 `physical` 和 `available` 两个字节数值。

- 不提供 `allocated` 或 `javaHeap`：HarmonyOS 的内存快照只包含物理内存和可用内存。

#### `FrameRateMetrics`

包含 `renderedFrames`、`expectedFrames`、`droppedFrames`、`frozenFrames`、`slowFrames`、`freezeTime` 和 `sessionDuration`。

#### `Metric`

表示已记录指标，包含时间戳、类别、名称、数值、路由名及自定义参数等字段。

#### `MetricAttributes`

表示启动指标可接收的路由名和自定义参数。

#### `MetricInput`

表示传给 `Session.addMetric()` 的指标输入，不包含会话 ID。

#### `Session`

`Session` 提供 `id`、`type` 和 `startDate`。会话由本包创建，不支持直接构造。

#### `SessionType`

HarmonyOS 会话类型包括 `main`、`foreground` 和 `custom`。

#### `DebugSession`

`getInactiveSessions()` 返回的历史会话记录，包含会话信息、指标、日志和可用的崩溃报告。

#### `LogRecord`

表示日志记录。

#### `LogEventOptions`

表示 `logEvent()` 的可选参数。

#### `LogAttributeValue`

日志属性值支持字符串、数字、布尔值、数组和嵌套对象。

#### `LogSeverity`

日志严重级别为 `trace`、`debug`、`info`、`warn`、`error` 或 `fatal`。

#### `CrashReport`

表示崩溃报告，可包含系统提供的信号、终止原因、异常信息和调用栈；具体字段取决于系统提供的数据。

#### `CallStack`

表示调用栈及其线程归属信息。

#### `CallStackFrame`

表示调用栈中的单个帧，包括系统提供的符号名或二进制名。

#### `CallStackTree`

表示崩溃报告中的调用栈集合。

#### `NetworkRequestFilter`

支持 `hosts` 和 `methods` 数组。主机名和请求方法忽略大小写匹配；未设置的字段不限制请求，不同字段同时设置时需同时匹配。

#### `NetworkRequestStartedEvent`

表示请求开始事件；事件字段见 `requestStarted`。

#### `NetworkRequestCompletedEvent`

表示请求完成事件；事件字段及 HarmonyOS 差异见 `requestCompleted`。

#### `NetworkRequestRedirect`

表示重定向链中的单个跳转步骤。

#### `NetworkRequestObserverEvents`

`NetworkRequestObserver` 的事件映射类型，包含 `requestStarted` 和 `requestCompleted`。

#### `UseNetworkRequestObserverOptions`

Hook 参数类型，包含可选筛选条件以及 `onStarted`、`onCompleted` 回调。

#### `AppMetricsErrorBoundaryProps`

表示错误边界的属性。

#### `AppMetricsErrorBoundaryFallbackProps`

表示 `fallback` 函数收到的错误值和重试回调。

#### `ExpoAppMetricsModuleType`

Expo App Metrics 模块方法的类型定义。

### Error codes

#### `ERR_APP_METRICS_INVALID_ARGUMENT`

参数格式不正确，或参数不包含可序列化的值。

#### `ERR_INVALID_ARGUMENT`

网络观察器筛选条件格式不正确。

#### `ERR_APP_METRICS_INVALID_METRIC`

指标缺少必需字段、时间戳无效，或数值不是有限数字。

#### `ERR_APP_METRICS_INVALID_SESSION`

会话 ID 为空。

#### `ERR_APP_METRICS_SESSION_NOT_FOUND`

指定的会话不存在。

#### `ERR_APP_METRICS_SESSION_CONSTRUCTOR`

尝试直接构造由本包管理的会话对象。

#### `ERR_APP_METRICS_FRAME_METRICS_UNAVAILABLE`

帧率采集尚未开始，当前没有可返回的帧率数据。

#### `ERR_APP_METRICS_MEMORY_API`

系统未提供读取内存快照所需的信息。

#### `ERR_APP_METRICS_MEMORY_SNAPSHOT`

无法读取内存快照。

#### `ERR_APP_METRICS_NETWORK_UNAVAILABLE`

网络请求观察功能不可用。

#### `ERR_APP_METRICS_NOT_INITIALIZED`

应用指标尚未初始化。

#### `ERR_APP_METRICS_NOT_READY`

应用指标仍在准备中。

#### `ERR_APP_METRICS_DESTROYED`

应用指标已停止接受调用。

#### `ERR_APP_METRICS_STORAGE`

本地存储读写失败。

#### `ERR_APP_METRICS_STORAGE_CAPACITY`

本地存储容量不足。

### Permissions

本包声明 `ohos.permission.GET_NETWORK_INFO`，用于读取网络状态。无法读取网络状态时，相应网络字段会省略。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
