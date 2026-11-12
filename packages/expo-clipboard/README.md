# @expo-harmony/expo-clipboard

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-clipboard) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/clipboard/)

为 HarmonyOS 上的 React Native 应用提供 Expo Clipboard 的原生实现，与官方同版本的 `expo-clipboard` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 14（HarmonyOS 5.0.2）。

```bash
npm install @expo-harmony/expo-clipboard expo-clipboard
```

## API 对照表

### Constants

#### `isPasteButtonAvailable`

`boolean`，表示设备是否支持系统粘贴控件。为 `false` 时，`ClipboardPasteButton` 不可用。

### Components

#### `Clipboard.ClipboardPasteButton`

HarmonyOS 系统粘贴控件。用户点击并通过系统授权后，`onPress` 收到第一项匹配的内容，类型为 `TextPasteEvent` 或 `ImagePasteEvent`。默认接受纯文本和图片；`acceptedContentTypes` 可设置为纯文本、HTML、图片或 URL。HTML 和 URL 以文本形式回调。没有匹配内容或用户未授权时，不触发 `onPress`。

系统绘制本地化文字和图标。`displayMode` 支持 `iconAndLabel`、`iconOnly`、`labelOnly`；`backgroundColor` 和 `foregroundColor` 设置背景色与前景色。`cornerStyle` 为 `capsule` 或 `dynamic` 时使用胶囊形状，其余取值使用普通形状。`imageOptions` 设置粘贴图片的输出格式。请在 `style` 中设置明确的宽高，并保持控件可见。

#### `ClipboardPasteButtonProps`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `onPress` | `(data: PasteEventPayload) => void` | 用户粘贴成功且有匹配内容时收到文本或图片。 |
| `acceptedContentTypes` | `AcceptedContentType[]` | 接受的内容类型；默认 `['plain-text', 'image']`。传空数组时恢复默认值。 |
| `imageOptions` | `GetImageOptions \| null` | 粘贴图片时采用的格式和质量选项。 |
| `displayMode` | `DisplayModeType \| null` | 显示图标和文字、仅图标或仅文字。 |
| `cornerStyle` | `CornerStyleType \| null` | 设置控件形状；HarmonyOS 将 `capsule`、`dynamic` 显示为胶囊形，其余显示为普通形。 |
| `backgroundColor` | `string \| null` | 控件背景色；省略时使用系统颜色。 |
| `foregroundColor` | `string \| null` | 控件文字和图标颜色；省略时使用系统颜色。 |
| `style` | `StyleProp<Omit<ViewStyle, 'backgroundColor' \| 'borderRadius' \| 'color'>>` | 控件样式，需设置宽和高。颜色和形状使用对应的控件属性设置。 |

### Methods

#### `Clipboard.getStringAsync(options?)`

返回 `Promise<string>`，读取纯文本、HTML 或 URL。无可读内容时返回空字符串。默认使用纯文本格式：先返回纯文本；只有 HTML 时转换为纯文本；只有 URL 时返回 URL 字符串。`preferredFormat: StringFormat.HTML` 优先返回 HTML 原文；没有 HTML 时将纯文本或 URL 转换为 HTML。读取 HTML 时不会加载图片，纯文本转 HTML 会转义特殊字符并用段落保留换行。HTML 的 `<br>` 换行支持从 HarmonyOS API 20 起提供。

`options` 见 `GetStringOptions`。只有剪贴板中存在可读内容时才会申请 `ohos.permission.READ_PASTEBOARD`。

#### `Clipboard.setStringAsync(text, options?)`

返回 `Promise<boolean>`，写入文本并始终返回 `true`。写入会替换剪贴板原有内容。`options.inputFormat` 为 `StringFormat.HTML` 时按 HTML 写入，并同时保存转换后的纯文本；之后读取纯文本会得到转换结果。纯文本中的特殊字符会转义，换行会转换为段落。

#### `Clipboard.hasStringAsync()`

返回 `Promise<boolean>`，剪贴板包含纯文本或 HTML 时为 `true`。无需读取权限。

#### `Clipboard.getUrlAsync()`

返回 `Promise<string | null>`，读取剪贴板中的 URL；没有 URL 时返回 `null`。HarmonyOS 只将系统 URI 类型识别为 URL，普通文本不会作为 URL 返回。读取到 URL 时需要 `ohos.permission.READ_PASTEBOARD`。

#### `Clipboard.setUrlAsync(url)`

返回 `Promise<void>`，以 URL 类型写入内容，使接收方能够识别为链接。

#### `Clipboard.hasUrlAsync()`

返回 `Promise<boolean>`，剪贴板包含 URL 时为 `true`。无需读取权限。

#### `Clipboard.getImageAsync(options)`

返回 `Promise<ClipboardImage | null>`，读取剪贴板中的图片；没有图片时返回 `null`。`options.format` 可为 `png` 或 `jpeg`，HarmonyOS 默认 `jpeg`；`jpegQuality` 取值为 0 到 1，默认 `1`，仅对 JPEG 生效。返回的 `data` 带有 `data:image/...;base64,` 前缀，可直接用作 `Image` 组件的来源；`size` 是像素尺寸。读取到图片时需要 `ohos.permission.READ_PASTEBOARD`。无效的 JPEG 质量值会抛出 `ERR_INVALID_ARGUMENT`，读取或编码失败会抛出 `ERR_PASTE_FAILURE`。

#### `Clipboard.setImageAsync(base64Image)`

