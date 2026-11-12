# @expo-harmony/expo-print

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-print) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/print/)

为 HarmonyOS 上的 React Native 应用提供 Expo Print 的原生实现，与官方同版本的 `expo-print` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 14（HarmonyOS 5.0.2）。

```bash
npm install @expo-harmony/expo-print expo-print
```

## API 对照表

### Constants

#### `Print.Orientation`

包含 `portrait: 'portrait'` 和 `landscape: 'landscape'`，可用于设置 `PrintOptions.orientation`。设为 `landscape` 且页面高度大于宽度时，会交换页面宽高；其他情况下宽高不变。

### Methods

#### `Print.printAsync(options)`

返回 `Promise<void>`。打开系统打印界面并提交打印请求后即完成，不等待打印作业结束；用户关闭界面不会因此导致请求失败。

`options` 见 `PrintOptions`。必须提供 `html` 或 `uri`：两者都未提供时请求失败；两者同时为非空值时请求失败。传入 `html: ''` 可打印空白文档；此时即使提供 `uri`，也会按空白 HTML 处理。

`html` 是要打印的 HTML。HTML 中的 JavaScript 不会执行；相对地址没有基准路径，本地文件地址不会读取。图片可使用内联 Base64 或网络地址，网络图片需要 `ohos.permission.INTERNET`。页面大小、边距、文字缩放和方向选项均在打印 HTML 时生效。

`uri` 必须指向 PDF，支持可读取的本地 PDF URI、HTTP(S) PDF 地址，以及 `data:application/pdf;base64,` 数据 URI。外部文件 URI 需要应用具有读取授权。URI 无法读取或内容不是 PDF 时请求失败。

调用时应用需处于前台；应用进入后台或关闭时，尚未提交的请求会失败或取消。设备不支持系统打印功能时请求失败。

#### `Print.printToFileAsync(options?)`

返回 `Promise<FilePrintResult>`，将 HTML 导出为 PDF 并保存在应用缓存目录。省略 `options` 或未提供 HTML、提供空字符串 HTML 时，会导出一页空白文档。导出的文件由调用方管理和清理。

生成文件并返回页数需要设备支持 PDF 服务；不支持时请求失败。`base64: true` 时结果包含不带 `data:` 前缀的 Base64 内容。

#### `Print.selectPrinterAsync()`

返回 `Promise<Printer>`。

- HarmonyOS 没有供此方法使用的独立打印机选择功能，调用会失败。

### Types

#### `OrientationType`

包含两个字符串属性：`portrait` 和 `landscape`，分别表示纵向和横向页面方向。

#### `FilePrintOptions`

HTML 导出 PDF 时使用的选项。

| 属性 | 类型 | 默认值及行为 |
| --- | --- | --- |
| `html` | `string?` | 要导出为 PDF 的 HTML；省略或为空时导出空白文档。 |
| `width` | `number?` | 页面宽度，按 72 PPI 换算，默认 `612`。 |
| `height` | `number?` | 页面高度，按 72 PPI 换算，默认 `792`。 |
| `margins` | `PageMargins?` | 页面边距，默认各侧为 `0`。 |
| `textZoom` | `number?` | 文字缩放百分比，默认 `100`；须为正 int32 整数。 |
| `base64` | `boolean?` | 设为 `true` 时在结果中附带 Base64 内容。 |

宽高须为正有限数值；每侧边距须为非负数，且小于对应页面尺寸的一半。

- `useMarkupFormatter`：HarmonyOS 不提供此 HTML 格式化方式。

#### `FilePrintResult`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `uri` | `string` | 导出 PDF 在应用缓存目录中的 URI。 |
| `numberOfPages` | `number` | PDF 页数。 |
| `base64` | `string?` | 仅在 `base64: true` 时返回，不带 `data:` 前缀。 |

#### `PageMargins`

页面边距，单位与页面宽高一致。每侧边距须为非负数，且小于对应页面尺寸的一半；未设置的边距按 `0` 处理。

| 属性 | 类型 |
| --- | --- |
| `top` | `number` |
| `right` | `number` |
| `bottom` | `number` |
| `left` | `number` |

#### `Printer`

