# @expo-harmony/expo-battery

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-battery)

为 HarmonyOS 上的 React Native 应用提供 Expo Battery 的原生实现，支持读取设备电量、充电状态和低电量模式，以及订阅对应的状态变化，与官方同版本的 `expo-battery` 配套使用。JavaScript API、类型和 React Hook 由官方 `expo-battery` 包提供。

注：`isBatteryOptimizationEnabledAsync()` 是 Android 专属 API，HarmonyOS 没有等价接口，因此会直接返回 `false`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/renbaoshuo)
