# @expo-harmony/expo-crypto

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-crypto) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/crypto/)

为 HarmonyOS 上的 React Native 应用提供 Expo Crypto 的原生实现，与官方同版本的 `expo-crypto` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-crypto expo-crypto@57.0.4
```

## API 对照表

### Methods

#### `AESEncryptionKey.generate(size?)`

生成 AES 密钥，返回 `Promise<AESEncryptionKey>`。`size` 为 128、192 或 256，默认 256。

#### `AESEncryptionKey.import(bytes)`

从 `Uint8Array` 导入密钥，返回 `Promise<AESEncryptionKey>`。密钥长度须为 16、24 或 32 字节。

#### `AESEncryptionKey.import(hexString, encoding)`

从字符串导入密钥，返回 `Promise<AESEncryptionKey>`。`encoding` 必须为 `'hex'` 或 `'base64'`；hex 字符串可带 `0x` 前缀。解码后的密钥须为 16、24 或 32 字节。

#### `AESEncryptionKey.bytes()`

返回 `Promise<Uint8Array>`，包含密钥字节。

#### `AESEncryptionKey.encoded(encoding)`

返回 `Promise<string>`。`encoding` 为 `'hex'` 或 `'base64'`。

#### `AESSealedData.fromCombined(combined, config?)`

从 IV、密文和认证标签依次拼接的数据创建并返回 `AESSealedData`。`config.ivLength` 默认 12，`config.tagLength` 默认 16；数据须至少包含指定长度的 IV 和标签。创建对象时保留传入的 IV 长度；调用加解密时，IV 长度须在 1 到 128 字节之间。

#### `AESSealedData.fromParts(iv, ciphertext, tag)`

从独立的 IV、密文和认证标签创建并返回 `AESSealedData`。`ciphertext` 不含认证标签。

#### `AESSealedData.fromParts(iv, ciphertextWithTag, tagLength?)`

从 IV 和尾部附有认证标签的密文创建并返回 `AESSealedData`。`tagLength` 默认 16；输入须至少包含指定长度的标签。

#### `AESSealedData.ciphertext(options?)`

返回 `Promise<string | Uint8Array>`。`options.includeTag` 默认 `false`；`options.encoding` 默认 `'bytes'`，也可设为 `'base64'`。

#### `AESSealedData.combined(encoding?)`

返回 IV、密文和标签拼接后的 `Promise<string | Uint8Array>`。`encoding` 默认 `'bytes'`，也可设为 `'base64'`。

#### `AESSealedData.iv(encoding?)`

返回 `Promise<string | Uint8Array>`。`encoding` 默认 `'bytes'`，也可设为 `'base64'`。

#### `AESSealedData.tag(encoding?)`

返回 `Promise<string | Uint8Array>`。`encoding` 默认 `'bytes'`，也可设为 `'base64'`。

#### `Crypto.aesEncryptAsync(plaintext, key, options?)`

使用 AES-GCM 加密并返回 `Promise<AESSealedData>`。`plaintext` 为 `BinaryInput`；字符串按 base64 解码。`options.nonce` 可指定 IV 字节或长度；未指定时生成 12 字节 IV。IV 长度须为 1 到 128 字节。`options.additionalData` 为附加认证数据，字符串按 base64 解码。`options.tagLength` 默认 16 字节，HarmonyOS 加密只接受 16 字节。

#### `Crypto.aesDecryptAsync(sealedData, key, options?)`

使用 AES-GCM 解密并返回 `Promise<Uint8Array | string>`。`options.output` 默认 `'bytes'`，也可设为 `'base64'`；`options.additionalData` 为附加认证数据，字符串按 base64 解码。HarmonyOS 解密只接受 16 字节认证标签；标签验证失败时 Promise 会被拒绝。

#### `Crypto.digest(algorithm, data)`

返回 `Promise<ArrayBuffer>`，计算输入数据的摘要。`data` 可为 `ArrayBuffer`、`DataView` 或 TypedArray；传入视图时只计算视图覆盖的字节。支持 SHA-1、SHA-256、SHA-384、SHA-512 和 MD5。

#### `Crypto.digestStringAsync(algorithm, data, options?)`

返回 `Promise<string>`，对字符串的 UTF-8 字节计算摘要。支持 SHA-1、SHA-256、SHA-384、SHA-512 和 MD5。`options.encoding` 默认 `'hex'`，也可设为 `'base64'`。

#### `Crypto.getRandomBytes(byteCount)`

返回长度为 `byteCount` 的 `Uint8Array`。`byteCount` 须在 0 到 1024 之间；超出范围时抛出 `TypeError`。

#### `Crypto.getRandomBytesAsync(byteCount)`

返回 `Promise<Uint8Array>`，长度规则与 `getRandomBytes()` 相同。

#### `Crypto.getRandomValues(typedArray)`

用安全随机数填充传入的整型 TypedArray，原地修改并返回同一数组。支持 `Int8Array`、`Uint8Array`、`Uint8ClampedArray`、`Int16Array`、`Uint16Array`、`Int32Array` 和 `Uint32Array`；空数组保持不变。

#### `Crypto.randomUUID()`

返回小写 RFC 4122 V4 UUID 字符串。

### Types

#### `AESEncryptionKey`

AES 密钥对象，密钥长度为 128、192 或 256 位。构造器不能直接调用，通过 `generate()` 或 `import()` 创建。

#### `AESEncryptionKey.size`

只读 `AESKeySize`，表示密钥位数。

#### `AESSealedData`

包含 AES-GCM 的 IV、密文和认证标签。构造器不能直接调用，通过静态方法创建。

#### `AESSealedData.combinedSize`

只读 `number`，表示 IV、密文和标签的总字节数。

#### `AESSealedData.ivSize`

只读 `number`，表示 IV 的字节数。

#### `AESSealedData.tagSize`

只读 `GCMTagByteLength`，表示认证标签的字节数。HarmonyOS 加解密只接受 16 字节标签。

#### `AESEncryptOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `nonce` | `GCMNonceParam` | 可指定 IV 字节或待生成的 IV 长度；默认生成 12 字节 IV，长度范围为 1 到 128 字节。 |
| `tagLength` | `GCMTagByteLength` | 默认 16；HarmonyOS 加密只接受 16。 |
| `additionalData` | `BinaryInput` | 附加认证数据；字符串按 base64 解码。 |