打印机信息类型，包含 `name: string` 和 `url: string`。

- HarmonyOS 不提供独立打印机选择功能，因此本包不会返回此类型的对象。

#### `PrintOptions`

打印 HTML 或 PDF 时使用的选项。

| 属性 | 类型 | 默认值及行为 |
| --- | --- | --- |
| `html` | `string?` | 要打印的 HTML；与 `uri` 不能同时为非空值。空字符串表示打印空白文档。 |
| `uri` | `string?` | 要打印的 PDF URI；与 `html` 不能同时为非空值。 |
| `width` | `number?` | HTML 页面宽度，按 72 PPI 换算，默认 `612`。 |
| `height` | `number?` | HTML 页面高度，按 72 PPI 换算，默认 `792`。 |
| `margins` | `PageMargins?` | HTML 页面边距，默认各侧为 `0`。 |
| `textZoom` | `number?` | HTML 文字缩放百分比，默认 `100`；须为正 int32 整数。 |
| `orientation` | `string?` | HTML 页面方向，取 `Orientation.portrait` 或 `Orientation.landscape`。 |

HTML 页面宽高须为正有限数值；每侧边距须为非负数，且小于对应页面尺寸的一半。`width`、`height`、`margins`、`textZoom` 和 `orientation` 不影响通过 `uri` 打印的 PDF。

- `printerUrl`：HarmonyOS 打印请求不支持指定打印机 URL。
- `useMarkupFormatter`：HarmonyOS 不提供此 HTML 格式化方式。
- `markupFormatterIOS`：HarmonyOS 不提供此 HTML 格式化方式。

### Error codes

#### `ERR_PRINT_BACKGROUND`

打印期间应用不在前台时抛出。

#### `ERR_PRINT_CACHE_DIRECTORY`

无法创建用于保存 PDF 的缓存目录时抛出。

#### `ERR_PRINT_CANCELLED`

打印或 PDF 导出尚未完成时，应用进入后台或关闭导致请求取消时抛出。

#### `ERR_PRINT_CANNOT_LOAD_URI`

无法读取 PDF URI、下载失败或 URI 内容不是 PDF 时抛出。

#### `ERR_PRINT_DESTROYED`

执行期间应用运行环境已结束，导致请求无法继续时抛出。

#### `ERR_PRINT_FAILED`

无法启动系统打印请求时抛出。

#### `ERR_PRINT_HTML_LOAD`

HTML 页面无法加载时抛出。

#### `ERR_PRINT_HTML_RENDER`

HTML 页面无法完成渲染时抛出。

#### `ERR_PRINT_HTML_TIMEOUT`

HTML 页面渲染超过 60 秒时抛出。

#### `ERR_PRINT_HTML_UNAVAILABLE`

设备不支持将 HTML 渲染为 PDF 时抛出。

#### `ERR_PRINT_IN_PROGRESS`

前一个打印请求尚未提交时再次调用 `printAsync` 会抛出。

#### `ERR_PRINT_INVALID_OPTIONS`

未提供 HTML 或 PDF URI、HTML 与 PDF URI 冲突，或页面尺寸、边距、文字缩放参数无效时抛出。

#### `ERR_PRINT_PDF_PARSE`

无法读取导出 PDF 的页数时抛出。

#### `ERR_PRINT_PDF_RENDER`

无法生成 PDF 文件时抛出。

#### `ERR_PRINT_PDF_UNAVAILABLE`

设备不支持读取导出 PDF 页数所需的 PDF 服务时抛出。

#### `ERR_PRINT_UNAVAILABLE`

设备不支持系统打印功能时抛出。

### Permissions

#### `ohos.permission.PRINT`

用于提交系统打印请求，属于普通权限，由系统授予；本包模块已声明此权限。

#### `ohos.permission.INTERNET`

用于下载 HTTP(S) PDF 和加载 HTML 中的网络图片，属于普通权限，由系统授予；本包模块已声明此权限。

## 使用示例

```ts
import * as Print from 'expo-print';

const result = await Print.printToFileAsync({
  html: '<!doctype html><html><body><h1>Hello, HarmonyOS</h1></body></html>',
  base64: true,
});

await Print.printAsync({ uri: result.uri });
```

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