返回 `Promise<void>`，写入图片。`base64Image` 是不带 `data:` 前缀的 Base64 图片字符串。内容无法解码为图片时抛出 `ERR_INVALID_IMAGE`，写入失败时抛出 `ERR_COPY_FAILURE`。

#### `Clipboard.hasImageAsync()`

返回 `Promise<boolean>`，剪贴板包含图片时为 `true`。无需读取权限。

### Event subscriptions

#### `Clipboard.addClipboardListener(listener)`

返回 `Subscription`，订阅剪贴板变化。回调参数为 `ClipboardEvent`，其中 `contentTypes` 列出当前剪贴板的内容类型；HTML 内容也会报告为纯文本。只在应用处于前台且存在订阅时发送事件，后台期间的变化不会在应用回到前台后补发。监听无需读取权限。

#### `Clipboard.removeClipboardListener(subscription)`

移除由 `addClipboardListener` 创建的订阅，不返回值。也可调用 `subscription.remove()`。

### Types

#### `ClipboardImage`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `data` | `string` | 带 `data:image/png;base64,` 或 `data:image/jpeg;base64,` 前缀的图片数据。 |
| `size` | `{ width: number; height: number }` | 图片的像素尺寸。 |

#### `ClipboardEvent`

`contentTypes: ContentType[]`，表示剪贴板上可用的内容类型。

#### `GetImageOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `format` | `'png' \| 'jpeg'` | 输出图片格式；HarmonyOS 默认 `jpeg`。 |
| `jpegQuality` | `number` | 可选，0 到 1，默认 `1`，仅对 JPEG 生效。 |

#### `GetStringOptions`

`preferredFormat?: StringFormat`，期望的读取格式，默认 `StringFormat.PLAIN_TEXT`。

#### `SetStringOptions`

`inputFormat?: StringFormat`，写入内容的格式，默认 `StringFormat.PLAIN_TEXT`。

#### `AcceptedContentType`

`'plain-text' | 'html' | 'image' | 'url'`，可供 `ClipboardPasteButton` 接受的内容类型。

#### `CornerStyleType`

`'dynamic' | 'fixed' | 'capsule' | 'large' | 'medium' | 'small'`，控件形状选项。HarmonyOS 将 `dynamic`、`capsule` 显示为胶囊形，其余取值显示为普通形。

#### `DisplayModeType`

`'iconAndLabel' | 'iconOnly' | 'labelOnly'`，控件图标和文字的显示方式。

#### `PasteEventPayload`

`TextPasteEvent | ImagePasteEvent`，系统粘贴控件回调收到的内容。

#### `TextPasteEvent`

`{ type: 'text'; text: string }`，表示粘贴到的文本内容。

#### `ImagePasteEvent`

`{ type: 'image'; data: string; size: { width: number; height: number } }`，表示粘贴到的图片；`data` 带 `data:image/...;base64,` 前缀。

#### `Subscription`

`EventSubscription` 的别名，提供 `remove(): void` 用于取消订阅。

### Enums

#### `ContentType`

| 成员 | 值 |
| --- | --- |
| `PLAIN_TEXT` | `'plain-text'` |
| `HTML` | `'html'` |
| `IMAGE` | `'image'` |
| `URL` | `'url'` |

HarmonyOS 剪贴板变化事件支持 `URL`。

#### `StringFormat`

| 成员 | 值 |
| --- | --- |
| `PLAIN_TEXT` | `'plainText'` |
| `HTML` | `'html'` |

### Error codes

#### `ERR_NO_PERMISSION`

剪贴板读取权限未声明、不可用、被拒绝，或应用在后台请求读取时抛出。

#### `ERR_INVALID_ARGUMENT`

`getImageAsync` 的 JPEG 质量不是 0 到 1 之间的有限数值时抛出。

#### `ERR_INVALID_IMAGE`

`setImageAsync` 收到的 Base64 内容无法解码为图片时抛出。

#### `ERR_COPY_FAILURE`

写入图片失败时抛出。

#### `ERR_PASTE_FAILURE`

读取或编码剪贴板图片失败时抛出。

#### `ERR_CLIPBOARD`

其他剪贴板操作失败时抛出。

#### `ERR_CLIPBOARD_DESTROYED`

应用运行时已销毁后调用剪贴板 API 时抛出。

### Permissions

#### `ohos.permission.READ_PASTEBOARD`

读取剪贴板中的文本、URL 或图片时需要此受限权限。无对应内容时，读取 API 返回空值且不会申请权限。写入、查询内容类型和监听变化无需此权限；系统粘贴控件由用户操作授权，也无需声明此权限。请按华为的[受限权限说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions#ohospermissionread_pasteboard)申请，并在 `app.json` 的 `expo.harmony.permissions` 中声明：

```json
{
  "name": "ohos.permission.READ_PASTEBOARD",
  "reason": "$string:expo_clipboard_read_permission_reason",
  "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
}
```

将 `EntryAbility` 替换为应用实际的入口 Ability。裸工程可在入口模块的 `module.json5` 中声明。应用签名需使用包含获批权限的 Profile 文件。应用在前台读取时，系统会在尚未授权时请求权限；API 20 起，用户可在系统设置中更改已拒绝权限的状态。

可通过插件选项 `clipboardPermission` 自定义用途说明，值必须为非空字符串。此选项不会自动声明读取权限；未设置时使用默认说明「用于粘贴您复制的文字、链接和图片」。

```json
{
  "expo": {
    "plugins": [["@expo-harmony/expo-clipboard", { "clipboardPermission": "用于粘贴您复制的订单编号" }]]
  }
}
```

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
