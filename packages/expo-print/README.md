# @expo-harmony/expo-print

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-print) | [Expo 官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/print/)

为 HarmonyOS 上的 React Native 应用提供 Expo Print 的原生实现，与官方同版本的 `expo-print` 配套使用。支持将 HTML 导出为 PDF，以及通过系统打印界面打印 HTML 或 PDF 文件。最低支持 HarmonyOS 5.0.2（API 14）。

## 安装

```bash
npm install @expo-harmony/expo-print expo-print@55.0.15
```

重新生成并编译 HarmonyOS 工程后，业务代码依旧使用官方包：

```ts
import * as Print from 'expo-print';

const result = await Print.printToFileAsync({
  html: '<!doctype html><html><body><h1>Hello, HarmonyOS</h1></body></html>',
  base64: true,
});

await Print.printAsync({ uri: result.uri });
```

## API 对照表

### Constants

#### `Orientation`

类型：`OrientationType`，值为 `{ portrait: 'portrait', landscape: 'landscape' }`。

传给 `PrintOptions.orientation` 时，`landscape` 且页面高度大于宽度会交换宽高，其他情况不改变宽高。

### Methods

#### `Print.printAsync(options)`

返回 `Promise<void>`，打开系统打印界面后即返回，不等待打印完成，用户关闭界面不算失败。

`options` 见 `PrintOptions`，必须且只能提供 `html` 或 `uri` 之一，否则拒绝。打印空白文档可传 `html: ''`。

`html` 会先渲染成 PDF 再交给系统打印，`margins`、`textZoom` 和 `orientation` 在这一步生效。`uri` 支持本地文件、已授权的文件提供者 URI、HTTP(S) 链接和 `data:application/pdf;base64,` 数据 URI，内容不是 PDF 时会直接拒绝。

调用需要应用处于前台状态。已有打印请求未返回时再次调用会直接拒绝。应用退入后台或运行时销毁会取消尚未提交的工作。设备没有系统打印能力时会直接拒绝。PDF 下载和 HTML 渲染各有 60 秒超时限制。

系统打印的临时文件在收到任务完成、失败或取消事件后删除；收不到事件时保留，由系统回收。`printerUrl`、`useMarkupFormatter` 和 `markupFormatterIOS` 不生效。

#### `Print.printToFileAsync(options?)`

返回 `Promise<FilePrintResult>`，把 HTML 导出为 PDF 并保存到应用缓存目录。`options` 见 `FilePrintOptions`，省略或 `html` 为空时导出一页空白文档。

页面默认 612 × 792，按 72 PPI 换算。边距默认各侧为 0，每侧须小于对应页面尺寸的一半；尺寸须为正有限数；`textZoom` 须为正 int32 整数。超出范围时拒绝，不会把参数改成系统默认值。

页数由系统 PDF 服务解析导出文件得出，设备不支持 PDF 服务时拒绝。网页转 PDF 由系统从 API 14 起提供，也是本包的最低版本要求。`useMarkupFormatter` 不生效。

导出的文件由调用方清理。并发调用会排队依次渲染。`base64` 为 `true` 时结果附带 Base64 内容，不带 `data:` 前缀。

> **未实现的内容**
>
> - `Print.selectPrinterAsync()`：iOS 专属接口，HarmonyOS 没有对应的打印机选择能力，调用抛出 `UnavailabilityError`。

### Interfaces

#### `OrientationType`

| 属性        | 类型     |
| ----------- | -------- |
| `landscape` | `string` |
| `portrait`  | `string` |

### Types

#### `FilePrintOptions`

| 属性                 | 类型           | 说明                                                          |
| -------------------- | -------------- | ------------------------------------------------------------- |
| `html`               | `string?`      | 要渲染成 PDF 的 HTML。                                        |
| `width`              | `number?`      | 页面宽度，按 72 PPI 换算，默认 `612`。                        |
| `height`             | `number?`      | 页面高度，按 72 PPI 换算，默认 `792`。                        |
| `margins`            | `PageMargins?` | 页面边距，默认各侧为 0。官方标为 iOS 专属，这里可用。         |
| `textZoom`           | `number?`      | 文字缩放百分比，默认 `100`。官方标为 Android 专属，这里可用。 |
| `base64`             | `boolean?`     | 为 `true` 时在结果中附带 Base64 内容。                        |
| `useMarkupFormatter` | `boolean?`     | 不生效。                                                      |

#### `FilePrintResult`

| 属性            | 类型      | 说明                                                |
| --------------- | --------- | --------------------------------------------------- |
| `uri`           | `string`  | 导出文件在缓存目录中的 URI。                        |
| `numberOfPages` | `number`  | 页数。                                              |
| `base64`        | `string?` | 仅在 `base64` 为 `true` 时返回，不带 `data:` 前缀。 |

#### `PageMargins`

| 属性     | 类型     | 说明     |
| -------- | -------- | -------- |
| `top`    | `number` | 上边距。 |
| `right`  | `number` | 右边距。 |
| `bottom` | `number` | 下边距。 |
| `left`   | `number` | 左边距。 |

单位与页面尺寸一致，每侧须小于对应页面尺寸的一半。

#### `PrintOptions`

| 属性                 | 类型           | 说明                                                                                                        |
| -------------------- | -------------- | ----------------------------------------------------------------------------------------------------------- |
| `html`               | `string?`      | 要打印的 HTML，与 `uri` 二选一。                                                                            |
| `uri`                | `string?`      | 要打印的 PDF，与 `html` 二选一。                                                                            |
| `width`              | `number?`      | 页面宽度，按 72 PPI 换算，默认 `612`。只在打印 `html` 时生效。                                              |
| `height`             | `number?`      | 页面高度，按 72 PPI 换算，默认 `792`。只在打印 `html` 时生效。                                              |
| `margins`            | `PageMargins?` | 页面边距，默认各侧为 0。官方标为 iOS 专属，这里可用，只在打印 `html` 时生效。                               |
| `textZoom`           | `number?`      | 文字缩放百分比，默认 `100`。官方标为 Android 专属，这里可用，只在打印 `html` 时生效。                       |
| `orientation`        | `string?`      | 取 `Orientation.portrait` 或 `Orientation.landscape`。官方标为 iOS 专属，这里可用，只在打印 `html` 时生效。 |
| `printerUrl`         | `string?`      | 不生效。                                                                                                    |
| `useMarkupFormatter` | `boolean?`     | 不生效。                                                                                                    |
| `markupFormatterIOS` | `string?`      | 不生效。                                                                                                    |

> **未实现的内容**
>
> - `Printer`：只用于 `selectPrinterAsync`，HarmonyOS 上取不到。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
