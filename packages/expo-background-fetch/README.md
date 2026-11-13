# @expo-harmony/expo-background-fetch

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-background-fetch) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/background-fetch/)

为 HarmonyOS 上的 React Native 应用提供 Expo Background Fetch 的原生实现，与官方 `expo-background-fetch` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

在项目目录执行以下命令，安装本包及其 Expo 依赖：

```bash
npm install @expo-harmony/expo-background-fetch expo-background-fetch@~57.0.21 expo-task-manager@~57.0.21
```

## 配置

在 `app.json` 的 `plugins` 中加入 `@expo-harmony/expo-background-fetch`，并将它放在 `@expo-harmony/prebuild-config` 之前：

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

TypeScript 配置可从 `@expo-harmony/expo-background-fetch/plugin` 导入 `backgroundFetch`，在 `plugins` 中使用 `backgroundFetch()`。

## API 对照表

### Methods

#### `BackgroundFetch.getStatusAsync()`

返回 `Promise<BackgroundFetchStatus>`。HarmonyOS 支持 WorkScheduler 且任务可在无界面场景启动时返回 `Available`，否则返回 `Restricted`。

#### `BackgroundFetch.setMinimumIntervalAsync(minimumInterval: number)`

`minimumInterval` 以秒为单位，返回 `Promise<void>`。

- HarmonyOS 不应用此全局间隔设置；请在 `registerTaskAsync()` 的 `options.minimumInterval` 中设置每个任务的间隔。

#### `BackgroundFetch.registerTaskAsync(taskName: string, options: BackgroundFetchOptions = {})`

`taskName` 是通过 `TaskManager.defineTask` 定义的非空字符串。`options` 默认 `{}`，返回 `Promise<void>`。

同名任务重复注册会更新现有注册。单个应用最多注册 10 个任务；达到上限或 WorkScheduler 不可用时注册会失败。任务在应用前台时暂停，应用进入后台后可继续调度；单次执行最长 2 分钟，超时后由系统结束。实际触发时间由系统调度，不保证精确。

#### `BackgroundFetch.unregisterTaskAsync(taskName: string)`

`taskName` 是非空字符串。调用后取消该任务的注册，返回 `Promise<void>`；任务未注册时会失败。

### Types

#### `BackgroundFetchOptions`

| 属性              | 类型      |
| ----------------- | --------- |
| `minimumInterval` | `number`  |
| `stopOnTerminate` | `boolean` |
| `startOnBoot`     | `boolean` |

`minimumInterval` 以秒为单位，默认 `600` 秒，必须是正有限数且不大于 `2147483.647` 秒。HarmonyOS 的循环任务间隔至少为 2 小时；系统还按应用活跃分组限制执行频率：

- 活跃分组：最短 2 小时
- 经常使用分组：4 小时
- 常用分组：24 小时
- 极少使用分组：48 小时
- 受限使用分组、从未使用分组：禁止执行

`stopOnTerminate` 默认 `true`，应用正常终止后停止任务；设为 `false` 时任务可继续调度。`startOnBoot` 默认 `false`，设为 `true` 时任务会在设备重启后恢复。这两个选项可独立设置。

`stopOnTerminate` 和 `startOnBoot` 只能取布尔值；不支持未列出的选项字段。

### Enums

#### `BackgroundFetchResult`

| 成员      | 值  | 含义             |
| --------- | --- | ---------------- |
| `NoData`  | 1   | 没有新数据       |
| `NewData` | 2   | 成功获取到新数据 |
| `Failed`  | 3   | 获取数据失败     |

HarmonyOS 不会根据任务返回的枚举值调整后续调度。

#### `BackgroundFetchStatus`

| 成员         | 值  | 含义                             |
| ------------ | --- | -------------------------------- |
| `Denied`     | 1   | 后台行为被用户关闭               |
| `Restricted` | 2   | 后台更新不可用，用户无法重新开启 |
| `Available`  | 3   | 后台更新可用                     |

- HarmonyOS 没有针对单个应用的后台刷新开关，因此 `getStatusAsync()` 不会返回 `Denied`。

### Permissions

此 API 无需额外声明 HarmonyOS 权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
