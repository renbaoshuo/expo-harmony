# @expo-harmony/expo-application

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-application) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/application/)

为 HarmonyOS 上的 React Native 应用提供 Expo Application 的原生实现，与官方同版本的 `expo-application` 配套使用。支持读取应用名称、应用 ID、原生版本、构建版本以及安装和最后更新时间。

## 安装

```bash
npm install @expo-harmony/expo-application expo-application@55.0.15
```

## API 对照表

### Constants

#### `Application.applicationId`

类型：`string | null`

应用包名。空值按 `null` 返回。

#### `Application.applicationName`

类型：`string | null`

应用显示名称，从应用的名称资源配置解析。名称配置为资源引用而非文本时返回 `null`。

API 20 起系统在部分查询接口上直接返回用户可见名称，本模块不受这一变更影响。

#### `Application.nativeApplicationVersion`

类型：`string | null`

商店展示版本。

#### `Application.nativeBuildVersion`

类型：`string | null`

内部构建版本，以字符串返回，与官方的类型一致。

### Methods

#### `Application.getInstallationTimeAsync()`

返回 `Promise<Date>`，安装时间。取值来源随 HarmonyOS SDK 版本变化：

- API 18 及以上使用首次安装时间，符合官方不计入后续更新的语义。预置应用返回固定的初始安装时间。
- API 13–17 没有首次安装时间，使用应用包的安装时间，覆盖安装后怎么取值由系统决定。

设备首次开机时若还没拿到系统时间，安装时间从 Unix 纪元开始计时，返回值会远小于真实安装时间。时间戳不合法时拒绝。

#### `Application.getLastUpdateTimeAsync()`

返回 `Promise<Date>`，应用包的最后更新时间。官方文档说的是 Google Play 的更新时间，这里与分发渠道无关。该方法是官方标记的 Android 专属接口，在 HarmonyOS 上可用。

> **未实现的内容**
>
> - `getAndroidId()`、`getInstallReferrerAsync()`：Android 专属接口，HarmonyOS 上调用抛出 `UnavailabilityError`。
> - `getIosApplicationReleaseTypeAsync()`、`getIosIdForVendorAsync()`、`getIosPushNotificationServiceEnvironmentAsync()`：iOS 专属接口，HarmonyOS 上调用抛出 `UnavailabilityError`。

### Types

> **未实现的内容**
>
> - `PushNotificationServiceEnvironment`：iOS 专属类型，HarmonyOS 上没有取值来源。

### Enums

> **未实现的内容**
>
> - `ApplicationReleaseType`：iOS 专属枚举，HarmonyOS 上没有取值来源。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
