# @expo-harmony/expo-background-task

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-background-task) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/background-task/)

为 HarmonyOS 上的 React Native 应用提供 Expo Background Task 的原生实现，与官方同版本的 `expo-background-task` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

安装时需同时添加本包、`expo-background-task` 和 `expo-task-manager`：

```bash
npm install @expo-harmony/expo-background-task expo-background-task expo-task-manager
```

## 项目配置

使用 Expo Prebuild 生成 HarmonyOS 工程时，在 `app.json` 的 `plugins` 中加入 `@expo-harmony/expo-background-task`，并将它放在 `@expo-harmony/prebuild-config` 前面：

```json
{
  "expo": {
    "plugins": [
      "@expo-harmony/expo-background-task",
      "@expo-harmony/prebuild-config"
    ]
  }
}
```

## API 对照表

### Methods

#### `getStatusAsync()`

返回 `Promise<BackgroundTaskStatus>`。WorkScheduler 可用、应用包含所需扩展且后台任务运行时可用时返回 `Available`，否则返回 `Restricted`。

#### `registerTaskAsync(taskName, options?)`

注册名为 `taskName` 的周期任务，返回 `Promise<void>`。任务需先用 `TaskManager.defineTask` 定义，名称必须是非空字符串。若状态为 `Restricted`，调用会记录警告并跳过注册。

`options` 类型为 `BackgroundTaskOptions`，省略时默认为 `{}`。注册信息会保留，并在应用重新启动后恢复。同名任务已注册时调用不会更新选项；如需更改间隔，应先注销再注册。多个任务共用一个调度周期，采用最后注册任务的 `minimumInterval`。

任务的实际执行时间由系统决定，不保证按间隔准时运行；系统调度要求设备有可用网络。选项无效、WorkScheduler 不可用或调度失败时，调用会以对应错误拒绝。

#### `unregisterTaskAsync(taskName)`

注销名为 `taskName` 的任务，返回 `Promise<void>`。名称必须是非空字符串。任务未注册时直接返回；注销最后一个任务后，周期调度也会取消。

#### `triggerTaskWorkerForTestingAsync()`

在 Debug 构建中立即触发当前应用已注册的后台任务，返回 `Promise<boolean>`。有任务产生执行结果时返回 `true`，没有可执行任务时返回 `false`。调用不会改变周期调度。Release 构建中返回 `false`。

### Event subscriptions

#### `addExpirationListener(listener)`

任务执行到期时触发 `listener`，回调不接收参数。返回 `{ remove: () => void }`，调用 `remove()` 可取消订阅。单次执行窗口约为 2 分钟；进程被系统强制终止时，监听器可能没有机会运行。

### Types

#### `BackgroundTaskOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `minimumInterval` | `number` | 两次执行之间的最小间隔，单位为分钟，默认 12 小时。必须为正的有限数值；小于 2 小时的值按 2 小时处理，最大值约为 24.86 天 |

### Enums

#### `BackgroundTaskStatus`

| 成员 | 值 | 含义 |
| --- | --- | --- |
| `Restricted` | `1` | 后台任务当前不可用 |
| `Available` | `2` | 后台任务可用 |

#### `BackgroundTaskResult`

| 成员 | 值 | 含义 |
| --- | --- | --- |
| `Success` | `1` | 任务执行成功 |
| `Failed` | `2` | 任务执行失败 |

任务函数可返回 `Success` 或 `Failed` 表示本次执行结果；后续执行时间由系统安排。

### Error codes

#### `ERR_BACKGROUND_TASK_NOT_CONFIGURED`

应用未配置可用的 HarmonyOS WorkScheduler 扩展时，无法安排后台任务。

#### `ERR_BACKGROUND_TASK_UNAVAILABLE`

WorkScheduler 或应用的后台启动能力不可用时，注册任务会失败。

#### `ERR_BACKGROUND_TASK_INVALID_OPTIONS`

`options` 不是对象，或包含 `minimumInterval` 以外的字段时抛出。

#### `ERR_BACKGROUND_TASK_INVALID_INTERVAL`

`minimumInterval` 不是正的有限数值，或超出 HarmonyOS 可接受的最大值时抛出。

#### `ERR_BACKGROUND_TASK_SCHEDULER`

HarmonyOS 无法读取、安排或取消后台调度时抛出。

#### `ERR_BACKGROUND_TASK_WORK_ID`

HarmonyOS 没有可用于后台调度的任务标识时抛出。

### Permissions

本包不申请权限。若任务需要访问网络等能力，应用需自行声明相应权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
