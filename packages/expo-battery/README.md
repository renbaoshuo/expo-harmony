# @expo-harmony/expo-battery

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-battery) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/battery/)

为 HarmonyOS 上的 React Native 应用提供 Expo Battery 的原生实现，与官方同版本的 `expo-battery` 配套使用。支持读取设备电量、充电状态和低电量模式，以及订阅对应的状态变化。

## 安装

```bash
npm install @expo-harmony/expo-battery expo-battery@55.0.13
```

## API 对照表

### Hooks

#### `useBatteryLevel()`

返回 `number`，电量比例，取值 0 到 1。初始值为 `-1`，读取完成后更新，之后跟随电量事件变化。

#### `useBatteryState()`

返回 `BatteryState`。初始值为 `BatteryState.UNKNOWN`，读取完成后更新，之后跟随电池状态事件变化。

#### `useLowPowerMode()`

返回 `boolean`。初始值为 `false`，读取完成后更新，之后跟随低电量模式事件变化。

#### `usePowerState()`

返回 `PowerState`，包含电量、电池状态和低电量模式。三项分别读取，之后各自跟随对应事件变化。

### Methods

#### `Battery.isAvailableAsync()`

返回 `Promise<boolean>`，恒为 `true`。设备是否带电池不影响该值。

#### `Battery.getBatteryLevelAsync()`

返回 `Promise<number>`，电量比例，取值 0 到 1。设备没有电池，或系统给出的电量不在 0 到 100 之间时返回 `-1`。读取失败时拒绝。

#### `Battery.getBatteryStateAsync()`

返回 `Promise<BatteryState>`。设备没有电池时返回 `BatteryState.UNKNOWN`。系统充电状态按以下方式映射：充电中为 `CHARGING`，未充电为 `UNPLUGGED`，已充满为 `FULL`，其他取值为 `UNKNOWN`。

#### `Battery.isLowPowerModeEnabledAsync()`

返回 `Promise<boolean>`，系统是否处于省电模式。普通省电和超级省电返回 `true`；API 20 起自定义省电模式也返回 `true`。其他电源模式返回 `false`。

#### `Battery.isBatteryOptimizationEnabledAsync()`

返回 `Promise<boolean>`，恒为 `false`。HarmonyOS 没有针对单个应用的电池优化开关，Android 上的这一概念在这里不适用。

#### `Battery.getPowerStateAsync()`

返回 `Promise<PowerState>`，一次读取电量、电池状态和低电量模式，取值分别与对应方法一致。任一项读取失败时整体拒绝。

### Event Subscriptions

#### `Battery.addBatteryLevelListener(listener)`

订阅电量变化，回调收到 `BatteryLevelEvent`。返回 `Subscription`，调用 `remove()` 取消订阅。

只在应用处于前台时监听系统事件，切到后台会停止监听，回到前台后补发期间发生的变化。订阅后不会立即回调，只在数值变化时触发。

#### `Battery.addBatteryStateListener(listener)`

订阅电池状态变化，回调收到 `BatteryStateEvent`。返回 `Subscription`。前后台行为与电量事件一致，状态没有变化时不触发。

#### `Battery.addLowPowerModeListener(listener)`

订阅低电量模式变化，回调收到 `PowerModeEvent`。返回 `Subscription`。前后台行为与电量事件一致，模式没有变化时不触发。

### Types

#### `BatteryLevelEvent`

| 属性           | 类型     |
| -------------- | -------- |
| `batteryLevel` | `number` |

#### `BatteryStateEvent`

| 属性           | 类型           |
| -------------- | -------------- |
| `batteryState` | `BatteryState` |

#### `PowerModeEvent`

| 属性           | 类型      |
| -------------- | --------- |
| `lowPowerMode` | `boolean` |

#### `PowerState`

| 属性           | 类型           |
| -------------- | -------------- |
| `batteryLevel` | `number`       |
| `batteryState` | `BatteryState` |
| `lowPowerMode` | `boolean`      |

#### `Subscription`

监听句柄，调用 `remove()` 取消订阅，返回 `void`。

### Enums

#### `BatteryState`

| 成员        | 值  | 含义                                           |
| ----------- | --- | ---------------------------------------------- |
| `UNKNOWN`   | `0` | 无法判断，设备没有电池或充电状态不在已知取值内 |
| `UNPLUGGED` | `1` | 未充电                                         |
| `CHARGING`  | `2` | 充电中                                         |
| `FULL`      | `3` | 已充满                                         |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
