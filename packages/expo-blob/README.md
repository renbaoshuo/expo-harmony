# @expo-harmony/expo-blob

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-blob) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/blob/)

为 HarmonyOS 上的 React Native 应用提供 Expo Blob 的原生实现，与官方同版本的 `expo-blob` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-blob expo-blob
```

## API 对照表

### Types

#### `Blob`

表示不可变二进制数据的对象，不提供文件读写方法。

#### `Blob.size`

只读 `number`，表示 Blob 的字节数，即各片段长度之和。总长度超过安全整数范围时会抛出 `RangeError`。

#### `Blob.type`

只读 `string`，表示 MIME 类型。只保留可打印 ASCII 字符并转换为小写；类型为空或含其他字符时返回空字符串。

#### `BlobPart`

`string | ArrayBuffer | ArrayBufferView | Blob`，表示构造 Blob 时可传入的单个片段。字符串按 UTF-8 编码，ArrayBuffer 和 TypedArray 使用其字节内容，嵌套 Blob 使用其内容。TypedArray 仅使用其 `byteOffset` 和 `byteLength` 指定的范围。

`DataView` 和 `Uint8ClampedArray` 会先转换为字符串再编码。若要传入这两种视图的字节，可先转换为 `new Uint8Array(view.buffer, view.byteOffset, view.byteLength)`。

### Methods

#### `new Blob(blobParts?, options?)`

创建并返回 `Blob`。`blobParts` 可为片段数组或可迭代对象，省略时创建空 Blob；传入 `null` 或非对象值会抛出 `TypeError`。构造时读取 ArrayBuffer 和 TypedArray 的当前字节，之后修改输入不会改变 Blob 内容。

`options.type` 为可选 MIME 类型，默认空字符串，按 `Blob.type` 的规则处理。`options.endings` 可设为 `'transparent'` 或 `'native'`，默认 `'transparent'`；其他值会抛出 `TypeError`。设为 `'native'` 时，字符串片段中的 `\r\n` 和单独的 `\r` 都转换为 `\n`；设为 `'transparent'` 时保留原样。该选项只影响字符串片段。

#### `Blob.arrayBuffer()`

返回 `Promise<ArrayBuffer>`，解析为 Blob 的完整字节。每次调用返回新的 ArrayBuffer，修改结果不会影响 Blob。

#### `Blob.bytes()`

返回 `Promise<Uint8Array>`，解析为 Blob 的完整字节。每次调用返回新的数组，修改结果不会影响 Blob 或后续读取。

#### `Blob.slice(start?, end?, contentType?)`

返回新的 `Blob`，包含字节范围 `[start, end)`。`start` 和 `end` 按有符号 32 位整数处理，小数向零取整，`NaN` 按 `0` 处理；负值从末尾计算，超出范围时限制在 `0` 到 Blob 长度之间。参数省略时分别按 `0` 和 Blob 长度处理；`end` 不大于 `start` 时结果为空。

`contentType` 为结果 MIME 类型，默认空字符串，按 `Blob.type` 的规则处理；结果不继承原 Blob 的类型。

#### `Blob.stream()`

返回可读取 Blob 字节的 `ReadableStream`，支持按块读取和 BYOB 读取。空 Blob 的流会立即结束。

#### `Blob.text()`

返回 `Promise<string>`，解析为按 UTF-8 解码的内容。空 Blob 返回空字符串；非法字节序列替换为 `U+FFFD`，不会抛出解码错误；字节序标记会保留在结果开头。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
