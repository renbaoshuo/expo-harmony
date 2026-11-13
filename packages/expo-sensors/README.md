# @expo-harmony/expo-sensors

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-sensors) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/sensors/)

为 HarmonyOS 上的 React Native 应用提供 Expo Sensors 原生实现，与官方 `expo-sensors` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

在 Expo 应用项目目录中运行以下命令安装：

```bash
npm install @expo-harmony/expo-sensors expo-sensors@~57.0.3
```

## API 对照表

### Constants

#### `DeviceMotion.Gravity`

地球标准重力加速度，值为 `9.80665`，单位为 `m/s²`。

### Methods

#### `Accelerometer.isAvailableAsync()`

返回 `Promise<boolean>`，表示设备是否提供加速度计。

#### `Barometer.isAvailableAsync()`

返回 `Promise<boolean>`，表示设备是否提供气压计。

#### `DeviceMotion.isAvailableAsync()`

返回 `Promise<boolean>`。设备运动所需的加速度、线性加速度、重力、陀螺仪和旋转矢量传感器都可用时返回 `true`。

#### `Gyroscope.isAvailableAsync()`

返回 `Promise<boolean>`，表示设备是否提供陀螺仪。

#### `LightSensor.isAvailableAsync()`

返回 `Promise<boolean>`，表示设备是否提供环境光传感器。

#### `Magnetometer.isAvailableAsync()`

返回 `Promise<boolean>`，表示设备是否提供磁力计。

#### `MagnetometerUncalibrated.isAvailableAsync()`

返回 `Promise<boolean>`，表示设备是否提供未校准磁力计。

#### `Pedometer.isAvailableAsync()`

返回 `Promise<boolean>`，表示设备是否提供计步器。

#### `DeviceSensor.setUpdateInterval(intervalMs)`

设置传感器更新间隔，参数单位为毫秒，返回 `void`。参数须为有限的非负数；实际更新频率受传感器支持的采样范围限制。默认间隔为 100 毫秒；`DeviceMotion` 默认间隔为 `1000 / 60` 毫秒。`Pedometer` 不提供此方法。

#### `DeviceSensor.hasListeners()`

返回 `boolean`，表示当前传感器是否有监听器。

#### `DeviceSensor.getListenerCount()`

返回 `number`，表示当前传感器的监听器数量。

#### `DeviceSensor.removeAllListeners()`

移除当前传感器的所有监听器，返回 `void`。

#### `DeviceSensor.removeSubscription(subscription)`

移除指定的监听订阅，返回 `void`。此方法已废弃，请调用 `subscription.remove()`。

#### `Pedometer.getStepCountAsync(start, end)`

参数 `start` 和 `end` 为 `Date`，表示查询范围的起止时间；返回类型为 `Promise<PedometerResult>`。

- HarmonyOS 不提供按时间范围查询步数的功能。

### Event subscriptions

#### `Accelerometer.addListener(listener)`

参数 `listener: (measurement: AccelerometerMeasurement) => void`。订阅加速度更新，返回 `Subscription`；调用 `remove()` 取消订阅。测量值的三轴单位为 `g`。应用进入后台时暂停事件，回到前台后恢复。

#### `Barometer.addListener(listener)`

参数 `listener: (measurement: BarometerMeasurement) => void`。订阅气压更新，返回 `Subscription`；调用 `remove()` 取消订阅。应用进入后台时暂停事件，回到前台后恢复。

#### `DeviceMotion.addListener(listener)`

参数 `listener: (measurement: DeviceMotionMeasurement) => void`。订阅设备运动更新，返回 `Subscription`；调用 `remove()` 取消订阅。收齐含重力加速度和设备姿态数据后开始回调；线性加速度和角速度数据尚不可用时，相应字段为 `null`。应用进入后台时暂停事件，回到前台后恢复。

#### `Gyroscope.addListener(listener)`

参数 `listener: (measurement: GyroscopeMeasurement) => void`。订阅陀螺仪更新，返回 `Subscription`；调用 `remove()` 取消订阅。测量值的三轴单位为 `rad/s`。应用进入后台时暂停事件，回到前台后恢复。

#### `LightSensor.addListener(listener)`

参数 `listener: (measurement: LightSensorMeasurement) => void`。订阅环境光更新，返回 `Subscription`；调用 `remove()` 取消订阅。应用进入后台时暂停事件，回到前台后恢复。

#### `Magnetometer.addListener(listener)`

参数 `listener: (measurement: MagnetometerMeasurement) => void`。订阅磁场强度更新，返回 `Subscription`；调用 `remove()` 取消订阅。应用进入后台时暂停事件，回到前台后恢复。

#### `MagnetometerUncalibrated.addListener(listener)`

参数 `listener: (measurement: MagnetometerUncalibratedMeasurement) => void`。订阅未经校准的磁场强度更新，返回 `Subscription`；调用 `remove()` 取消订阅。应用进入后台时暂停事件，回到前台后恢复。

#### `Pedometer.watchStepCount(callback)`

参数 `callback: PedometerUpdateCallback`，返回 `Subscription`；调用 `remove()` 取消订阅。需要运动权限；未授权时不会收到步数事件。事件按默认 100 毫秒间隔节流。每轮订阅首次收到的步数为 `1`；前后台切换会保留本轮计数，移除最后一个订阅后再次订阅会重新计数。应用处于后台时暂停事件；恢复后步数可能包含暂停期间记录的步数。

