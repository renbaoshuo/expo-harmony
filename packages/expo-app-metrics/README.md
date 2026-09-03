# @expo-harmony/expo-app-metrics

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-app-metrics)

为 HarmonyOS 上的 React Native 应用提供 Expo App Metrics 的原生实现，与官方同版本的 `expo-app-metrics` 配套使用。支持采集应用启动耗时、帧率指标和内存使用快照，并支持按会话记录指标、附加自定义指标以及读取和清空本地持久化的记录。启动耗时包括冷启动、暖启动、Bundle 加载、首次渲染和可交互时间；帧率指标包括渲染帧数、掉帧、慢帧、卡顿帧数和卡顿总时长。

内存快照通过 HarmonyOS HiDebug 的异步接口读取，需要系统 API 版本 20 及以上。帧率指标基于系统帧回调统计，需要在 React Native UI 上下文就绪后才能获取。官方类型中标注为 Android 专属的会话 API（`startSession`、`stopSession`、`addCustomMetricToSession`）在 HarmonyOS 上同样可用。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
