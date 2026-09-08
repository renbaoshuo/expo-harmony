# @expo-harmony/expo-location

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-location) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/location/)

为 HarmonyOS 上的 React Native 应用提供 Expo Location 的原生实现，与官方同版本的 `expo-location` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-location expo-location@55.1.10
```

## API 对照表

### Hooks

#### `useForegroundPermissions(options)`

返回 `[LocationPermissionResponse | null, request, get]`，读取或申请前台定位权限，取值与 `getForegroundPermissionsAsync()`、`requestForegroundPermissionsAsync()` 一致。`options` 见 `PermissionHookOptions`。

> **未实现的内容**
>
> - `useBackgroundPermissions(options)`：后台定位未支持，读取和申请都返回 `status: 'denied'`、`canAskAgain: false`。

### Methods

#### `Location.getForegroundPermissionsAsync()`

返回 `Promise<LocationPermissionResponse>`，查询前台定位权限。

授予模糊定位权限（`ohos.permission.APPROXIMATELY_LOCATION`）即视为已授权，精确定位权限不是必需。API 20 及以上直接读取系统的权限状态，未决定返回 `undetermined`，拒绝返回 `denied`；API 13–19 只记录本模块收到的明确拒绝，返回 `denied` 需要之前在这里拒绝过，否则为 `undetermined`，也无法反映其他模块的申请或系统设置重置。拒绝后 `canAskAgain` 为 `false`。`expires` 恒为 `'never'`。

#### `Location.requestForegroundPermissionsAsync()`

返回 `Promise<LocationPermissionResponse>`，申请前台定位权限，同时申请模糊与精确定位。同一时刻的重复调用共用一次系统弹窗。

模块已声明两个定位权限，权限场景为 `EntryAbility` / `inuse`；使用自定义 Ability 的宿主需要自行配置使用场景和权限说明，缺少声明时抛出 `ERR_LOCATION_PERMISSION_REQUEST`。API 18 及以上还会检查系统返回的申请失败原因，原因非 0 时同样抛出该错误。

#### `Location.getProviderStatusAsync()`

返回 `Promise<LocationProviderStatus>`，`locationServicesEnabled` 为系统定位开关状态，`backgroundModeEnabled` 恒为 `false`。Android 专属的 `gpsAvailable`、`networkAvailable`、`passiveAvailable` 不返回。

#### `Location.hasServicesEnabledAsync()`

返回 `Promise<boolean>`，系统定位服务是否开启。设备没有定位能力时返回 `false`。

#### `Location.getCurrentPositionAsync(options)`

返回 `Promise<LocationObject>`，请求一次当前定位，10 秒超时。`options` 见 `LocationOptions`。

`accuracy` 为 `High` 及以上时按精度优先请求，否则按速度优先。未授予前台定位权限时抛出 `ERR_LOCATION_UNAUTHORIZED`，定位服务未开启时抛出 `ERR_LOCATION_SETTINGS_UNSATISFIED`。

#### `Location.getLastKnownPositionAsync(options)`

返回 `Promise<LocationObject | null>`，读取系统缓存的最近位置。`options` 见 `LocationLastKnownOptions`。

超过 `maxAge` 或精度低于 `requiredAccuracy` 时返回 `null`；系统没有缓存、定位服务不可用或已关闭时也返回 `null`。需要前台定位权限。

#### `Location.watchPositionAsync(options, callback, errorHandler)`

返回 `Promise<LocationSubscription>`，订阅位置更新。应用进入后台时暂停回调，回到前台后恢复；订阅期间系统定位开关关闭或权限被收回，会通过 `errorHandler` 报告，恢复后重新开始。离开页面时调用 `subscription.remove()` 释放，重复调用没有副作用。

API 18 及以上会监听本应用的前台定位权限变化，权限恢复后重新启动订阅；API 13–17 没有这个监听，要等回到前台或调用权限接口时才重新检查。

`options` 见 `LocationOptions`。`timeInterval` 与 `distanceInterval` 未指定时按 `accuracy` 取默认值，正数毫秒间隔向上取整到秒，显式传 `0` 表示不限间隔。

#### `Location.getHeadingAsync()`

返回 `Promise<LocationHeadingObject>`，获取当前方向。内部订阅方向并等待准确度足够或若干次更新后返回。设备没有方向传感器时拒绝。

#### `Location.watchHeadingAsync(callback, errorHandler)`

返回 `Promise<LocationSubscription>`，订阅方向变化，约每 200 毫秒回调一次。`accuracy` 取 0–3，对应系统传感器的无、低、中、高准确度。

`magHeading` 为磁北角度，范围 0–360，不需要定位权限。`trueHeading` 为真北角度，需要定位权限和可用位置，依赖定位结果计算，条件不满足时返回 `-1`。

#### `Location.geocodeAsync(address)`

返回 `Promise<LocationGeocodedLocation[]>`，把地址转换成坐标，每次最多一个结果。需要前台定位权限，且只在前台可用；系统地理编码能力不可用时抛出 `ERR_LOCATION_GEOCODER_UNAVAILABLE`。结果只含 `latitude` 和 `longitude`。

#### `Location.reverseGeocodeAsync(location)`

返回 `Promise<LocationGeocodedAddress[]>`，把坐标转换成地址，每次最多一个结果。权限和可用性要求与 `geocodeAsync()` 相同。`name` 和 `formattedAddress` 取系统的地点名称，时区等系统未提供的字段返回 `null`。

#### `Location.isBackgroundLocationAvailableAsync()`

返回 `Promise<boolean>`，恒为 `false`。

#### `Location.enableNetworkProviderAsync()`

返回 `Promise<void>`，Android 专属接口，HarmonyOS 上不执行任何操作，直接成功返回。

#### `Location.installWebGeolocationPolyfill()`

返回 `void`，把 `navigator.geolocation` 挂到全局对象上，供 React Native 与 Web 的定位写法调用。

> **未实现的内容**
>
> - `getBackgroundPermissionsAsync()`、`requestBackgroundPermissionsAsync()`：后台定位未支持，返回 `status: 'denied'`、`canAskAgain: false`。
> - `startLocationUpdatesAsync()`、`stopLocationUpdatesAsync()`、`hasStartedLocationUpdatesAsync()`：后台定位未支持。启动抛出 `ERR_LOCATION_BACKGROUND_UNAVAILABLE`，停止未注册任务抛出 `ERR_TASK_NOT_FOUND`，查询返回 `false`。
> - `startGeofencingAsync()`、`stopGeofencingAsync()`、`hasStartedGeofencingAsync()`：地理围栏未支持。启动抛出 `ERR_LOCATION_GEOFENCING_UNAVAILABLE`，停止未注册任务抛出 `ERR_TASK_NOT_FOUND`，查询返回 `false`。

### Types

#### `LocationObject`

| 属性        | 类型                   | 说明                 |
| ----------- | ---------------------- | -------------------- |
| `coords`    | `LocationObjectCoords` | 坐标详情             |
| `timestamp` | `number`               | 定位时间，毫秒时间戳 |

Android 专属的 `mocked` 不返回。

#### `LocationObjectCoords`

| 属性               | 类型             | 说明                                          |
| ------------------ | ---------------- | --------------------------------------------- |
| `latitude`         | `number`         | WGS-84 纬度                                   |
| `longitude`        | `number`         | WGS-84 经度                                   |
| `altitude`         | `number \| null` | 海拔，米                                      |
| `accuracy`         | `number \| null` | 水平精度，米                                  |
| `altitudeAccuracy` | `number \| null` | 垂直精度，米                                  |
| `heading`          | `number \| null` | 行进方向，度                                  |
| `speed`            | `number \| null` | 速度，米每秒                                  |

系统没有提供或数值非有限时返回 `null`；`accuracy`、`altitudeAccuracy`、`heading`、`speed` 为负时也返回 `null`，`altitude` 允许负值。

#### `LocationHeadingObject`

| 属性          | 类型     | 说明                            |
| ------------- | -------- | ------------------------------- |
| `magHeading`  | `number` | 磁北角度，0–360                 |
| `trueHeading` | `number` | 真北角度，0–360；不可用时为 `-1` |
| `accuracy`    | `number` | 校准等级 0–3                    |

#### `LocationGeocodedLocation`

只返回 `latitude` 和 `longitude`，可选的 `accuracy`、`altitude` 在 HarmonyOS 上不返回。

#### `LocationGeocodedAddress`

`city`、`district`、`street`、`streetNumber`、`region`、`subregion`、`country`、`postalCode`、`isoCountryCode`、`name`、`formattedAddress` 均为 `string | null`，取系统地址字段，未提供时为 `null`，其中 `name` 与 `formattedAddress` 都取地点名称。`timezone` 恒为 `null`。

#### `LocationOptions`

| 属性                        | 类型       | 说明                             |
| --------------------------- | ---------- | -------------------------------- |
| `accuracy`                  | `Accuracy` | 定位精度，默认 `Balanced`        |
| `timeInterval`              | `number`   | 更新间隔，毫秒                   |
| `distanceInterval`          | `number`   | 更新距离，米                     |

Android 专属的 `mayShowUserSettingsDialog` 在 HarmonyOS 上不生效。

`timeInterval` 与 `distanceInterval` 未指定时按 `accuracy` 取值：

| 精度                | 间隔    | 距离     |
| ------------------- | ------- | -------- |
| `Lowest`            | 10 秒   | 3000 米  |
| `Low`               | 5 秒    | 1000 米  |
| `Balanced`          | 3 秒    | 100 米   |
| `High`              | 2 秒    | 50 米    |
| `Highest`           | 1 秒    | 25 米    |
| `BestForNavigation` | 0.5 秒  | 0 米     |

#### `LocationLastKnownOptions`

| 属性               | 类型     | 说明                                 |
| ------------------ | -------- | ------------------------------------ |
| `maxAge`           | `number` | 位置超过该毫秒数视为无效             |
| `requiredAccuracy` | `number` | 精度超过该米数时返回 `null`          |

#### `LocationPermissionResponse`

继承 `PermissionResponse`，含 `status`、`granted`、`canAskAgain`、`expires`。Android 的 `android` 和 iOS 的 `ios` 字段在 HarmonyOS 上不返回。

#### `LocationProviderStatus`

| 属性                      | 类型      | 说明         |
| ------------------------- | --------- | ------------ |
| `locationServicesEnabled` | `boolean` | 系统定位开关 |
| `backgroundModeEnabled`   | `boolean` | 恒为 `false` |

Android 专属的 `gpsAvailable`、`networkAvailable`、`passiveAvailable` 不返回。

#### `LocationSubscription`

| 属性     | 类型         | 说明               |
| -------- | ------------ | ------------------ |
| `remove` | `() => void` | 停止订阅回调       |

#### `LocationCallback`、`LocationErrorCallback`、`LocationHeadingCallback`

回调类型，分别接收 `LocationObject`、错误原因字符串、`LocationHeadingObject`。

#### `PermissionResponse`

含 `status`、`granted`、`canAskAgain`、`expires`。

#### `PermissionExpiration`

`'never' | number`，当前所有权限永久有效。

#### `PermissionHookOptions`

`PermissionHookBehavior | Options`。

> **未实现的内容**
>
> - `LocationTaskOptions`、`LocationTaskServiceOptions`：后台定位选项，HarmonyOS 上没有使用场景。
> - `LocationRegion`：地理围栏区域，HarmonyOS 上没有使用场景。
> - `PermissionDetailsLocationAndroid`、`PermissionDetailsLocationIOS`：其他平台专属的权限详情，HarmonyOS 上不返回。

### Enums

#### `Accuracy`

| 成员                | 值  | 含义               |
| ------------------- | --- | ------------------ |
| `Lowest`            | 1   | 约 3 公里          |
| `Low`               | 2   | 约 1 公里          |
| `Balanced`          | 3   | 100 米以内         |
| `High`              | 4   | 10 米以内          |
| `Highest`           | 5   | 最高精度           |
| `BestForNavigation` | 6   | 导航级精度         |

#### `PermissionStatus`

| 成员           | 值               |
| -------------- | ---------------- |
| `DENIED`       | `'denied'`       |
| `GRANTED`      | `'granted'`      |
| `UNDETERMINED` | `'undetermined'` |

> **未实现的内容**
>
> - `ActivityType`：iOS 专属枚举，HarmonyOS 上没有取值来源。
> - `GeofencingEventType`、`GeofencingRegionState`：地理围栏未支持，没有取值来源。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
