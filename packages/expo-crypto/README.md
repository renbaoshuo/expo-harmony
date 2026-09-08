# @expo-harmony/expo-crypto

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-crypto) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/crypto/)

为 HarmonyOS 上的 React Native 应用提供 Expo Crypto 的原生实现，与官方同版本的 `expo-crypto` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-crypto expo-crypto@55.0.15
```

## API 对照表

### Classes

#### `AESEncryptionKey`

AES 密钥。位数由 `size` 给出，取值为 128、192 或 256。构造器不能直接调用，用静态方法创建。

#### `AESEncryptionKey.generate(size?)`

返回 `Promise<AESEncryptionKey>`，生成新密钥。`size` 默认 256，只接受 128、192、256。

#### `AESEncryptionKey.import(bytes)`

从 `Uint8Array` 导入密钥，返回 `Promise<AESEncryptionKey>`。字节数须为 16、24 或 32，否则抛错。

#### `AESEncryptionKey.import(hexString, encoding)`

从字符串导入密钥，返回 `Promise<AESEncryptionKey>`。`encoding` 取 `'hex'` 或 `'base64'`，必须显式给出。hex 允许 `0x` 前缀。

#### `AESEncryptionKey.size`

类型：`AESKeySize`，只读

密钥位数。

#### `AESEncryptionKey.bytes()`

返回 `Promise<Uint8Array>`，密钥的字节表示。

#### `AESEncryptionKey.encoded(encoding)`

返回 `Promise<string>`，按 `'hex'` 或 `'base64'` 输出密钥。

#### `AESSealedData`

AES-GCM 的 IV、密文和认证标签。构造器不能直接调用，用静态方法创建。

#### `AESSealedData.fromCombined(combined, config?)`

从 IV、密文、标签依次拼接的数据创建，返回 `AESSealedData`。`config.ivLength` 默认 12，`config.tagLength` 默认 16。数据长度不足时抛错。

#### `AESSealedData.fromParts(iv, ciphertext, tag)`

从三段独立数据创建，返回 `AESSealedData`。`ciphertext` 不含标签。

#### `AESSealedData.fromParts(iv, ciphertextWithTag, tagLength?)`

从 IV 和尾部带标签的密文创建，返回 `AESSealedData`。`tagLength` 默认 16。

#### `AESSealedData.ciphertext(options?)`

返回 `Promise<string | Uint8Array>`，密文。`options.includeTag` 默认 `false`，为 `true` 时在密文末尾附加标签；`options.encoding` 默认 `'bytes'`，也可用 `'base64'`。

#### `AESSealedData.combined(encoding?)`

返回 `Promise<string | Uint8Array>`，IV、密文、标签的拼接结果。`encoding` 默认 `'bytes'`。

#### `AESSealedData.iv(encoding?)`

返回 `Promise<string | Uint8Array>`，IV。`encoding` 默认 `'bytes'`。

#### `AESSealedData.tag(encoding?)`

返回 `Promise<string | Uint8Array>`，认证标签。`encoding` 默认 `'bytes'`。

#### `AESSealedData.combinedSize`

类型：`number`，只读

IV、密文、标签的总字节数。

#### `AESSealedData.ivSize`

类型：`number`，只读

IV 的字节数。

#### `AESSealedData.tagSize`

类型：`GCMTagByteLength`，只读

认证标签的字节数。

### Methods

#### `Crypto.aesDecryptAsync(sealedData, key, options?)`

返回 `Promise<string | Uint8Array>`，用 AES-GCM 解密。`options.output` 决定返回类型，默认 `'bytes'`。认证标签校验失败时拒绝。

#### `Crypto.aesEncryptAsync(plaintext, key, options?)`

返回 `Promise<AESSealedData>`，用 AES-GCM 加密。未提供 `nonce` 时随机生成。

#### `Crypto.digest(algorithm, data)`

返回 `Promise<ArrayBuffer>`，对 `ArrayBuffer` 或 TypedArray 计算摘要。支持 SHA-1、SHA-256、SHA-384、SHA-512、MD5。

#### `Crypto.digestStringAsync(algorithm, data, options?)`

返回 `Promise<string>`，对字符串按 UTF-8 编码计算摘要，支持的算法与 `digest()` 相同。`options.encoding` 默认 `'hex'`，也可用 `'base64'`。

#### `Crypto.getRandomBytes(byteCount)`

返回长度为 `byteCount` 的 `Uint8Array`。取值 0 到 1024，超出范围抛 `TypeError`。

#### `Crypto.getRandomBytesAsync(byteCount)`

返回 `Promise<Uint8Array>`，长度和取值范围与 `getRandomBytes()` 相同。

#### `Crypto.getRandomValues(typedArray)`

用安全随机数填充传入的整型 TypedArray，原地修改并返回同一数组。支持 `Int8Array`、`Uint8Array`、`Uint8ClampedArray`、`Int16Array`、`Uint16Array`、`Int32Array`、`Uint32Array`。空数组直接返回。

#### `Crypto.randomUUID()`

返回 RFC 4122 V4 UUID 字符串，小写。

### Interfaces

#### `AESEncryptOptions`

| 属性             | 类型               | 说明                                       |
| ---------------- | ------------------ | ------------------------------------------ |
| `nonce`          | `GCMNonceParam`    | 未提供时随机生成，长度默认 12              |
| `tagLength`      | `GCMTagByteLength` | 默认 16，HarmonyOS 上只接受 16             |
| `additionalData` | `BinaryInput`      | 附加认证数据，字符串按 base64 解析         |

#### `AESDecryptOptions`

| 属性             | 类型                  | 说明                               |
| ---------------- | --------------------- | ---------------------------------- |
| `output`         | `'bytes' \| 'base64'` | 输出格式，默认 `'bytes'`           |
| `additionalData` | `BinaryInput`         | 附加认证数据，字符串按 base64 解析 |

#### `AESSealedDataConfig`

| 属性        | 类型               | 说明    |
| ----------- | ------------------ | ------- |
| `ivLength`  | `number`           | 默认 12 |
| `tagLength` | `GCMTagByteLength` | 默认 16 |

### Types

#### `BinaryInput`

`string | Uint8Array | ArrayBuffer`，字符串按 base64 解析。

#### `CryptoDigestOptions`

`{ encoding: CryptoEncoding }`。

#### `Digest`

`string`。

#### `GCMNonceParam`

`{ length: number } | { bytes: BinaryInput }`。`length` 默认 12，HarmonyOS 上取值范围是 1 到 128 字节。

#### `GCMTagByteLength`

`4 | 8 | 12 | 13 | 14 | 15 | 16`。加解密时 HarmonyOS 只接受 16，其他值抛错，与 Apple 上静默使用 16 的处理不同。

### Enums

#### `AESKeySize`

| 成员     | 值    |
| -------- | ----- |
| `AES128` | `128` |
| `AES192` | `192` |
| `AES256` | `256` |

三种长度都支持。

#### `CryptoDigestAlgorithm`

| 成员     | 值          |
| -------- | ----------- |
| `SHA1`   | `'SHA-1'`   |
| `SHA256` | `'SHA-256'` |
| `SHA384` | `'SHA-384'` |
| `SHA512` | `'SHA-512'` |
| `MD2`    | `'MD2'`     |
| `MD4`    | `'MD4'`     |
| `MD5`    | `'MD5'`     |

> **未实现的内容**
>
> - `MD2`、`MD4`：HarmonyOS 的摘要能力不提供这两种算法，传入时抛出 `ERR_CRYPTO_DIGEST`。

#### `CryptoEncoding`

| 成员     | 值         |
| -------- | ---------- |
| `HEX`    | `'hex'`    |
| `BASE64` | `'base64'` |

### Error codes

#### `ERR_CRYPTO_DIGEST`

摘要算法或编码不受支持时抛出。HarmonyOS 上传入 `MD2`、`MD4` 会得到这个错误。

#### `ERR_CRYPTO_UNAVAILABLE`

只在 Web 上因缺少安全来源而使用，HarmonyOS 上不会出现。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
