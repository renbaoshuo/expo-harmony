# @expo-harmony/expo-location

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-location) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/location/)

为 HarmonyOS 上的 React Native 应用提供 Expo Location 的原生实现，与官方同版本的 `expo-location` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-location expo-location
```

## API 对照表

### Hooks

#### `Location.useForegroundPermissions(options?)`

返回 `[permissionResponse, requestPermission, getPermission]`。`permissionResponse` 初次读取完成前为 `null`；其余响应与对应的前台权限方法一致。`options` 类型为 `PermissionHookOptions`。

#### `Location.useBackgroundPermissions(options?)`

返回后台定位权限响应、申请函数和读取函数。`permissionResponse` 初次读取完成前为 `null`；`options` 类型为 `PermissionHookOptions`。后台能力未启用或未获得“始终允许”权限时，响应为 `denied`。

#### `Location.useMotionActivityPermissions(options?)`

- HarmonyOS 不提供运动状态识别权限。读取和申请均返回 `status: 'denied'`、`granted: false`、`canAskAgain: false`、`expires: 'never'`。

### Constants

#### `Location.EventEmitter`

事件发射器。通过 `addListener(eventName, listener)` 订阅事件，返回可调用 `remove()` 的订阅对象；事件名和载荷见“Event subscriptions”。

### Methods

#### `Location.getProviderStatusAsync()`

返回 `Promise<LocationProviderStatus>`。`locationServicesEnabled` 表示系统定位服务是否开启；`backgroundModeEnabled` 表示后台定位能力已配置、设备支持且系统定位服务已开启。

#### `Location.hasServicesEnabledAsync()`

返回 `Promise<boolean>`，表示系统定位服务是否开启。设备不支持定位或系统查询失败时返回 `false`。

#### `Location.getCurrentPositionAsync(options?)`

返回 `Promise<LocationObject>`。当 `timeInterval` 大于 `0` 时，先读取不超过该毫秒数的系统缓存；省略时按 `accuracy` 使用默认间隔，显式传 `0` 会跳过缓存。没有符合条件的缓存时请求新位置，最长等待 10 秒。`distanceInterval` 不影响单次定位。`options` 类型为 `LocationOptions`。

请求新位置时，`High` 及以上使用精度优先，其余精度使用速度优先。未获前台定位权限时抛出 `ERR_LOCATION_UNAUTHORIZED`；定位服务关闭或不可用时抛出 `ERR_LOCATION_SETTINGS_UNSATISFIED`。

#### `Location.getLastKnownPositionAsync(options?)`

返回 `Promise<LocationObject | null>`，读取系统缓存的最近位置。`options` 类型为 `LocationLastKnownOptions`。超过 `maxAge`，或精度缺失、大于 `requiredAccuracy` 时返回 `null`；系统无缓存、定位服务不可用或已关闭时也返回 `null`。需要前台定位权限。

#### `Location.watchPositionAsync(options, callback, errorHandler?)`

返回 `Promise<LocationSubscription>`，订阅前台位置更新。应用进入后台时暂停回调，回到前台后恢复；定位服务关闭或权限被收回时通过 `errorHandler` 报告原因，条件恢复后继续更新。调用订阅对象的 `remove()` 可停止回调。

`options` 类型为 `LocationOptions`。`timeInterval` 和 `distanceInterval` 省略时按 `accuracy` 采用默认值；正数时间间隔向上取整到秒，显式传 `0` 不设时间间隔限制，实际频率仍由系统决定。HarmonyOS 不提供平衡功耗的精度档：`Lowest` 使用低功耗请求，其余档位使用高精度请求。API 18 及以上可在权限恢复后自动恢复订阅；API 13–17 需要应用回到前台或再次查询权限后重新检查。

#### `Location.getHeadingAsync()`

返回 `Promise<LocationHeadingObject>`，等待方向准确度足够或收到若干次更新后返回，并停止本次订阅。需要前台定位权限；设备没有方向传感器时拒绝。系统定位服务关闭时仍可获取磁北，真北为 `-1`。

#### `Location.watchHeadingAsync(callback, errorHandler?)`

返回 `Promise<LocationSubscription>`，订阅方向变化。回调中的 `accuracy` 为 `0` 到 `3`，对应无、低、中、高准确度；`magHeading` 为 [0, 360) 范围内的磁北角度，`trueHeading` 为真北角度，不可计算时为 `-1`。

订阅需要前台定位权限。权限被收回时通过 `errorHandler` 报告原因并暂停更新，条件恢复后继续订阅。系统定位服务关闭时磁北仍更新，真北为 `-1`；服务恢复后重新计算真北。

#### `Location.getMotionActivityAsync()`

- HarmonyOS 不提供运动状态识别；调用会以 `ERR_MOTION_ACTIVITY_UNAVAILABLE` 拒绝。

#### `Location.watchMotionActivityAsync(callback, errorHandler?)`

- HarmonyOS 不提供运动状态识别；调用会以 `ERR_MOTION_ACTIVITY_UNAVAILABLE` 拒绝，且不会建立订阅。

#### `Location.geocodeAsync(address)`

返回 `Promise<LocationGeocodedLocation[]>`，把地址转换成坐标，每次最多返回一个结果。需要前台定位权限并在应用前台调用；系统不支持地理编码时抛出 `ERR_LOCATION_GEOCODER_UNAVAILABLE`。结果包含 `latitude` 和 `longitude`。

#### `Location.reverseGeocodeAsync(location)`

返回 `Promise<LocationGeocodedAddress[]>`，把坐标转换成地址，每次最多返回一个结果；权限及前台要求与 `geocodeAsync()` 相同。系统没有独立地标名称或时区，`name` 和 `timezone` 始终为 `null`；`formattedAddress` 为系统提供的详细地址。系统没有匹配结果时返回空数组。

#### `Location.isBackgroundLocationAvailableAsync()`

返回 `Promise<boolean>`，与 `getProviderStatusAsync()` 的 `backgroundModeEnabled` 值一致。

#### `Location.enableNetworkProviderAsync()`

- HarmonyOS 不提供此方法对应的网络定位开关操作，因此调用不执行操作并直接完成。

#### `Location.installWebGeolocationPolyfill()`

返回 `void`，在全局 `navigator.geolocation` 上提供 `getCurrentPosition()`、`watchPosition()` 和 `clearWatch()`。`getCurrentPosition()` 会先申请前台定位权限。

#### `Location.startLocationUpdatesAsync(taskName, options?)`

返回 `Promise<void>`，注册后台位置更新任务；任务收到 `{ locations }`，其中 `locations` 是位置对象数组。`options` 类型为 `LocationTaskOptions`，省略时使用 `accuracy: Balanced`。

要求后台定位能力已启用，HarmonyOS SDK API 21 及以上且设备支持持续定位；启动时应用须在前台，并已授予前台定位和“始终允许”权限。运行时系统显示持续任务通知；用户从通知停止任务后，更新会停止，再次启动可恢复。应用进程终止时当前持续任务停止，应用重新打开后仍有效的任务注册可恢复。

后台更新可用 `deferredUpdatesDistance`、`deferredUpdatesInterval` 和 `deferredUpdatesTimeout` 延后或批量投递。停止应用进程不会清除任务注册。能力未启用或设备不支持时抛出 `ERR_LOCATION_BACKGROUND_UNAVAILABLE`；权限不足时抛出 `ERR_LOCATION_BACKGROUND_UNAUTHORIZED`。

#### `Location.stopLocationUpdatesAsync(taskName)`

返回 `Promise<void>`，停止指定的后台位置更新任务。任务未注册时抛出 `ERR_TASK_NOT_FOUND`。

#### `Location.hasStartedLocationUpdatesAsync(taskName)`

返回 `Promise<boolean>`，查询指定后台位置更新任务是否已注册。

#### `Location.startGeofencingAsync(taskName, regions)`

返回 `Promise<void>`，为指定任务注册圆形 GNSS 地理围栏。设备进入或离开围栏时，任务收到 `{ eventType, region }`；`eventType` 和 `region.state` 的值见对应枚举。`regions` 类型为 `LocationRegion[]`，不能为空。

要求地理围栏能力已启用，HarmonyOS SDK API 23 及以上、设备支持 WGS-84 GNSS 围栏，并已授予前台、精确和“始终允许”定位权限。系统最多支持每个应用 100 个围栏；单个围栏有效期为一年，应用重新打开后会恢复已注册围栏。应用进程退出时发生的事件会在应用回到前台时投递，且只保留仍在一分钟有效期内的事件。能力未启用或设备不支持时抛出 `ERR_LOCATION_GEOFENCING_UNAVAILABLE`；权限不足时抛出 `ERR_LOCATION_BACKGROUND_UNAUTHORIZED`。

#### `Location.stopGeofencingAsync(taskName)`

返回 `Promise<void>`，停止指定任务的地理围栏。任务未注册时抛出 `ERR_TASK_NOT_FOUND`。

#### `Location.hasStartedGeofencingAsync(taskName)`

返回 `Promise<boolean>`，查询指定地理围栏任务是否已注册。

### Event subscriptions

#### `Expo.locationChanged`

通过 `Location.EventEmitter.addListener()` 订阅位置变化事件。事件载荷包含 `watchId` 和 `location`；`location` 类型为 `LocationObject`。

#### `Expo.headingChanged`

通过 `Location.EventEmitter.addListener()` 订阅方向变化事件。事件载荷包含 `watchId` 和 `heading`；`heading` 类型为 `LocationHeadingObject`。

#### `Expo.locationError`

通过 `Location.EventEmitter.addListener()` 订阅位置或方向订阅错误。事件载荷包含 `watchId` 和错误原因字符串 `reason`。

#### `Expo.motionActivityChanged`

- HarmonyOS 不提供运动状态识别，因此不会触发此事件。

### Types

#### `LocationObject`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `coords` | `LocationObjectCoords` | 坐标详情 |
| `timestamp` | `number` | 定位时间，毫秒时间戳 |

- HarmonyOS 不提供 `mocked` 字段。

#### `LocationObjectCoords`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `latitude` | `number` | WGS-84 纬度 |
| `longitude` | `number` | WGS-84 经度 |
| `altitude` | `number \| null` | 海拔，米 |
| `accuracy` | `number \| null` | 水平精度，米 |
| `altitudeAccuracy` | `number \| null` | 垂直精度，米 |
| `heading` | `number \| null` | 行进方向，度 |
| `speed` | `number \| null` | 速度，米每秒 |

系统未提供或返回非有限数值时为 `null`；`accuracy`、`altitudeAccuracy`、`heading` 和 `speed` 为负数时也为 `null`，`altitude` 可以为负数。

#### `LocationHeadingObject`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `magHeading` | `number` | [0, 360) 范围内的磁北角度 |
| `trueHeading` | `number` | 真北角度；不可用时为 `-1` |
| `accuracy` | `number` | 方向准确度，范围为 0–3 |

#### `LocationGeocodedLocation`

包含 `latitude` 和 `longitude`。

- HarmonyOS 不返回可选的 `accuracy`、`altitude`。

#### `LocationGeocodedAddress`

包含 `city`、`district`、`street`、`streetNumber`、`region`、`subregion`、`country`、`postalCode`、`isoCountryCode`、`name`、`formattedAddress`、`timezone`，字段类型均为 `string | null`。系统未提供的地址字段为 `null`；`name` 和 `timezone` 始终为 `null`。

#### `LocationProviderStatus`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `locationServicesEnabled` | `boolean` | 系统定位服务是否开启 |
| `backgroundModeEnabled` | `boolean` | 后台定位能力是否已配置、受支持且系统定位服务已开启 |

- HarmonyOS 不提供 `gpsAvailable`、`networkAvailable`、`passiveAvailable` 状态。

#### `LocationSubscription`

包含 `remove: () => void`，用于停止位置或方向订阅；重复调用不会产生额外效果。

#### `LocationOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `accuracy` | `Accuracy` | 定位精度，默认 `Balanced` |
| `timeInterval` | `number` | 更新时间间隔，毫秒 |
| `distanceInterval` | `number` | 最小更新距离，米 |
| `mayShowUserSettingsDialog` | `boolean` | 是否显示定位设置弹窗 |

