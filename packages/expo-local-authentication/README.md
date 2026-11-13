# @expo-harmony/expo-local-authentication

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-local-authentication) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/local-authentication/)

为 HarmonyOS 上的 React Native 应用提供 Expo LocalAuthentication 的原生实现，与官方 `expo-local-authentication` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-local-authentication expo-local-authentication@~57.0.3
```

## API 对照表

### Methods

#### `LocalAuthentication.hasHardwareAsync()`

返回 `Promise<boolean>`。设备支持指纹或人脸认证时返回 `true`，否则返回 `false`。此查询不要求已录入凭据；设备临时锁定也不改变硬件支持结果。

#### `LocalAuthentication.supportedAuthenticationTypesAsync()`

返回 `Promise<AuthenticationType[]>`，列出设备支持的生物认证方式。指纹为 `FINGERPRINT`（1），人脸为 `FACIAL_RECOGNITION`（2）；设备均不支持时返回空数组。支持方式的判断不要求已录入凭据。

#### `LocalAuthentication.isEnrolledAsync()`

返回 `Promise<boolean>`。至少录入一种达到 ATL2 等级的指纹或人脸时返回 `true`；暂时锁定的生物凭据仍计为已录入。锁屏密码不计入此结果。

#### `LocalAuthentication.getEnrolledLevelAsync()`

返回 `Promise<SecurityLevel>`，表示设备当前已录入凭据的最高等级：有 ATL3 生物凭据时返回 `BIOMETRIC_STRONG`，否则有 ATL2 生物凭据时返回 `BIOMETRIC_WEAK`；未录入生物凭据但已配置锁屏密码时返回 `SECRET`，都没有时返回 `NONE`。暂时锁定的生物凭据仍计入等级；已过期的锁屏密码仍返回 `SECRET`。

#### `LocalAuthentication.authenticateAsync(options)`

`options` 可省略，返回 `Promise<LocalAuthenticationResult>`。验证成功时返回 `{ success: true }`；未通过或取消时返回 `{ success: false, error }`。

认证需要在应用前台发起；上下文无效或应用不在前台时返回 `invalid_context`。同一时间已有认证界面时，新请求返回 `app_cancel`，现有认证仍可继续。发起认证的界面销毁时，未完成的请求返回 `app_cancel`。

系统负责凭据校验、失败重试和临时锁定。取消认证时，HarmonyOS 不区分用户取消和系统取消，两者均返回 `user_cancel`。其他返回错误及抛出的异常码见 [`LocalAuthenticationError`](#localauthenticationerror)、[`ERR_LOCAL_AUTHENTICATION_INVALID_ARGUMENT`](#err_local_authentication_invalid_argument) 和 [`ERR_LOCAL_AUTHENTICATION_UNAVAILABLE`](#err_local_authentication_unavailable)。

HarmonyOS 上的认证界面与生物识别选择方式受 `biometricsSecurityLevel`、锁屏密码状态和系统 API 版本影响，详见 [`LocalAuthenticationOptions`](#localauthenticationoptions)。

#### `LocalAuthentication.cancelAuthenticate()`

返回 `Promise<void>`，取消正在进行的认证；对应认证请求返回 `user_cancel`。没有进行中的请求时不做任何操作，可以重复调用。

### Types

#### `LocalAuthenticationOptions`

`authenticateAsync()` 的可选参数。HarmonyOS 支持以下属性：

| 属性 | 说明 |
| --- | --- |
| `promptMessage` | 认证界面标题，默认 `Authenticate`，长度为 1–500 个字符。 |
| `cancelLabel` | 仅在不使用锁屏密码时，作为认证界面的导航按钮文字，默认 `Cancel`，最多 60 个字符；点击后返回 `user_cancel`。使用锁屏密码时由系统提供按钮。 |
| `disableDeviceFallback` | 默认 `false`，允许使用已配置的锁屏密码；设为 `true` 时只使用生物认证。允许回退且没有已录入的生物凭据时，可直接使用锁屏密码。 |
| `biometricsSecurityLevel` | 默认 `'weak'`，要求 ATL2；`'strong'` 要求 ATL3。要求 ATL3 时不会降级为 ATL2；允许回退时仍可使用锁屏密码。 |

当锁屏密码不可用或被禁用，并且指纹和人脸均已录入且达到要求的等级时，API 18 及以上可在同一认证界面提供两种方式；API 13–17 一次提供一种，均可用时优先指纹。若 `cancelLabel` 为空，也只提供一种生物认证方式。

HarmonyOS 认证界面不支持以下选项：

- `promptSubtitle`：认证界面没有对应的展示位置。
- `promptDescription`：认证界面没有对应的展示位置。
- `requireConfirmation`：是否需要验证后确认由系统决定。
- `fallbackLabel`：界面没有单独的回退按钮；可用 `disableDeviceFallback` 禁用锁屏密码回退。

#### `LocalAuthenticationResult`

成功结果为 `{ success: true }`。失败结果为 `{ success: false, error }`，其中 `error` 是 [`LocalAuthenticationError`](#localauthenticationerror) 的取值。`error` 为 `unknown` 时还会有 `warning` 字段，其中包含 HarmonyOS 返回的结果码。

#### `BiometricsSecurityLevel`

`'weak'` 或 `'strong'`，用于 `LocalAuthenticationOptions.biometricsSecurityLevel`。`'weak'` 对应 ATL2，`'strong'` 对应 ATL3。

### Enums

#### `AuthenticationType`

| 值 | 说明 |
| --- | --- |
| `FINGERPRINT`（1） | 指纹认证。 |
| `FACIAL_RECOGNITION`（2） | 人脸认证。 |

`supportedAuthenticationTypesAsync()` 不会返回以下方式：

- `IRIS`（3）：HarmonyOS 不提供虹膜认证。

#### `SecurityLevel`

`getEnrolledLevelAsync()` 的返回值：

| 值 | 说明 |
| --- | --- |
| `NONE`（0） | 没有已录入的认证凭据。 |
| `SECRET`（1） | 已配置锁屏密码。 |
| `BIOMETRIC_WEAK`（2） | 已录入 ATL2 等级的指纹或人脸。 |
| `BIOMETRIC_STRONG`（3） | 已录入 ATL3 等级的指纹或人脸。 |

### Error codes

#### `LocalAuthenticationError`

认证失败结果中 `error` 字段的取值：

| 值 | HarmonyOS 上的含义 |
| --- | --- |
| `authentication_failed` | 生物认证未通过。 |
| `user_cancel` | 用户取消、系统取消或调用 `cancelAuthenticate()`。 |
| `app_cancel` | 认证界面所属应用上下文销毁，或已有认证界面时发起了新请求。 |
| `timeout` | 认证超时。 |
| `lockout` | 认证方式被系统临时锁定。 |
| `not_enrolled` | 没有符合请求条件的已录入凭据。 |
| `not_available` | 请求条件下没有可用的认证方式，例如锁屏密码已过期。 |
| `unable_to_process` | 认证服务繁忙或发生一般错误。 |
| `invalid_context` | 应用不在前台，或认证上下文不可用。 |
| `unknown` | 没有对应映射的系统结果；结果同时附带 `warning`，其中包含 HarmonyOS 结果码。 |

HarmonyOS 不会返回以下错误值：

- `no_space`：HarmonyOS 没有对应的存储空间不足认证结果，未识别的系统结果返回 `unknown`。
- `system_cancel`：系统取消与用户取消无法区分，均映射为 `user_cancel`。
- `user_fallback`：切换到锁屏密码时不产生单独的回退结果。
- `passcode_not_set`：未设置锁屏密码时按 `not_enrolled` 处理。

#### `ERR_LOCAL_AUTHENTICATION_INVALID_ARGUMENT`

`promptMessage` 为空或超过 500 个字符时抛出。仅使用生物认证时，`cancelLabel` 超过 60 个字符也会抛出；系统拒绝认证界面参数时同样可能抛出。

#### `ERR_LOCAL_AUTHENTICATION_UNAVAILABLE`

查询或选择认证能力遇到无法识别的 HarmonyOS 系统错误时抛出；此时不会将查询错误当作硬件不支持或凭据未录入返回。

### Permissions

#### `ohos.permission.ACCESS_BIOMETRIC`

查询和启动生物认证所需的普通权限，由本包声明并随应用安装生效，不会弹出额外授权框。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
