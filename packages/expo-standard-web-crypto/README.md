# @expo-harmony/expo-standard-web-crypto

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-standard-web-crypto) | [Expo Crypto 文档](https://docs.expo.dev/versions/v57.0.0/sdk/crypto/)

HarmonyOS 应用直接使用官方 `expo-standard-web-crypto`。它通过 `expo-crypto` 获取随机数，HarmonyOS 原生模块由 `@expo-harmony/expo-crypto` 提供。

## 安装

本包适配 Expo SDK 57。

原生依赖 `@expo-harmony/expo-crypto` 要求 HarmonyOS API 13（HarmonyOS 5.0.1）或更高版本。

```bash
npm install expo-standard-web-crypto@~57.0.4 @expo-harmony/expo-crypto expo-crypto@~57.0.4
```

```js
import crypto, { polyfillWebCrypto } from 'expo-standard-web-crypto';
```

## API 对照表

### Constants

#### 默认导出的 `crypto`

运行环境已有全局 `crypto` 时，上游默认导出该对象。否则，默认导出的补丁对象仅提供 `getRandomValues()`。

- 已有全局 `crypto` 的 `subtle` 和 `randomUUID()` 由运行环境提供。

### Methods

#### `polyfillWebCrypto()`

当全局 `crypto` 不存在时，在 `window` 上提供 `crypto` 对象；若对象已存在，则不作修改。返回 `void`。

#### `crypto.getRandomValues(values)`

用随机数原地填充并返回传入的整型 TypedArray。支持 `Int8Array`、`Uint8Array`、`Uint8ClampedArray`、`Int16Array`、`Uint16Array`、`Int32Array` 和 `Uint32Array`。`values` 的字节长度最多为 65,536；缺少参数或传入其他类型会抛出 `TypeError`，超过长度上限会抛出 `QuotaExceededError`（`code` 为 `22`）。

- 上游补丁调用 `expo-crypto` 出错时会发出警告，并使用 `Math.random()`。安全用途应直接调用 `expo-crypto` 的 `getRandomValues()`，这样原生错误会传给调用方。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