- HarmonyOS 没有对应的系统设置弹窗，传入 `mayShowUserSettingsDialog` 不生效。

`timeInterval` 和 `distanceInterval` 省略时按精度使用下表默认值。时间间隔传给系统时按秒向上取整。

| 精度 | 时间间隔 | 距离 |
| --- | ---: | ---: |
| `Lowest` | 10 秒 | 3000 米 |
| `Low` | 5 秒 | 1000 米 |
| `Balanced` | 3 秒 | 100 米 |
| `High` | 2 秒 | 50 米 |
| `Highest` | 1 秒 | 25 米 |
| `BestForNavigation` | 0.5 秒 | 0 米 |

#### `LocationLastKnownOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `maxAge` | `number` | 位置超过该毫秒数时视为无效 |
| `requiredAccuracy` | `number` | 精度大于该米数时返回 `null` |

#### `LocationTaskOptions`

继承 `LocationOptions`，另含 `deferredUpdatesDistance`（米）、`deferredUpdatesInterval`（毫秒）和 `deferredUpdatesTimeout`（毫秒），用于控制后台位置的批量投递。

- HarmonyOS 不使用 `activityType`、`showsBackgroundLocationIndicator` 或 `pausesUpdatesAutomatically`。

#### `LocationTaskServiceOptions`