#### `AESDecryptOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `output` | `'bytes' \| 'base64'` | 解密结果格式，默认 `'bytes'`。 |
| `additionalData` | `BinaryInput` | 附加认证数据；字符串按 base64 解码。 |

#### `AESSealedDataConfig`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `ivLength` | `number` | IV 字节数，默认 12。 |
| `tagLength` | `GCMTagByteLength` | 标签字节数，默认 16。 |

#### `BinaryInput`

`string | Uint8Array | ArrayBuffer`。字符串按 base64 解码。

#### `CryptoDigestOptions`

`{ encoding: CryptoEncoding }`，指定摘要输出编码。

#### `Digest`

`string`，摘要字符串。

#### `GCMNonceParam`

`{ length: number } | { bytes: BinaryInput }`。`length` 默认 12；HarmonyOS 上的 IV 长度范围为 1 到 128 字节。

#### `GCMTagByteLength`

`4 | 8 | 12 | 13 | 14 | 15 | 16`。HarmonyOS AES-GCM 加密和解密只接受 16 字节。

### Enums

#### `AESKeySize`

| 成员 | 值 |
| --- | --- |
| `AES128` | `128` |
| `AES192` | `192` |
| `AES256` | `256` |

三种密钥长度均支持。

#### `CryptoDigestAlgorithm`

| 成员 | 值 |
| --- | --- |
| `SHA1` | `'SHA-1'` |
| `SHA256` | `'SHA-256'` |
| `SHA384` | `'SHA-384'` |
| `SHA512` | `'SHA-512'` |
| `MD2` | `'MD2'` |
| `MD4` | `'MD4'` |
| `MD5` | `'MD5'` |

- HarmonyOS 摘要能力不提供 `MD2`、`MD4`，传入这两种算法会抛出 `ERR_CRYPTO_DIGEST`。

#### `CryptoEncoding`

| 成员 | 值 |
| --- | --- |
| `HEX` | `'hex'` |
| `BASE64` | `'base64'` |

### Error codes

#### `ERR_CRYPTO_AES_KEY`

生成 AES 密钥失败时抛出。

#### `ERR_CRYPTO_DECRYPT`

AES-GCM 解密失败或认证标签验证失败时抛出。

#### `ERR_CRYPTO_DIGEST`

摘要计算失败，或摘要算法、编码不受支持时抛出。

#### `ERR_CRYPTO_ENCRYPT`

AES-GCM 加密失败时抛出。

#### `ERR_CRYPTO_INVALID_BASE64`

输入的 base64 字符串格式无效时抛出。

#### `ERR_CRYPTO_INVALID_KEY`

AES 密钥长度或编码无效时抛出。

#### `ERR_CRYPTO_INVALID_NONCE`

AES-GCM IV 长度不在 1 到 128 字节范围内时抛出。

#### `ERR_CRYPTO_INVALID_SEALED_DATA`

创建 `AESSealedData` 时，认证标签长度不受支持时抛出。

#### `ERR_CRYPTO_RANDOM`

生成安全随机数失败时抛出。

#### `ERR_CRYPTO_UNSUPPORTED_TAG_LENGTH`

AES-GCM 加解密收到非 16 字节认证标签时抛出。

#### `ERR_INVALID_SEALED_DATA_CONFIG`

拼接数据不足以容纳指定长度的 IV 和认证标签时抛出。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
