# @expo-harmony/expo-blob

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-blob) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/blob/)

为 HarmonyOS 上的 React Native 应用提供 Expo Blob 的原生实现，与官方同版本的 `expo-blob` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-blob expo-blob@55.0.13
```

## API 对照表

### Classes

#### `Blob`

二进制数据容器。内容在构造时确定，之后不再改变。必须用 `new` 调用，否则抛出 `TypeError`。

#### `new Blob(blobParts?, options?)`

返回新的 `Blob`。`blobParts` 是 `BlobPart` 数组或任意可迭代对象，省略时为空。

`options.type` 是 MIME 类型，默认空字符串。只保留可打印 ASCII 字符并转为小写，含其他字符时按空字符串处理。

`options.endings` 取 `'transparent'` 或 `'native'`，默认 `'transparent'`，取其他值抛出 `TypeError`。取 `'native'` 时字符串片段中的 `\r\n` 和单独的 `\r` 都换成 `\n`，取 `'transparent'` 时原样保留；该选项只影响字符串片段。

内容按片段复制。构造后修改原来的字符串变量、ArrayBuffer 或 TypedArray，不会改变 Blob 里的数据。TypedArray 按自身的 `byteOffset` 和 `byteLength` 取范围。

#### `Blob.size`

类型：`number`，只读

字节数，为各片段长度之和。

#### `Blob.type`

类型：`string`，只读

MIME 类型，无法确定时为空字符串。

#### `Blob.arrayBuffer()`

返回 `Promise<ArrayBuffer>`，Blob 的完整字节。每次调用返回新的 ArrayBuffer，修改结果不影响 Blob。

#### `Blob.bytes()`

返回 `Promise<Uint8Array>`，Blob 的完整字节。每次调用返回新的数组，修改结果不影响 Blob 和后续读取。

#### `Blob.slice(start?, end?, contentType?)`

返回新的 `Blob`，取字节范围 `[start, end)`。`start`、`end` 为有符号 32 位整数，负值从末尾算起，小数向零取整，越界时截到 `0` 或 `size`。省略时分别取 `0` 和 `size`。`end` 不大于 `start` 时返回空 Blob。

`contentType` 是结果的 MIME 类型，默认空字符串，处理方式与构造参数 `type` 相同。切片不继承原 Blob 的类型。

#### `Blob.stream()`

返回 `ReadableStream`，按块输出 Blob 内容。默认流每块最多 64 KiB，也支持 BYOB 读取。与官方实现相同，读取前会把整个 Blob 载入内存。

#### `Blob.text()`

返回 `Promise<string>`，按 UTF-8 解码的内容。空 Blob 返回空字符串。非法字节序列替换为 `U+FFFD` 而不抛错，字节序标记保留在结果开头。

文本解码在支持的各 HarmonyOS 版本上行为一致。

### Types

#### `BlobPart`

`string | ArrayBuffer | ArrayBufferView | Blob`，构造 `Blob` 时单个片段的取值。字符串按 UTF-8 编码，ArrayBuffer 和 TypedArray 按字节使用，嵌套的 `Blob` 沿用其内容。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
