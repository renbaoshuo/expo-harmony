# @expo-harmony/expo-standard-web-crypto

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-standard-web-crypto) | [Expo Crypto 文档](https://docs.expo.dev/versions/v57.0.0/sdk/crypto/)

为 HarmonyOS 上的 React Native 应用提供 Expo Standard Web Crypto 支持，与官方 `expo-standard-web-crypto` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-standard-web-crypto expo-standard-web-crypto@~57.0.4 @expo-harmony/expo-crypto expo-crypto@~57.0.4
```

## API 对照表

### Constants

#### 默认导出的 `crypto`

默认导出当前的 `crypto` 对象。HarmonyOS 运行环境没有全局 `crypto` 时，本包提供的对象仅实现 `getRandomValues()`。

- `crypto.subtle` 未实现：本包提供的对象仅实现 `getRandomValues()`。
- `crypto.randomUUID()` 未实现：本包提供的对象仅实现 `getRandomValues()`。

### Methods

#### `polyfillWebCrypto()`

当全局 `crypto` 不存在时，在 `window` 上提供 `crypto` 对象；若对象已存在，则不作修改。返回 `void`。

#### `crypto.getRandomValues(values)`

用随机数原地填充并返回传入的整型 TypedArray。支持 `Int8Array`、`Uint8Array`、`Uint8ClampedArray`、`Int16Array`、`Uint16Array`、`Int32Array` 和 `Uint32Array`。`values` 的字节长度最多为 65,536；缺少参数或传入其他类型会抛出 `TypeError`，超过长度上限会抛出 `QuotaExceededError`（`code` 为 `22`）。

- HarmonyOS 无法取得安全随机数时会发出警告并回退到非安全随机数；回退结果不适合安全用途。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