包含通知标题 `notificationTitle`、正文 `notificationBody`、颜色 `notificationColor` 和停止应用时销毁服务的选项 `killServiceOnDestroy`。

- HarmonyOS 持续任务通知由系统管理，不支持通过此类型自定义通知。

#### `LocationRegion`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `identifier` | `string` | 围栏标识；省略时自动生成 |
| `latitude` | `number` | 圆心纬度 |
| `longitude` | `number` | 圆心经度 |
| `radius` | `number` | 半径，米，必须大于 0 |
| `notifyOnEnter` | `boolean` | 是否通知进入，默认 `true` |
| `notifyOnExit` | `boolean` | 是否通知离开，默认 `true` |
| `state` | `GeofencingRegionState` | 进入或离开事件中的围栏状态 |

坐标使用 WGS-84。`notifyOnEnter` 和 `notifyOnExit` 不能同时为 `false`；HarmonyOS 仅在围栏事件结果中返回 `state`。

#### `LocationCallback`

回调接收一个 `LocationObject`。

#### `LocationErrorCallback`

回调接收一个错误原因字符串。

#### `LocationHeadingCallback`

回调接收一个 `LocationHeadingObject`。

#### `LocationPermissionResponse`

继承 `PermissionResponse`，包含 `status`、`granted`、`canAskAgain` 和 `expires`。

