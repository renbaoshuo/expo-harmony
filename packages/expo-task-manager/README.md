# @expo-harmony/expo-task-manager

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-task-manager) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/task-manager/)

为 HarmonyOS 上的 React Native 应用提供 Expo Task Manager 的原生实现，与官方同版本的 `expo-task-manager` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-task-manager expo-task-manager
```

## API 对照表

### Methods

#### `TaskManager.defineTask(taskName, taskExecutor)`

定义任务处理函数。`taskName` 是非空任务名，必须与注册任务时使用的名称一致；`taskExecutor` 接收 `TaskManagerTaskBody`，返回的值会作为任务结果回传。参数不符合要求时会输出警告并忽略定义。

任务函数需在应用加载时于全局作用域定义，以便任务触发时可找到处理函数。任务可能在应用界面未打开时触发。

触发时找不到对应定义的已注册任务不会执行，并会自动注销。

#### `TaskManager.getRegisteredTasksAsync()`

返回 `Promise<TaskManagerTask[]>`，包含当前应用已注册任务的名称、类型和选项。注册信息会在应用重启后保留。

#### `TaskManager.getTaskOptionsAsync(taskName)`

`taskName` 为任务名。返回 `Promise<TaskOptions | null>`：任务已注册时返回注册选项，否则返回 `null`。

#### `TaskManager.isAvailableAsync()`

返回 `Promise<boolean>`。在 HarmonyOS 上始终返回 `true`。

#### `TaskManager.isTaskDefined(taskName)`

`taskName` 为任务名。返回 `boolean`，表示当前运行中是否已通过 `defineTask` 定义；应用重新启动后需重新定义任务。

#### `TaskManager.isTaskRegisteredAsync(taskName)`

`taskName` 为任务名。返回 `Promise<boolean>`，表示该任务是否已注册。注册信息会跨应用重启保留。

#### `TaskManager.unregisterTaskAsync(taskName)`

注销名为 `taskName` 的任务，返回 `Promise<void>`。任务未注册时会报错。已开始的执行仍可能在截止时间前返回结果。

#### `TaskManager.unregisterAllTasksAsync()`

注销当前应用已注册的全部任务，返回 `Promise<void>`。没有已注册任务时也会正常完成。

### Types

#### `TaskManagerError`

任务失败时可在 `TaskManagerTaskBody.error` 中收到此错误对象。

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `code` | `string \| number` | 错误码 |
| `message` | `string` | 错误信息 |

#### `TaskManagerTask`

表示当前应用已注册的任务。

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `taskName` | `string` | 注册任务时使用的名称 |
| `taskType` | `string` | 注册任务的模块提供的类型 |
| `options` | `any` | 注册任务时传入的选项 |

#### `TaskManagerTaskBody<T = unknown>`

传给任务处理函数的执行信息。

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `data` | `T` | 任务数据，结构由任务类型决定 |
| `error` | `TaskManagerError \| null` | 任务错误；无错误时为 `null` |
| `executionInfo` | `TaskManagerTaskBodyExecutionInfo` | 本次任务执行的信息 |

#### `TaskManagerTaskBodyExecutionInfo`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `eventId` | `string` | 本次执行的唯一 ID，完成时随结果回传 |
| `taskName` | `string` | 任务名称 |

- HarmonyOS 不提供 `appState` 字段。

#### `TaskManagerTaskExecutor<T = any>`

任务处理函数的类型为 `(body: TaskManagerTaskBody<T>) => Promise<any>`。没有单独设置截止时间的执行最长为两分钟；由后台任务触发的执行按对应的截止时间处理，超时后返回的结果会被忽略。

系统可能在任务完成前终止应用进程，任务也可能重复执行或未能完成。请确保任务处理函数能容忍重复执行或遗漏。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
