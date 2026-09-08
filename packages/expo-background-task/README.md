# @expo-harmony/expo-background-task

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-background-task) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/background-task/)

为 HarmonyOS 上的 React Native 应用提供 Expo Background Task 的原生实现，与官方同版本的 `expo-background-task` 和 `expo-task-manager` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-background-task expo-background-task@55.0.18 expo-task-manager@~55.0.16
```

使用前必须在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-background-task`，并将其放在 `@expo-harmony/prebuild-config` 之前：

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

HarmonyOS Work Scheduler 的周期任务最短间隔为 2 小时，实际执行时间还会受到系统电量、配额和应用活跃度影响。只有宿主注册了可在无界面场景启动 RNOH 的 TaskManager runtime loader 时，本模块才会报告为可用；普通前台 RNOH Host 不能替代冷启动能力。

## API 对照表

### Methods

#### `BackgroundTask.getStatusAsync()`

返回 `Promise<BackgroundTaskStatus>`。系统具备 Work Scheduler 能力、应用声明了对应的 workScheduler 扩展，且宿主注册了可在无界面场景启动 RNOH 的 TaskManager runtime loader 时返回 `Available`，任一条件不满足返回 `Restricted`。官方文档称原生平台返回 `Available`，HarmonyOS 上该值可能为 `Restricted`。

#### `BackgroundTask.registerTaskAsync(taskName, options)`

注册名为 `taskName` 的周期任务，返回 `Promise<void>`。任务需先用 `TaskManager.defineTask` 定义，未定义或 `taskName` 不是非空字符串时抛出错误。注册信息持久化保存，应用退出后仍保留。任务已注册时直接返回，不更新选项，改动间隔要先注销再注册。

`options` 默认 `{}`，只接受 `minimumInterval`，传入其他字段抛出错误。

`minimumInterval` 单位为分钟，默认 12 小时。HarmonyOS Work Scheduler 的周期下限为 2 小时，小于 2 小时的值按 2 小时处理。多个任务共用一个调度周期，各自的 `minimumInterval` 不会分别生效。取值不是正数或超出 Work Scheduler 可表示的范围时抛出错误。

状态为 `Restricted` 时不做注册，只在控制台给出警告。实际执行时间由系统决定，会受电量、配额和应用活跃度影响而推迟。

#### `BackgroundTask.unregisterTaskAsync(taskName)`

注销任务，返回 `Promise<void>`。任务未注册时直接返回。取消最后一个任务后，对应的周期调度一并取消。

> **未实现的内容**
>
> - `triggerTaskWorkerForTestingAsync()`：HarmonyOS 没有手动触发周期任务的原生入口，调用会抛出 `UnavailabilityError`。

### Event Subscriptions

#### `BackgroundTask.addExpirationListener(listener)`

任务执行超过时限被中止时触发，回调没有参数，返回 `{ remove: () => void }` 用于取消订阅。单次后台执行约有 2 分钟时限。该接口官方标记为 iOS 专属，在 HarmonyOS 上可用。

### Types

#### `BackgroundTaskOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `minimumInterval` | `number` | 两次执行之间的不精确间隔，单位分钟，默认 12 小时，最小 2 小时 |

### Enums

#### `BackgroundTaskStatus`

| 成员 | 值 | 含义 |
| --- | --- | --- |
| `Restricted` | `1` | 后台任务不可用 |
| `Available` | `2` | 后台任务可用 |

#### `BackgroundTaskResult`

| 成员 | 值 | 含义 |
| --- | --- | --- |
| `Success` | `1` | 任务执行成功 |
| `Failed` | `2` | 任务执行失败 |

任务返回值不影响后续调度，HarmonyOS 上仅作记录。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