#### `PermissionResponse`

包含 `status`、`granted`、`canAskAgain` 和 `expires`。本包返回的 `expires` 始终为 `'never'`。

#### `PermissionExpiration`

类型为 `'never' | number`。HarmonyOS 定位权限响应固定为 `'never'`。

#### `PermissionHookOptions`

权限 Hook 的选项类型，为 `PermissionHookBehavior | Options`。

#### `MotionActivityObject`

包含运动状态集合 `activities` 和采样时间 `timestamp`。

- HarmonyOS 不提供运动状态识别，因此不会返回此类型的数据。

#### `MotionActivityState`

包含 `detected` 布尔值和 `confidence` 置信度。

- HarmonyOS 不提供运动状态识别，因此不会返回此类型的数据。

#### `MotionActivityCallback`

回调接收一个 `MotionActivityObject`。

- HarmonyOS 不提供运动状态识别，因此不会调用此回调。

### Enums

#### `Accuracy`

| 成员 | 值 | 含义 |
| --- | ---: | --- |
| `Lowest` | `1` | 低功耗，默认更新间隔 10 秒、距离 3000 米 |
| `Low` | `2` | 默认更新间隔 5 秒、距离 1000 米 |
| `Balanced` | `3` | 默认更新间隔 3 秒、距离 100 米 |
| `High` | `4` | 默认更新间隔 2 秒、距离 50 米 |
| `Highest` | `5` | 默认更新间隔 1 秒、距离 25 米 |
| `BestForNavigation` | `6` | 默认更新间隔 0.5 秒、距离 0 米 |

