# @expo-harmony/expo-background-fetch

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-background-fetch)

为 HarmonyOS 上的 React Native 应用提供 Expo Background Fetch 的原生实现，与官方同版本的 `expo-background-fetch` 和 `expo-task-manager` 配套使用。支持通过 HarmonyOS Work Scheduler 注册、查询和注销后台抓取任务，并按任务应用 `minimumInterval`、`stopOnTerminate` 和 `startOnBoot` 选项。

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

HarmonyOS 的周期调度受系统资源策略影响，`minimumInterval` 小于 20 分钟时会按 20 分钟处理；当前 RNOH 运行时也无法在应用进程完全退出后由 Work Scheduler 独立冷启动 headless React Native 实例。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
