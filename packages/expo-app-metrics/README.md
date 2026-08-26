# @expo-harmony/expo-app-metrics

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-app-metrics)

为 HarmonyOS 上的 React Native 应用提供 Expo App Metrics 的原生实现，与官方同版本的 `expo-app-metrics` 配套使用。支持记录 bundle 加载、首帧和可交互耗时，统计慢帧、冻结帧和丢帧，读取应用内存快照，以及持久化会话和自定义指标。

HarmonyOS 暂无可靠的公开启动原因和 Expo Updates 构建元数据来源，因此不会推测 cold/warm launch，也不会填充 update ID、EAS build ID 或 Expo SDK 版本；内存快照需要支持异步 HiDebug 接口的 API 20 及以上系统。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/renbaoshuo)