这些默认值是位置请求的时间和距离参数，不保证实际更新精度或频率。

#### `ActivityType`

| 成员 | 值 |
| --- | ---: |
| `Other` | `1` |
| `AutomotiveNavigation` | `2` |
| `Fitness` | `3` |
| `OtherNavigation` | `4` |
| `Airborne` | `5` |

- HarmonyOS 后台定位不按活动类型调整，传入值不生效。

#### `GeofencingEventType`

| 成员 | 值 | 含义 |
| --- | ---: | --- |
| `Enter` | `1` | 进入围栏 |
| `Exit` | `2` | 离开围栏 |

#### `GeofencingRegionState`

| 成员 | 值 | 含义 |
| --- | ---: | --- |
| `Unknown` | `0` | 状态未知 |
| `Inside` | `1` | 位于围栏内 |
| `Outside` | `2` | 位于围栏外 |

- HarmonyOS 的围栏事件只返回 `Inside` 或 `Outside`。

#### `MotionActivityType`

| 成员 | 值 |
| --- | --- |
| `Automotive` | `'automotive'` |
| `Cycling` | `'cycling'` |
| `Running` | `'running'` |
| `Walking` | `'walking'` |
| `Stationary` | `'stationary'` |
| `Unknown` | `'unknown'` |

- HarmonyOS 不提供运动状态识别，因此不会返回这些值。

#### `MotionActivityConfidence`

包含 `Low`（`0`）、`Medium`（`1`）和 `High`（`2`）。

- HarmonyOS 不提供运动状态识别，因此不会返回这些值。

#### `PermissionStatus`

包含 `DENIED`（`'denied'`）、`GRANTED`（`'granted'`）和 `UNDETERMINED`（`'undetermined'`）。

### Error codes

#### `ERR_LOCATION_INVALID_ARGUMENT`

选项、任务名、坐标或围栏参数不符合要求时抛出。

#### `ERR_LOCATION_INVALID_RESPONSE`

HarmonyOS 定位或地理编码服务返回无效坐标或时间戳时抛出。

#### `ERR_LOCATION_UNAUTHORIZED`

单次或持续前台定位没有前台定位权限时抛出。

#### `ERR_LOCATION_SETTINGS_UNSATISFIED`

请求位置时系统定位服务已关闭或不可用时抛出。

#### `ERR_LOCATION_UNAVAILABLE`

定位服务以其他错误原因拒绝单次定位请求时抛出。

#### `ERR_LOCATION_PERMISSION_REQUEST`

系统权限请求返回无效结果，或无法打开后台定位权限设置页时抛出。

#### `ERR_LOCATION_WATCH`

HarmonyOS 无法启动位置订阅时抛出。

#### `ERR_LOCATION_HEADING`

方向订阅失败或设备没有可用的方向传感器时抛出。

