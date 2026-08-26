# @expo-harmony/expo-task-manager

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-task-manager)

为 HarmonyOS 上的 React Native 应用提供 Expo Task Manager 的原生实现，与官方同版本的 `expo-task-manager` 配套使用。支持持久化任务注册、查询和注销，并为 Background Fetch、Background Task 等原生任务消费者提供按应用 owner 隔离的持久执行队列。

业务代码需要继续从官方 `expo-task-manager` 导入 JavaScript API，该包只负责 HarmonyOS 原生模块实现。具体的系统调度行为由对应任务包负责，例如 `@expo-harmony/expo-background-fetch` 和 `@expo-harmony/expo-background-task`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
