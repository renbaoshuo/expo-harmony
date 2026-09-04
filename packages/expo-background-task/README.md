# @expo-harmony/expo-background-task

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-background-task)

为 HarmonyOS 上的 React Native 应用提供 Expo Background Task 的原生实现，与官方同版本的 `expo-background-task` 和 `expo-task-manager` 配套使用。支持通过 HarmonyOS Work Scheduler 注册、查询和注销后台任务，并由 Task Manager 持久化任务注册与执行状态。

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

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
