# @expo-harmony/expo-application

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-application) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/application/)

为 HarmonyOS 上的 React Native 应用提供 Expo Application 的原生实现，与官方 `expo-application` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-application expo-application@~57.0.3
```

## API 对照表

### Constants

#### `Application.applicationId`

类型：`string | null`

HarmonyOS 应用包名。无法读取或值为空时返回 `null`。

#### `Application.applicationName`

类型：`string | null`

HarmonyOS 应用显示名称。系统无法解析名称时返回 `null`。

#### `Application.nativeApplicationVersion`

类型：`string | null`

HarmonyOS 应用版本号。系统未提供非空版本号时返回 `null`。

#### `Application.nativeBuildVersion`

类型：`string | null`

HarmonyOS 应用构建版本号，以字符串返回。系统未提供有效版本号时返回 `null`。

### Methods

#### `Application.getInstallationTimeAsync()`

参数：无。

返回：`Promise<Date>`，应用安装时间。

- HarmonyOS SDK API 18 及以上使用系统提供的首次安装时间；系统未提供时使用应用包安装时间。覆盖更新通常不会改变首次安装时间。
- HarmonyOS SDK API 13–17 使用应用包安装时间；覆盖更新后该时间是否变化由系统决定。
- 系统尚未同步准确时间时，返回的时间可能早于实际安装时间。

系统无法提供有效时间戳时，Promise 会以 `ERR_APPLICATION_INSTALLATION_TIME` 拒绝。

#### `Application.getLastUpdateTimeAsync()`

参数：无。

返回：`Promise<Date>`，应用包最近更新时间。

系统无法提供有效时间戳时，Promise 会以 `ERR_APPLICATION_LAST_UPDATE_TIME` 拒绝。

#### `Application.getAndroidId()`

参数：无。

- HarmonyOS 不提供此 API 所需的设备标识。

#### `Application.getInstallReferrerAsync()`

参数：无。

- HarmonyOS 不提供此 API 所需的安装来源信息。

#### `Application.getIosApplicationReleaseTypeAsync()`

参数：无。

- HarmonyOS 没有此 API 对应的应用发行类型。

#### `Application.getIosIdForVendorAsync()`

参数：无。

- HarmonyOS 不提供此 API 对应的 vendor 标识。

#### `Application.getIosPushNotificationServiceEnvironmentAsync()`

参数：无。

- HarmonyOS 不提供此 API 对应的推送服务环境信息。

### Types

#### `PushNotificationServiceEnvironment`

- HarmonyOS 上没有接口返回此类型的值，系统不提供对应的推送服务环境信息。

### Enums

#### `ApplicationReleaseType`

- HarmonyOS 上没有接口返回此枚举值，系统没有对应的应用发行类别。

### Error codes

| 错误码 | 触发条件 |
| --- | --- |
| `ERR_APPLICATION_INSTALLATION_TIME` | 无法读取应用包信息，或系统返回的安装时间戳无效。 |
| `ERR_APPLICATION_LAST_UPDATE_TIME` | 无法读取应用包信息，或系统返回的更新时间戳无效。 |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