#### `ERR_LOCATION_GEOCODER_UNAVAILABLE`

设备不支持 HarmonyOS 地理编码能力时抛出。

#### `ERR_LOCATION_GEOCODING`

地理编码或逆地理编码请求失败，或在应用后台调用时抛出。

#### `ERR_LOCATION_BACKGROUND_UNAVAILABLE`

后台连续定位未启用、系统 SDK 低于 API 21 或设备不支持持续定位时抛出。

#### `ERR_LOCATION_GEOFENCING_UNAVAILABLE`

地理围栏未启用、系统 SDK 低于 API 23、设备不支持 GNSS 围栏或已注册围栏数量超出系统限制时抛出。

#### `ERR_LOCATION_BACKGROUND_UNAUTHORIZED`

后台位置任务未获得所需的前台和“始终允许”权限；地理围栏还需要精确定位权限。

#### `ERR_LOCATION_BACKGROUND_NOT_FOREGROUND`

启动后台位置或地理围栏任务时，应用不在前台时抛出。

#### `ERR_LOCATION_BACKGROUND_STOP`

系统无法停止后台连续定位任务时抛出。

#### `ERR_LOCATION_GEOFENCING_STOP`

系统无法移除地理围栏时抛出。

#### `ERR_LOCATION_GEOFENCING_STORAGE`

系统地理围栏注册信息无法保存时抛出。

#### `ERR_TASK_NOT_FOUND`

停止未注册的后台位置或地理围栏任务时抛出。

#### `ERR_MOTION_ACTIVITY_UNAVAILABLE`

调用运动状态读取或订阅方法时抛出；HarmonyOS 不提供运动状态识别。

### Permissions

#### `Location.getForegroundPermissionsAsync()`

返回 `Promise<LocationPermissionResponse>`，查询前台定位权限。模糊定位权限获准后即可使用前台定位；精确定位权限不是前台定位的必需条件。`expires` 始终为 `'never'`。

HarmonyOS SDK API 20 及以上可直接读取系统权限状态；API 13–19 无法直接读取系统记录的拒绝状态，未授权时根据本应用此前的明确拒绝记录返回 `denied` 或 `undetermined`。

#### `Location.requestForegroundPermissionsAsync()`

返回 `Promise<LocationPermissionResponse>`，申请前台定位权限，同时申请模糊和精确定位权限。默认模块配置已声明所需权限；使用自定义 Ability 时，需为该 Ability 声明权限和 `inuse` 使用场景。API 18 及以上，权限未声明或系统返回无效结果时抛出 `ERR_LOCATION_PERMISSION_REQUEST`。未授权时返回 `denied`；系统不再显示权限弹窗或要求前往设置时，`canAskAgain` 为 `false`。

#### `Location.getBackgroundPermissionsAsync()`

返回 `Promise<PermissionResponse>`。只有前台定位和 HarmonyOS“始终允许”后台定位权限均已授权，且后台能力已启用时才返回 `granted`；否则返回 `denied`。`expires` 始终为 `'never'`。

#### `Location.requestBackgroundPermissionsAsync()`

返回 `Promise<PermissionResponse>`。API 22 及以上可打开系统后台定位权限设置页；同一时刻的重复申请共用一次设置交互。系统要求用户手动进入设置时返回 `denied` 和 `canAskAgain: false`。API 13–21 或后台位置、地理围栏能力均未启用时返回当前权限状态，不打开设置页。

#### `Location.getMotionActivityPermissionsAsync()`

- HarmonyOS 不提供运动状态识别权限；读取返回 `status: 'denied'`、`granted: false`、`canAskAgain: false`、`expires: 'never'`。

#### `Location.requestMotionActivityPermissionsAsync()`

- HarmonyOS 不提供运动状态识别权限；申请不显示权限弹窗，并返回 `status: 'denied'`、`granted: false`、`canAskAgain: false`、`expires: 'never'`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
