# @expo-harmony/expo-device

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-device) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/device/)

为 HarmonyOS 上的 React Native 应用提供 Expo Device 的原生实现，与官方 `expo-device` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-device expo-device@~57.0.2
```

## API 对照表

### Constants

#### `Device.isDevice`

类型为 `boolean`。DevEco 模拟器的产品型号为 `emulator`，此时返回 `false`。

#### `Device.brand`

类型为 `string | null`，返回设备品牌；系统未提供时返回 `null`。

#### `Device.manufacturer`

类型为 `string | null`，返回设备制造商；系统未提供时返回 `null`。

#### `Device.modelName`

类型为 `string | null`，返回面向用户的设备型号名称。优先使用市场名称，其次使用产品型号；两者都未提供时返回 `null`。

#### `Device.modelId`

类型为 `string | null`，返回系统提供的产品型号标识；未提供时返回 `null`。

#### `Device.designName`

类型为 `string | null`，返回系统提供的硬件版本标识 `hardwareModel`。系统未提供时返回 `null`。

#### `Device.productName`

类型为 `string | null`，返回系统提供的内部产品系列标识 `productSeries`。系统未提供时返回 `null`。

#### `Device.deviceYearClass`

类型为 `number | null`，始终返回 `null`。

- HarmonyOS 不提供设备年份分级。

#### `Device.totalMemory`

类型为 `number | null`，返回设备总内存，单位为字节。读取失败或数值无效时返回 `null`。

#### `Device.deviceType`

根据系统报告的设备类型返回枚举值。`phone` 映射为 `PHONE`，`tablet` 映射为 `TABLET`，`2in1` 映射为 `DESKTOP`，`tv` 映射为 `TV`，其余值映射为 `UNKNOWN`。

#### `Device.supportedCpuArchitectures`

类型为 `string[] | null`，返回系统报告的处理器架构标识列表；列表为空时返回 `null`。

#### `Device.osName`

类型为 `string | null`，返回系统名称；系统未提供时返回 `null`。

#### `Device.osVersion`

类型为 `string | null`，返回系统版本；系统未提供时返回 `null`。

#### `Device.osBuildId`

类型为 `string | null`，返回系统显示版本；系统未提供时返回 `null`。

#### `Device.osInternalBuildId`

类型为 `string | null`。优先返回系统构建时生成的增量版本号。该值不可用时返回系统完整版本名称，两个字段均缺失时返回 `null`。

#### `Device.osBuildFingerprint`

类型为 `string | null`，返回系统提供的构建信息标识；系统未提供时返回 `null`。

#### `Device.platformApiLevel`

类型为 `number | null`，返回设备的系统软件 API 级别 `sdkApiVersion`。系统未提供有效级别时返回 `null`。 [华为设备信息接口](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-device-info/)

#### `Device.deviceName`

类型为 `string | null`，返回系统设置中的设备名称；系统未提供名称或读取受限时返回 `null`。

### Methods

#### `Device.getDeviceTypeAsync()`

无参数，返回 `Promise<DeviceType>`，结果与 `Device.deviceType` 相同。

#### `Device.getUptimeAsync()`

无参数，返回 `Promise<number>`，表示自上次开机以来的毫秒数，不计入深度休眠。读取失败或结果无效时以 `ERR_DEVICE_UPTIME` 拒绝。

#### `Device.getPlatformFeaturesAsync()`

无参数，返回 `Promise<string[]>`。

- HarmonyOS 不提供平台特性列表，因此始终返回空数组。

#### `Device.hasPlatformFeatureAsync(feature)`

参数 `feature: string`，返回 `Promise<boolean>`。

- 传入具体的 HarmonyOS 系统能力名称，如 `SystemCapability.Location.Location.Core`，可查询设备是否支持此能力。 [华为 SysCap API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-syscap)

#### `Device.getMaxMemoryAsync()`

无参数，返回 `Promise<number>`。

- 返回当前 ArkTS VM 的堆内存上限，单位为字节。读取失败或结果无效时以 `ERR_DEVICE_MAX_MEMORY` 拒绝。 [华为 HiDebug 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hidebug-guidelines/)

#### `Device.isRootedExperimentalAsync()`

无参数，返回 `Promise<boolean>`。

- HarmonyOS 不提供可靠的 root 状态查询；调用时以 `UnavailabilityError` 拒绝。

#### `Device.isSideLoadingEnabledAsync()`

无参数，返回 `Promise<boolean>`。

- HarmonyOS 不提供侧载状态查询；调用时以 `UnavailabilityError` 拒绝。

### Enums

#### `DeviceType`

- `UNKNOWN = 0`：无法识别的设备类型。
- `PHONE = 1`：手机。
- `TABLET = 2`：平板。
- `DESKTOP = 3`：二合一设备。
- `TV = 4`：电视。

### Error codes

#### `ERR_DEVICE_UPTIME`

`Device.getUptimeAsync()` 读取失败或返回值无效时抛出。

#### `ERR_DEVICE_MAX_MEMORY`

`Device.getMaxMemoryAsync()` 读取失败或返回值无效时抛出。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
