# @expo-harmony/expo-battery

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-battery) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/battery/)

为 HarmonyOS 上的 React Native 应用提供 Expo Battery 的原生实现，与官方同版本的 `expo-battery` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-battery expo-battery
```

## API 对照表

### Hooks

#### `useBatteryLevel()`

无参数，返回 `number`。电量比例范围为 `0` 到 `1`；设备没有电池或电量未知时为 `-1`。首次读取完成后更新，之后在电量变化时更新。

#### `useBatteryState()`

无参数，返回 `BatteryState`。初始值为 `BatteryState.UNKNOWN`，首次读取完成后更新，之后在电池状态变化时更新。

#### `useLowPowerMode()`

无参数，返回 `boolean`。初始值为 `false`，首次读取完成后更新，之后在低电量模式状态变化时更新。

#### `usePowerState()`

无参数，返回 `PowerState`，包含电量、电池状态和低电量模式。初始值分别为 `-1`、`BatteryState.UNKNOWN` 和 `false`；首次读取完成后，各字段分别在对应状态变化时更新。

### Methods

#### `Battery.isAvailableAsync()`

无参数，返回 `Promise<boolean>`。始终为 `true`，即使设备没有电池。

#### `Battery.getBatteryLevelAsync()`

无参数，返回 `Promise<number>`。电量比例范围为 `0` 到 `1`；设备没有电池或系统电量值无效时返回 `-1`。读取失败时以 `ERR_BATTERY_LEVEL` 拒绝。

#### `Battery.getBatteryStateAsync()`

无参数，返回 `Promise<BatteryState>`。设备没有电池时返回 `BatteryState.UNKNOWN`。未充电且未连接电源时返回 `UNPLUGGED`，充电中返回 `CHARGING`，已充满返回 `FULL`。已连接 AC、USB 或无线充电器但未充电时返回 `NOT_CHARGING`；无法识别的状态返回 `UNKNOWN`。读取失败时以 `ERR_BATTERY_STATE` 拒绝。

#### `Battery.isLowPowerModeEnabledAsync()`

无参数，返回 `Promise<boolean>`。普通省电模式和超级省电模式返回 `true`；HarmonyOS API 20 及以上的自定义省电模式也返回 `true`，其他电源模式返回 `false`。读取失败时以 `ERR_BATTERY_POWER_MODE` 拒绝。

#### `Battery.isBatteryOptimizationEnabledAsync()`

无参数，返回 `Promise<boolean>`，始终为 `false`。HarmonyOS 不提供应用级电池优化状态查询；此值不表示系统不会限制应用在后台运行。

#### `Battery.getPowerStateAsync()`

无参数，返回 `Promise<PowerState>`，并行读取电量、电池状态和低电量模式。三项分别读取，不保证来自同一时刻；任一项读取失败时整体拒绝。

### Event subscriptions

#### `Battery.addBatteryLevelListener(listener)`

参数 `listener: (event: BatteryLevelEvent) => void`，订阅电量变化。返回 `Subscription`，调用 `remove()` 取消订阅。订阅后不会立即回调；只有电量值变化时才触发。应用处于后台时暂停监听，回到前台后若电量值与此前不同则触发事件。

#### `Battery.addBatteryStateListener(listener)`

参数 `listener: (event: BatteryStateEvent) => void`，订阅电池状态变化。返回 `Subscription`，调用 `remove()` 取消订阅。订阅后不会立即回调；应用处于后台时暂停监听，回到前台后若电池状态与此前不同则触发事件。

#### `Battery.addLowPowerModeListener(listener)`

参数 `listener: (event: PowerModeEvent) => void`，订阅低电量模式变化。返回 `Subscription`，调用 `remove()` 取消订阅。订阅后不会立即回调；应用处于后台时暂停监听，回到前台后若 `lowPowerMode` 的值与此前不同则触发事件。

### Types

#### `BatteryLevelEvent`

包含 `batteryLevel: number`，表示电量比例，范围为 `0` 到 `1`；电量未知时为 `-1`。

#### `BatteryStateEvent`

包含 `batteryState: BatteryState`，表示当前电池状态。

#### `PowerModeEvent`

包含 `lowPowerMode: boolean`，表示系统是否处于低电量模式。

#### `PowerState`

包含 `batteryLevel: number`、`batteryState: BatteryState` 和 `lowPowerMode: boolean`，分别表示电量比例、电池状态和低电量模式状态。电量未知时 `batteryLevel` 为 `-1`。

#### `Subscription`

事件订阅句柄。调用 `remove()` 取消订阅，返回 `void`。

### Enums

#### `BatteryState`

`UNKNOWN` 为 `0`，表示状态未知或无法判断；`UNPLUGGED` 为 `1`，表示未连接电源且未充电；`CHARGING` 为 `2`，表示正在充电；`FULL` 为 `3`，表示电量已满；`NOT_CHARGING` 为 `4`，表示已连接电源但当前未充电。

### Error codes

#### `ERR_BATTERY_LEVEL`

读取电量失败时抛出。

#### `ERR_BATTERY_STATE`

读取电池状态失败时抛出。

#### `ERR_BATTERY_POWER_MODE`

读取系统电源模式失败时抛出。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
