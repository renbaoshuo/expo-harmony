# @expo-harmony/expo-clipboard

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-clipboard) | [Expo 上游官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/clipboard/)

为 HarmonyOS 上的 React Native 应用提供 Expo Clipboard 的原生实现，与官方同版本的 `expo-clipboard` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-clipboard expo-clipboard@55.0.13
```

鸿蒙适配会通过 Autolinking 自动接入，无需额外配置。最低支持 HarmonyOS 5.0.2（API 14），宿主的 `compatibleSdkVersion` 也需满足此要求。

读取剪贴板需要 `ohos.permission.READ_PASTEBOARD`，本包已经声明并配置好用途说明（也可以参照下方的 `clipboardPermission` 配置自定义文本），正常情况下无需再次声明。这个权限只在读内容时用到，读之前如果没有就弹窗申请；弹窗只在前台出现，后台读取直接失败，用户拒绝后返回 `ERR_NO_PERMISSION`。权限声明挂在 `EntryAbility` 名下，Host 的入口 Ability 如果叫别的名字，需要改成自己的 Ability 名称。写入、查询内容类型和监听变化都不读内容，不会申请这个权限。

业务代码依旧使用官方包：

```ts
import * as Clipboard from 'expo-clipboard';

await Clipboard.setStringAsync('Hello HarmonyOS');
const text = await Clipboard.getStringAsync();
```

## Config Plugin

`clipboardPermission` 是 HarmonyOS 的构建期配置扩展，需要自定义读取权限的用途说明时，在应用配置中添加：

```json
{
  "expo": {
    "plugins": [["@expo-harmony/expo-clipboard", { "clipboardPermission": "用于粘贴您复制的订单编号" }]]
  }
}
```

该选项只接受非空字符串，不支持用 `false` 关闭权限。未配置时使用默认文案「用于粘贴您复制的文字、链接和图片」。修改配置后需要重新 prebuild 并构建应用。

## API 对照表

### Component

> **未实现的内容**
>
> - `ClipboardPasteButton`：官方只在 iOS 上提供该组件，HarmonyOS 上没有对应的系统粘贴控件，渲染结果为空。

### Constants

#### `isPasteButtonAvailable`

类型：`boolean`，HarmonyOS 上恒为 `false`。

### Methods

#### `Clipboard.getStringAsync(options?)`

返回 `Promise<string>`，读取剪贴板中的文本。`options` 见 `GetStringOptions`。

默认返回纯文本。剪贴板中只有 HTML 时返回系统转换后的纯文本，只有 URL 时返回 URL 字符串。`preferredFormat` 为 `html` 时优先返回 HTML 原文，没有 HTML 时把纯文本或 URL 转换成 HTML。剪贴板中没有文本或 URL 时返回空字符串，不申请权限。读取需要读取权限。

HTML 转纯文本由系统完成，标签支持和换行行为遵循系统版本，可能与 Android、iOS 不同。系统在 API 20 起支持 `<br>` 换行标签；纯文本转 HTML 时会转义特殊字符，并使用段落保留换行，以兼容 API 14。

#### `Clipboard.setStringAsync(text, options?)`

返回 `Promise<boolean>`，写入文本，HarmonyOS 上恒为 `true`。`options.inputFormat` 为 `html` 时按 HTML 写入，同时保存一份系统转换后的纯文本，之后按纯文本读取会得到转换结果。写入会替换剪贴板原有内容。并发发起的读写会排队依次执行，返回顺序与调用顺序一致。

#### `Clipboard.setString(text)`

写入纯文本，无返回值。官方已标记废弃，行为与 `setStringAsync(text)` 相同，但不等待写入完成。

#### `Clipboard.hasStringAsync()`

返回 `Promise<boolean>`，剪贴板中是否有文本，纯文本和 HTML 都算。不需要读取权限。

#### `Clipboard.getUrlAsync()`

返回 `Promise<string | null>`，读取剪贴板中的 URL，没有则返回 `null`。官方标记为 iOS 专属，HarmonyOS 上可用。URL 使用系统 URI 类型，普通文本不会被识别为 URL。读取需要读取权限。

#### `Clipboard.setUrlAsync(url)`

返回 `Promise<void>`，按 URL 类型写入，其他应用可以识别为链接。官方标记为 iOS 专属，HarmonyOS 上可用。

#### `Clipboard.hasUrlAsync()`

返回 `Promise<boolean>`，剪贴板中是否有 URL 内容。官方标记为 iOS 专属，HarmonyOS 上可用。不需要读取权限。

#### `Clipboard.getImageAsync(options)`

返回 `Promise<ClipboardImage | null>`，读取剪贴板中的图片，没有图片时返回 `null`，不申请权限。`options.format` 取 `png` 或 `jpeg`，`jpegQuality` 取 0 到 1，只对 JPEG 生效。`data` 已带 `data:image/...;base64,` 前缀，可直接用作 `Image` 组件的来源；`size` 是图片的像素尺寸。动画图片按系统默认帧处理，不保留动图。图片处理受设备内存、临时存储和系统编解码能力限制。读取需要读取权限，编码失败时抛出 `ERR_PASTE_FAILURE`。

#### `Clipboard.setImageAsync(base64Image)`

返回 `Promise<void>`，写入图片。`base64Image` 是不带 `data:` 前缀的 Base64 字符串。内容不是可解码的图片时抛出 `ERR_INVALID_IMAGE`，写入失败时抛出 `ERR_COPY_FAILURE`。

#### `Clipboard.hasImageAsync()`

返回 `Promise<boolean>`，剪贴板中是否有图片。不需要读取权限。

### Event Subscriptions

#### `Clipboard.addClipboardListener(listener)`

返回 `EventSubscription`，订阅剪贴板变化。回调收到 `ClipboardEvent`，`contentTypes` 列出当前内容类型。

只在应用处于前台且存在订阅时发送事件，应用在后台发生的复制不会在回到前台后补发。取消订阅调用返回对象的 `remove()`。

#### `Clipboard.removeClipboardListener(subscription)`

移除 `addClipboardListener` 添加的订阅，无返回值。官方已标记废弃，建议改用 `subscription.remove()`。

### Interfaces

#### `Subscription`

`EventSubscription` 的别名，提供 `remove()` 用于取消订阅。

### Types

#### `ClipboardEvent`

`contentTypes: ContentType[]`，剪贴板上可用的内容类型。

#### `ClipboardImage`

`data: string`，带 `data:` 前缀的 Base64 图片；`size: { width: number; height: number }`，图片的像素尺寸。

#### `GetImageOptions`

`format: 'png' | 'jpeg'`，输出格式；`jpegQuality?: number`，取值 0 到 1，默认 `1`，只对 JPEG 生效。

#### `GetStringOptions`

`preferredFormat?: StringFormat`，期望的字符串格式，默认 `StringFormat.PLAIN_TEXT`。

#### `SetStringOptions`

`inputFormat?: StringFormat`，写入字符串的格式，默认 `StringFormat.PLAIN_TEXT`。

> **未实现的内容**
>
> - `AcceptedContentType`、`CornerStyleType`、`DisplayModeType`、`PasteEventPayload`、`TextPasteEvent`、`ImagePasteEvent`：只在 `ClipboardPasteButton` 上使用，该组件在 HarmonyOS 上不可用。

### Enums

#### `ContentType`

| 成员         | 值             |
| ------------ | -------------- |
| `PLAIN_TEXT` | `'plain-text'` |
| `HTML`       | `'html'`       |
| `IMAGE`      | `'image'`      |
| `URL`        | `'url'`        |

官方把 `URL` 标记为 iOS 专属，HarmonyOS 上可用。

#### `StringFormat`

| 成员         | 值            |
| ------------ | ------------- |
| `PLAIN_TEXT` | `'plainText'` |
| `HTML`       | `'html'`      |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
