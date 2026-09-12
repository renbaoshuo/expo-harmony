# @expo-harmony/expo-background-fetch

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-background-fetch) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/background-fetch/)

为 HarmonyOS 上的 React Native 应用提供 Expo Background Fetch 的原生实现，与官方同版本的 `expo-background-fetch` 和 `expo-task-manager` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-background-fetch expo-background-fetch@55.0.16 expo-task-manager@~55.0.16
```

使用前必须在 `app.json` 的 `plugins` 中传入 `@expo-harmony/expo-background-fetch`，并将其放在 `@expo-harmony/prebuild-config` 之前：

```json
{
  "expo": {
    "plugins": [
      "@expo-harmony/expo-background-fetch",
      "@expo-harmony/prebuild-config"
    ]
  }
}
```

HarmonyOS Work Scheduler 的周期任务最短间隔为 2 小时，实际执行时间还会受到系统电量、配额和应用活跃度影响。

## API 对照表

### Methods

#### `BackgroundFetch.getStatusAsync()`

返回 `Promise<BackgroundFetchStatus>`。系统具备 Work Scheduler 能力、且应用能在无界面场景下启动时返回 `Available`，否则返回 `Restricted`。HarmonyOS 没有针对单个应用的后台刷新开关，`Denied` 没有取值来源。

#### `BackgroundFetch.registerTaskAsync(taskName, options)`

返回 `Promise<void>`。任务先用 `TaskManager.defineTask` 定义，注册后写入 Work Scheduler，应用初始化时自动恢复。同名任务重复注册会替换之前的注册。

`taskName` 需为非空字符串，`options` 默认 `{}`。应用在前台时暂停执行，切回后台后允许系统继续调度。单次回调最长运行 2 分钟，超时系统会终止承载任务的 Extension 进程。单个应用同一时刻最多注册 10 个延迟任务。

Work Scheduler 不可用、config plugin 未应用、任务名或选项不合法时拒绝。

#### `BackgroundFetch.unregisterTaskAsync(taskName)`

返回 `Promise<void>`，取消任务在 Work Scheduler 中的注册。任务不存在时拒绝。

> **未实现的内容**
>
> - `setMinimumIntervalAsync(minimumInterval)`：HarmonyOS 按任务设置间隔，没有全局间隔设置，调用不产生效果。

### Types

#### `BackgroundFetchOptions`

| 属性              | 类型      |
| ----------------- | --------- |
| `minimumInterval` | `number`  |
| `stopOnTerminate` | `boolean` |
| `startOnBoot`     | `boolean` |

`minimumInterval` 以秒为单位，默认 600（10 分钟）。重复间隔会被抬到至少 2 小时，实际触发时间由系统调度决定，不保证精确。执行频率还按应用活跃分组分级限制：

- 活跃分组：最短 2 小时
- 经常使用分组：4 小时
- 常用分组：24 小时
- 极少使用分组：48 小时
- 受限使用分组、从未使用分组：不执行

`stopOnTerminate` 默认 `true`，最后一个 UIAbility 正常销毁后停止执行任务。后台无界面运行时释放和开发时重新加载不视为应用终止。

`startOnBoot` 默认 `false`。为 `true` 时任务持久化到系统，设备重启后恢复。两个选项独立配置：

| `stopOnTerminate` | `startOnBoot` | 正常终止后 | 设备重启后 |
| ----------------- | ------------- | ---------- | ---------- |
| `true`            | `false`       | 停止       | 不恢复     |
| `true`            | `true`        | 停止       | 恢复       |
| `false`           | `false`       | 继续调度   | 不恢复     |
| `false`           | `true`        | 继续调度   | 恢复       |

开机恢复使用系统持久化任务；前台暂停和终止状态按系统启动次数记录，扩展回调在加载 JS 前检查。系统重启后旧状态失效。系统强杀若不发送销毁回调，无法保证执行 `stopOnTerminate` 清理；系统强行停止应用时还受系统后台限制约束。

`stopOnTerminate` 和 `startOnBoot` 官方标记为 Android 专属，在 HarmonyOS 上可用。传入未知字段时拒绝。

### Enums

#### `BackgroundFetchResult`

| 成员      | 值  | 含义               |
| --------- | --- | ------------------ |
| `NoData`  | 1   | 没有新数据         |
| `NewData` | 2   | 成功获取到新数据   |
| `Failed`  | 3   | 尝试获取数据但失败 |

返回值在 HarmonyOS 上不影响后续调度。

#### `BackgroundFetchStatus`

| 成员         | 值  | 含义                             |
| ------------ | --- | -------------------------------- |
| `Denied`     | 1   | 用户关闭了后台行为               |
| `Restricted` | 2   | 后台更新不可用，用户无法重新开启 |
| `Available`  | 3   | 后台更新可用                     |

`getStatusAsync()` 在 HarmonyOS 上只会返回 `Restricted` 或 `Available`。

## 原生初始化

本模块自带一个应用级生命周期订阅器，应用一启动（AbilityStage 阶段）就会向 TaskManager 注册原生 consumer；即使进程由后台任务冷启动、尚未打开任何界面，注册也能完成。使用 CNG 时，AbilityStage 入口由 prebuild 自动生成；升级已有的 Bare 工程时，请按 [接入说明](../../docs/BareInstallation.md) 在 `module.json5` 中登记 `module.srcEntry`。系统的调度回调仍由 WorkScheduler Extension 接收，该订阅器只负责注册，不会替代 runtime loader，也不会自动启动 RN。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
