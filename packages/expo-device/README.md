# @expo-harmony/expo-device

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-device) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/device/)

为 HarmonyOS 上的 React Native 应用提供 Expo Device 的原生实现，与官方同版本的 `expo-device` 配套使用。支持读取设备品牌、型号、系统版本、CPU 架构、总内存、设备类型和开机时长。

## 安装

```bash
npm install @expo-harmony/expo-device expo-device@55.0.17
```

鸿蒙适配会通过 Autolinking 自动接入，无需额外配置。最低支持 HarmonyOS 5.0.1（API 13），宿主的 `compatibleSdkVersion` 也需满足此要求。

业务代码依旧使用官方包：

```ts
import * as Device from 'expo-device';

console.log(Device.modelName, Device.totalMemory);
const type = await Device.getDeviceTypeAsync();
const uptime = await Device.getUptimeAsync();
```

## API 对照表

### Constants

#### `Device.isDevice`

类型：`boolean`

恒为 `true`。HarmonyOS 没有公开的模拟器检测接口，在模拟器上同样返回 `true`。

#### `Device.brand`

类型：`string | null`

设备品牌。取不到或为空时返回 `null`。

#### `Device.manufacturer`

类型：`string | null`

设备制造商。取不到或为空时返回 `null`。

#### `Device.modelName`

类型：`string | null`

面向用户的设备型号名称。优先取市场名称，没有时取产品型号。两者都为空时返回 `null`。

#### `Device.deviceType`

类型：`DeviceType | null`

设备类型，按系统上报的设备类型字符串映射：`default` 和 `phone` 对应 `PHONE`，`tablet` 对应 `TABLET`，`2in1` 对应 `DESKTOP`，`tv` 对应 `TV`，其余值对应 `UNKNOWN`。可穿戴、车机等类型归入 `UNKNOWN`。恒为有效枚举值，不会返回 `null`。

#### `Device.totalMemory`

类型：`number | null`

设备总内存，单位字节。读取失败或结果不是正安全整数时返回 `null`。

#### `Device.supportedCpuArchitectures`

类型：`string[] | null`

设备支持的处理器架构列表，取系统上报的架构清单并去掉空项。清单为空时返回 `null`。

#### `Device.osName`

类型：`string | null`

操作系统名称，取发行方提供的名称原值，不做解析。为空时返回 `null`。

#### `Device.osVersion`

类型：`string | null`

操作系统版本，取发行方提供的版本字符串原值，不做解析。为空时返回 `null`。

#### `Device.osBuildId`

类型：`string | null`

系统显示版本。为空时返回 `null`。

> **未实现的内容**
>
> - `Device.modelId`：iOS 专属字段，HarmonyOS 上没有内部型号 ID。
> - `Device.designName`：Android 专属字段，HarmonyOS 上没有对应值。
> - `Device.productName`：Android 专属字段，HarmonyOS 上没有对应值。
> - `Device.deviceYearClass`：设备年份分级，HarmonyOS 上没有该分级。
> - `Device.deviceName`：用户可编辑的设备名称，HarmonyOS 没有公开接口。
> - `Device.osInternalBuildId`：HarmonyOS 没有与官方语义一致的内部构建 ID。
> - `Device.osBuildFingerprint`：Android 专属字段，HarmonyOS 上没有构建指纹。
> - `Device.platformApiLevel`：Android 专属字段，HarmonyOS 的系统 API 版本语义不同。

### Methods

#### `Device.getDeviceTypeAsync()`

返回 `Promise<DeviceType>`，取值与 `Device.deviceType` 一致。

#### `Device.getUptimeAsync()`

返回 `Promise<number>`，自上次开机以来的毫秒数，不计入深度休眠，与官方在 Android 上的语义一致。读取失败或结果不是非负安全整数时抛出 `ERR_DEVICE_UPTIME`。

#### `Device.getPlatformFeaturesAsync()`

返回 `Promise<string[]>`，恒为空数组。官方标记为 Android 专属接口，HarmonyOS 上没有对应的平台特性清单。

#### `Device.hasPlatformFeatureAsync(feature)`

返回 `Promise<boolean>`，恒为 `false`。官方标记为 Android 专属接口，HarmonyOS 上没有对应的平台特性清单。

> **未实现的内容**
>
> - `Device.getMaxMemoryAsync()`：Android 上返回 Java 虚拟机的内存上限，HarmonyOS 上没有等价概念，调用抛出 `UnavailabilityError`。
> - `Device.isRootedExperimentalAsync()`：HarmonyOS 没有可靠的 root 检测接口，调用抛出 `UnavailabilityError`。
> - `Device.isSideLoadingEnabledAsync()`：HarmonyOS 没有对应的侧载查询接口，调用抛出 `UnavailabilityError`。

### Enums

#### `DeviceType`

| 成员      | 值  | 含义                     |
| --------- | --- | ------------------------ |
| `UNKNOWN` | `0` | 无法识别的设备类型       |
| `PHONE`   | `1` | 手机                     |
| `TABLET`  | `2` | 平板                     |
| `DESKTOP` | `3` | 桌面设备，对应 2in1 设备 |
| `TV`      | `4` | 电视                     |

### Error codes

#### `ERR_DEVICE_UPTIME`

`getUptimeAsync()` 读取失败或返回值不合法时抛出。

#### `ERR_DEVICE_ROOT_DETECTION`

只在 root 检测时抛出，HarmonyOS 上不会出现。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