### Types

#### `AccelerometerMeasurement`

- `x`、`y`、`z: number`：设备三轴加速度，单位 `g`。
- `timestamp: number`：测量时间，单位秒。

#### `BarometerMeasurement`

- `pressure: number`：气压，单位 `hPa`。
- `timestamp: number`：测量时间，单位秒。
- `relativeAltitude?: number`：HarmonyOS 不提供相对高度数据。

#### `DeviceMotionMeasurement`

- `acceleration: { x, y, z, timestamp } | null`：不含重力的加速度，单位 `m/s²`；数据暂不可用时为 `null`。
- `accelerationIncludingGravity: { x, y, z, timestamp }`：含重力的加速度，单位 `m/s²`。
- `rotation: { alpha, beta, gamma, timestamp }`：设备姿态，角度单位为弧度。
- `rotationRate: { alpha, beta, gamma, timestamp } | null`：角速度，单位为度每秒；数据暂不可用时为 `null`。
- `interval: number`：更新间隔，单位毫秒。
- `orientation: DeviceMotionOrientation`：屏幕方向对应的角度。

#### `GyroscopeMeasurement`

- `x`、`y`、`z: number`：设备三轴角速度，单位 `rad/s`。
- `timestamp: number`：测量时间，单位秒。

#### `LightSensorMeasurement`

- `illuminance: number`：环境光照度，单位 `lux`。
- `timestamp: number`：测量时间，单位秒。

#### `MagnetometerMeasurement`

- `x`、`y`、`z: number`：设备三轴磁场强度，单位 `μT`。
- `timestamp: number`：测量时间，单位秒。

#### `MagnetometerUncalibratedMeasurement`

- `x`、`y`、`z: number`：设备三轴未经校准的磁场强度，单位 `μT`。
- `timestamp: number`：测量时间，单位秒。

#### `PedometerResult`

- `steps: number`：本轮计步订阅中的步数。

#### `PedometerUpdateCallback`

类型为 `(result: PedometerResult) => void`，接收步数更新。

#### `Subscription`

订阅句柄。调用 `remove()` 取消订阅，返回 `void`。

#### `PermissionExpiration`

类型为 `'never' | number`。HarmonyOS 上始终为 `'never'`。

#### `PermissionResponse`

- `status: PermissionStatus`：`'granted'`、`'denied'` 或 `'undetermined'`。
- `granted: boolean`：`status` 为 `'granted'` 时为 `true`。
- `canAskAgain: boolean`：`status` 为 `'granted'` 或 `'undetermined'` 时为 `true`，为 `'denied'` 时为 `false`。
- `expires: PermissionExpiration`：HarmonyOS 上始终为 `'never'`。

### Enums

#### `DeviceMotionOrientation`

- `Portrait = 0`
- `RightLandscape = 90`
- `UpsideDown = 180`
- `LeftLandscape = -90`

#### `PermissionStatus`

- `GRANTED = 'granted'`
- `DENIED = 'denied'`
- `UNDETERMINED = 'undetermined'`

### Error codes

#### `ERR_NOT_SUPPORTED`

调用 `Pedometer.getStepCountAsync()` 时抛出；HarmonyOS 不支持按日期范围查询步数。

#### `ERR_SENSOR_INTERVAL`

`DeviceSensor.setUpdateInterval()` 的参数不是有限的非负数，或超出可接受的数值范围时抛出。

#### `ERR_SENSOR_PERMISSION`

查询或请求计步权限时，权限未在应用中声明、系统无法请求权限或系统返回无效权限状态时抛出。

### Permissions

#### `DeviceSensor.getPermissionsAsync()`

返回 `Promise<PermissionResponse>`。`Accelerometer` 和 `Gyroscope` 返回对应系统权限状态；`DeviceMotion` 返回加速度计和陀螺仪权限状态。HarmonyOS 在安装时授予 `ohos.permission.ACCELEROMETER` 和 `ohos.permission.GYROSCOPE`。

#### `DeviceSensor.requestPermissionsAsync()`

返回 `Promise<PermissionResponse>`。`Accelerometer`、`Gyroscope` 和 `DeviceMotion` 的请求方法不会弹出授权对话框；`Barometer`、`LightSensor`、`Magnetometer` 和 `MagnetometerUncalibrated` 不需要额外权限，查询和请求均返回已授权状态。

#### `Pedometer.getPermissionsAsync()`

返回 `Promise<PermissionResponse>`，读取 `ohos.permission.ACTIVITY_MOTION` 的授权状态。

#### `Pedometer.requestPermissionsAsync()`

返回 `Promise<PermissionResponse>`，请求 `ohos.permission.ACTIVITY_MOTION`。授权成功后，已等待权限的步数订阅会恢复；用户拒绝或需要前往系统设置授权时返回 `denied`。

HarmonyOS SDK API 20 及以上可区分尚未请求和已拒绝。API 13 至 19 首次请求前返回 `undetermined`；请求被拒绝后返回 `denied`。`PermissionResponse` 的 `expires` 始终为 `'never'`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors)

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
