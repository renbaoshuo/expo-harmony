# @expo-harmony/expo-secure-store

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-secure-store) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/securestore/)

为 HarmonyOS 上的 React Native 应用提供 Expo SecureStore 的原生实现，与官方 `expo-secure-store` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-secure-store expo-secure-store@~57.0.4
```

## API 对照表

### Constants

#### `SecureStore.AFTER_FIRST_UNLOCK`

类型：`KeychainAccessibilityConstant`。新建记录在设备首次解锁后可访问。所有记录均仅保存在当前设备。

#### `SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY`

类型：`KeychainAccessibilityConstant`。与 `AFTER_FIRST_UNLOCK` 相同；所有记录均仅保存在当前设备。

#### `SecureStore.ALWAYS`

类型：`KeychainAccessibilityConstant`。新建记录在设备开机后可访问。所有记录均仅保存在当前设备。

#### `SecureStore.ALWAYS_THIS_DEVICE_ONLY`

类型：`KeychainAccessibilityConstant`。与 `ALWAYS` 相同；所有记录均仅保存在当前设备。

#### `SecureStore.WHEN_PASSCODE_SET_THIS_DEVICE_ONLY`

类型：`KeychainAccessibilityConstant`。新建记录要求设备已设置锁屏密码，并在设备解锁后可访问；所有记录均仅保存在当前设备。未设置锁屏密码时，存储操作会失败。

#### `SecureStore.WHEN_UNLOCKED`

类型：`KeychainAccessibilityConstant`。新建记录仅在设备解锁时可访问。所有记录均仅保存在当前设备。

#### `SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY`

类型：`KeychainAccessibilityConstant`。与 `WHEN_UNLOCKED` 相同；所有记录均仅保存在当前设备。

### Methods

#### `SecureStore.canUseBiometricAuthentication()`

无参数，返回 `boolean`。当前设备有可用且达到 ATL3 等级的人脸或指纹认证方式时返回 `true`；否则返回 `false`。查询不会弹出认证界面。

#### `SecureStore.deleteItemAsync(key, options)`

`key` 为键名，只能包含字母、数字、`.`、`-` 和 `_`；`options` 可省略，用于指定 `keychainService`。返回 `Promise<void>`。键不存在时也会正常完成。删除记录不要求生物认证。

#### `SecureStore.getItem(key, options)`

同步读取 `key` 对应的值，键名只能包含字母、数字、`.`、`-` 和 `_`；`options` 可省略。返回 `string | null`，键不存在时返回 `null`。同步方法会阻塞 JavaScript 线程。

记录要求生物认证且凭据未变化时，此方法抛出 `ERR_SECURE_STORE_SYNC_AUTH_UNSUPPORTED`。若记录的生物凭据状态已变化，记录会被删除并返回 `null`。

#### `SecureStore.getItemAsync(key, options)`

异步读取 `key` 对应的值，键名只能包含字母、数字、`.`、`-` 和 `_`；`options` 可省略，用于指定 `keychainService` 和 `authenticationPrompt`。返回 `Promise<string | null>`，键不存在时返回 `null`。

读取要求生物认证的记录时会显示系统认证界面。生物识别信息变化后，记录会被删除并返回 `null`。

#### `SecureStore.isAvailableAsync()`

无参数，返回 `Promise<boolean>`。HarmonyOS 上返回 `true`；这不表示设备支持生物认证。

#### `SecureStore.setItem(key, value, options)`

同步写入键值对。`key` 只能包含字母、数字、`.`、`-` 和 `_`，`value` 必须是字符串且最多为 1023 个 UTF-8 字节；空字符串可以保存。`options` 可省略。返回 `void`。同步方法会阻塞 JavaScript 线程。

当 `options.requireAuthentication` 为 `true`，且已有记录仍与当前生物凭据关联时，同步写入会抛出 `ERR_SECURE_STORE_SYNC_AUTH_UNSUPPORTED`。初次创建生物认证记录不需要认证界面；已有记录凭据状态变化时，同步写入会按新选项重建记录。

#### `SecureStore.setItemAsync(key, value, options)`

异步写入键值对。`key` 为键名，`value` 必须是字符串，`options` 可省略。返回 `Promise<void>`。

键名只能包含字母、数字、`.`、`-` 和 `_`。每个值最多为 1023 个 UTF-8 字节；超限时写入失败，原记录保持不变。空字符串可以保存。

写入时设置 `options.requireAuthentication: true`，设备必须有可用且达到 ATL3 等级的人脸或指纹认证方式。首次创建记录不显示认证界面；读取已保存为生物认证的记录，或使用相同认证模式更新记录时，需要通过系统认证。认证只在应用前台发起，认证失败、取消或应用不在前台时操作会失败。生物识别信息变化后，读取返回 `null` 并删除记录。

同一 `keychainService` 和键上的异步操作按顺序完成。对仍有异步操作进行中的同一服务名和键调用同步方法会抛出 `ERR_SECURE_STORE_BUSY`。

### Types

#### `KeychainAccessibilityConstant`

类型：`number`。可使用本页列出的访问策略常量作为 `keychainAccessible` 的值。

#### `SecureStoreOptions`

`setItemAsync()`、`getItemAsync()`、`deleteItemAsync()` 及对应的同步方法可接受此选项对象。

| 属性 | 类型 | 默认值 | HarmonyOS 行为 |
| --- | --- | --- | --- |
| `keychainService` | `string` | `'app'` | 服务名；不同服务中的同名键相互独立，读取和删除时需使用相同服务名。 |
| `requireAuthentication` | `boolean` | `false` | 为记录启用生物认证；只支持达到 ATL3 等级的人脸或指纹。见 `setItemAsync()`。 |
| `authenticationPrompt` | `string` | `'Authenticate to access secure data'` | 实际发起认证时作为系统界面的标题，长度须为 1–500 个 Unicode 码点。 |
| `keychainAccessible` | `KeychainAccessibilityConstant` | `WHEN_UNLOCKED` | 选择记录在设备锁定状态下的访问策略；不同常量的 HarmonyOS 映射见 Constants。 |
| `accessGroup` | `string` | — | HarmonyOS 不支持应用间共享访问组。 |

HarmonyOS 不支持的选项：

- `accessGroup`：HarmonyOS 不提供应用间共享访问组；传入该属性会抛出 `ERR_SECURE_STORE_UNSUPPORTED_OPTION`。

同一认证模式下更新记录只替换值，保留原有的 `keychainAccessible`。要更改现有记录的访问策略，请先删除再重新创建。

### Error codes

#### `ERR_SECURE_STORE_INVALID_ARGUMENT`

选项对象或属性类型无效、`keychainAccessible` 不是有效常量，或 `authenticationPrompt` 为空或超过 500 个 Unicode 码点时抛出。

#### `ERR_SECURE_STORE_UNSUPPORTED_OPTION`

传入 `SecureStoreOptions.accessGroup` 时抛出；HarmonyOS 不支持共享访问组。

#### `ERR_SECURE_STORE_VALUE_TOO_LARGE`

写入值超过 1023 个 UTF-8 字节时抛出。

#### `ERR_SECURE_STORE_AUTH_UNAVAILABLE`

启用 `requireAuthentication`，但设备没有可用且达到 ATL3 等级的已录入人脸或指纹时抛出。

#### `ERR_SECURE_STORE_AUTH_FAILED`

生物认证未通过、被取消或锁定，应用不在前台，或已有认证界面仍在进行时抛出。

#### `ERR_SECURE_STORE_SYNC_AUTH_UNSUPPORTED`

同步方法读取或更新仍受当前生物凭据保护的记录时抛出。此类操作请使用异步方法。

#### `ERR_SECURE_STORE_BUSY`

同一键仍有异步操作进行时调用同步方法会抛出。等待该异步操作完成后再调用同步方法。

#### `ERR_SECURE_STORE_DESTROYED`

应用运行时销毁或重载期间，尚未完成的生物认证会取消并抛出此错误。

#### `ERR_SECURE_STORE_DECODE`

存储记录或关联的认证状态无效、无法读取时抛出。

#### `ERR_SECURE_STORE_OPERATION_FAILED`

HarmonyOS 安全存储操作失败时抛出；错误包含系统返回码。

### Permissions

#### `ohos.permission.ACCESS_BIOMETRIC`

查询或使用生物认证所需的普通权限，由本包声明并随应用安装生效，无需运行时申请。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors)

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
