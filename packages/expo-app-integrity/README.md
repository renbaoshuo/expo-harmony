# @expo-harmony/expo-app-integrity

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-app-integrity) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/app-integrity/)

为 HarmonyOS 上的 React Native 应用提供 Expo App Integrity 的原生实现，与官方 `@expo/app-integrity` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-app-integrity @expo/app-integrity@~57.0.2
```

## API 对照表

### 常量

#### `AppIntegrity.isSupported`

类型：`boolean`。HarmonyOS 上始终为 `false`。

### 方法

#### `AppIntegrity.isHardwareAttestationSupportedAsync()`

无参数，返回 `Promise<boolean>`，表示当前设备是否支持硬件密钥证明。返回 `true` 不代表网络可用或系统证明服务一定会受理请求。参见[华为设备真实性证明说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/device-attestation-intro)。

#### `AppIntegrity.generateHardwareAttestedKeyAsync(keyAlias, challenge)`

- `keyAlias: string`：应用指定的密钥别名，不能为空，并需符合 HarmonyOS 的别名字符和长度限制。
- `challenge: string`：交给系统证明服务的挑战字符串。建议使用服务端生成的一次性值。

返回 `Promise<void>`。成功时生成签名密钥并取得匿名证明证书链；密钥内容不会返回。使用相同别名再次调用会替换已有密钥及证书链。证明需要网络连接，且须由系统证明服务受理；证书不包含设备标识。参见[华为匿名密钥证明文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/huks-key-anon-attestation-arkts)。

#### `AppIntegrity.getAttestationCertificateChainAsync(keyAlias)`

- `keyAlias: string`：生成密钥时使用的别名。

返回 `Promise<string[]>`。数组中的每项是无换行的 Base64 编码 DER 格式 X.509 证书，顺序从叶证书到根证书。证书链随密钥保存，应用重启后仍可读取；密钥或证书链不存在、无效时以 `ERR_APP_INTEGRITY_HARDWARE_ATTESTATION_CERTIFICATE_CHAIN_INVALID` 拒绝。

#### `AppIntegrity.generateKeyAsync()`

- 无参数，接口返回类型为 `Promise<string>`。
- HarmonyOS 不提供此方法，调用时以 `ERR_APP_INTEGRITY_FEATURE_UNSUPPORTED` 拒绝。

#### `AppIntegrity.attestKeyAsync(keyId, challenge)`

- `keyId: string`、`challenge: string`，接口返回类型为 `Promise<string>`。
- HarmonyOS 不提供此方法，调用时以 `ERR_APP_INTEGRITY_FEATURE_UNSUPPORTED` 拒绝。

#### `AppIntegrity.generateAssertionAsync(keyId, challenge)`

- `keyId: string`、`challenge: string`，接口返回类型为 `Promise<string>`。
- HarmonyOS 不提供此方法，调用时以 `ERR_APP_INTEGRITY_FEATURE_UNSUPPORTED` 拒绝。

#### `AppIntegrity.prepareIntegrityTokenProviderAsync(cloudProjectNumber)`

- `cloudProjectNumber: string`，接口返回类型为 `Promise<void>`。
- HarmonyOS 不提供此方法，调用时以 `ERR_APP_INTEGRITY_API_NOT_AVAILABLE` 拒绝。

#### `AppIntegrity.requestIntegrityCheckAsync(requestHash)`

- `requestHash: string`，接口返回类型为 `Promise<string>`。
- HarmonyOS 不提供此方法，调用时以 `ERR_APP_INTEGRITY_API_NOT_AVAILABLE` 拒绝。

### 错误码

#### `ERR_APP_INTEGRITY_FEATURE_UNSUPPORTED`

调用 `generateKeyAsync()`、`attestKeyAsync()` 或 `generateAssertionAsync()` 时抛出。

#### `ERR_APP_INTEGRITY_API_NOT_AVAILABLE`

调用 `prepareIntegrityTokenProviderAsync()` 或 `requestIntegrityCheckAsync()` 时抛出。

#### `ERR_APP_INTEGRITY_INVALID_INPUT`

密钥别名为空、包含不受支持的字符或超出长度限制时抛出；字符串参数含无效 Unicode 字符时也会抛出。

#### `ERR_APP_INTEGRITY_HARDWARE_ATTESTATION_NOT_SUPPORTED`

设备或系统不支持硬件密钥证明时抛出。

#### `ERR_APP_INTEGRITY_HARDWARE_ATTESTATION_KEY_GENERATION_FAILED`

系统未能生成硬件密钥时抛出。

#### `ERR_APP_INTEGRITY_HARDWARE_ATTESTATION_FAILED`

系统证明请求失败时抛出，例如网络不可用或系统证明服务未受理请求。

#### `ERR_APP_INTEGRITY_HARDWARE_ATTESTATION_CERTIFICATE_CHAIN_INVALID`

密钥对应的证明证书链不存在或无法读取时抛出。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
