# @expo-harmony/expo-sharing

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-sharing) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/sharing/)

为 HarmonyOS 上的 React Native 应用提供 Expo Sharing 的原生实现，与官方 `expo-sharing` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-sharing expo-modules-core@~57.0.24 expo-sharing@~57.0.24
```

## 接收分享

要接收其他应用分享的数据，请在 `app.json` 的 `plugins` 中加入 `@expo-harmony/expo-sharing`：

```json
{
  "expo": {
    "plugins": ["@expo-harmony/expo-sharing"]
  }
}
```

配置会在指定的 Ability 上启用分享接收。默认接收文本、文件和 HTTP(S) 链接，每次最多接收 500 项。可以通过 `utds`、`maxFileSupported`、`allowMultiple` 和 `abilityName` 设置可接收的数据类型、数量上限、是否一次接收多项数据以及目标 Ability。`maxFileSupported` 可设为 1 到 500。目标 Ability 必须已存在，并设置 `exported: true`。此配置只用于接收分享。

Bare 工程还需按[接入说明](https://github.com/renbaoshuo/expo-harmony/blob/master/docs/BareInstallation.md)完成 HarmonyOS 配置。

收到的数据由目标 Ability 交给应用。设置 Expo `scheme` 后，系统可通过 `<scheme>://expo-sharing` 打开应用；对应页面可以调用 `useIncomingShare()` 读取数据。未设置 `scheme` 时，也可以在当前页面读取数据。

## API 对照表

### Hooks

#### `useIncomingShare()`

返回 `UseIncomingShareResult`。页面挂载时读取已接收的数据，收到新分享或应用回到前台时更新结果；页面离开后停止监听。

接收数据已就绪时，首次渲染即可同步获得 `sharedPayloads`；仍在加载时先返回空数组，加载完成后更新。

### Methods

#### `Sharing.shareAsync(url, options)`

参数：`url: string`，可读取的本地 `file://` 文件地址；`options?: SharingOptions`，省略时使用空对象。返回 `Promise<void>`，系统分享面板关闭后完成，不返回用户的选择结果。

分享内容类型按 `options.mimeType` 判定，未提供时按文件扩展名判定。识别为图片或视频时，面板会展示内容预览；其他类型以普通卡片展示。文本文件也作为文件分享，原文件内容保持不变。

#### `Sharing.isAvailableAsync()`

返回 `Promise<boolean>`。应用位于前台且设备支持系统分享时为 `true`，否则为 `false`。

#### `Sharing.getSharedPayloads()`

同步返回 `SharePayload[]`，包含最近一次接收的分享数据；没有数据或数据仍在加载时返回空数组。每条数据对应一个分享条目，内容为空的条目会被跳过。单次最多接收 500 条数据，描述信息总量上限为 200 KB，文件内容不计入此限制。

#### `Sharing.getResolvedSharedPayloadsAsync()`

返回 `Promise<ResolvedSharePayload[]>`，在原始数据上补充读取内容所需的信息。解析 HTTP(S) 链接需要网络连接；每次接收新的分享后会重新解析。

链接解析会跟随重定向，连接和读取超时各为 5 秒。`contentUri` 指向重定向后的地址，`value` 保留原始链接；MIME 类型、文件名和大小取自响应头，缺少 `Content-Type` 时按 `text/plain` 处理。接收的文件会复制到应用缓存目录的 `expo-sharing` 子目录，`contentUri` 指向副本。空间不足或复制失败时 Promise 会拒绝，并清理本次未能返回的副本。

已经返回的副本会保留在缓存目录中；清空接收状态或收到新分享都不会删除这些副本。

#### `Sharing.clearSharedPayloads()`

清空接收状态；之后 `getSharedPayloads()` 返回空数组。已经返回的缓存副本不会被删除。

### Event subscriptions

#### `onSharedPayloadsChanged`

接收新分享或清空接收状态后发出通知，不携带参数。订阅返回 `EventSubscription`。`useIncomingShare()` 会自动订阅，并在应用回到前台时重新读取数据。

### Types

#### `SharePayload`

一条原始分享数据。HarmonyOS 返回的 `value`、`shareType` 和 `mimeType` 均有值。

| 属性        | 类型        | 说明                                                  |
| ----------- | ----------- | ----------------------------------------------------- |
| `value`     | `string`    | 文件地址或文本内容                                    |
| `shareType` | `ShareType` | 分享内容的类型                                        |
| `mimeType`  | `string`    | 内容的 MIME 类型，无法识别时按分享类型使用默认值 |

默认 MIME 类型为：文本和链接使用 `text/plain`，音频、图片和视频使用对应的 `audio/*`、`image/*`、`video/*`，其他文件使用 `application/octet-stream`。

#### `ResolvedSharePayload`

`UriBasedResolvedSharePayload | TextBasedResolvedSharePayload`，表示解析后的分享数据。

#### `BaseResolvedSharePayload`

`SharePayload` 加上以下字段：

| 属性              | 类型                  | 说明                                                                                               |
| ----------------- | --------------------- | -------------------------------------------------------------------------------------------------- |
| `contentUri`      | `string \| null`      | 内容地址。链接为重定向后的 URL，文件为缓存副本地址，纯文本为 `null`                                   |
| `contentType`     | `ContentType \| null` | 内容类型；纯文本为 `null`                                                                            |
| `contentMimeType` | `string \| null`      | 内容的 MIME 类型；纯文本为 `null`                                                                    |
| `originalName`    | `string \| null`      | 文件名。链接取 `Content-Disposition` 或 URL 的末段，文件优先使用分享方名称，纯文本为 `null`          |
| `contentSize`     | `number \| null`      | 内容大小，单位字节。链接取 `Content-Length`，文件取副本的实际大小；纯文本或响应头缺失时为 `null`      |

#### `UriBasedResolvedSharePayload`

文件和链接类数据的解析结果，`contentType` 为 `'audio' | 'file' | 'video' | 'image' | 'website'`，`contentUri` 必有值。

#### `TextBasedResolvedSharePayload`

纯文本数据的解析结果，`contentUri`、`contentType`、`contentMimeType`、`originalName` 和 `contentSize` 均为 `null`。

#### `ContentType`

`'text' | 'audio' | 'image' | 'video' | 'file' | 'website'`。`text/html` 和 XHTML 归为 `'website'`，其他已识别 MIME 类型按前缀归类；无法识别的文件类型按原始分享类型兜底。链接按响应的 `Content-Type` 判定，缺少该响应头时按 `text/plain` 处理，无法识别的链接 MIME 类型归为 `'file'`。

#### `ShareType`

`'text' | 'url' | 'audio' | 'image' | 'video' | 'file'`。根据分享方声明的数据类型归类；无法识别时，HTTP(S) 地址归为 `'url'`，文件地址归为 `'file'`，其他内容归为 `'text'`。

#### `SharingOptions`

| 选项          | 说明                                                                                                                       |
| ------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `anchor`      | 分享面板的弹出位置。`x`、`y` 是相对窗口的偏移，`width`、`height` 是锚点区域的尺寸，负的尺寸按 0 处理；省略时位置由系统决定 |
| `mimeType`    | 分享内容的 MIME 类型，用于判定面板中的展示形态，未提供时按文件扩展名判定                                                   |

不支持以下选项：

- `dialogTitle`：系统分享面板不支持自定义标题。
- `UTI`：HarmonyOS 上不适用；可用 `mimeType` 指定内容类型。

#### `UseIncomingShareResult`

| 属性                     | 类型                     | 说明                                   |
| ------------------------ | ------------------------ | -------------------------------------- |
| `sharedPayloads`         | `SharePayload[]`         | 未解析的原始数据                       |
| `resolvedSharedPayloads` | `ResolvedSharePayload[]` | 解析后的数据，解析中或失败时为空数组   |
| `isResolving`            | `boolean`                | 是否正在解析                           |
| `error`                  | `Error \| null`          | 解析失败时的错误，成功为 `null`        |
| `clearSharedPayloads`    | `() => void`             | 清空接收状态，已返回的缓存文件不受影响 |
| `refreshSharePayloads`   | `() => void`             | 重新读取并解析，解析失败后可以用它重试 |

### Error codes

#### `ERR_SHARING_INVALID_ARGS`

`url` 为空字符串时抛出。

#### `ERR_SHARING_INVALID_URL`

`url` 不是可读取的本地 `file://` 文件地址时抛出。

#### `ERR_SHARING_UNAVAILABLE`

应用不在前台、没有可用窗口，或设备不支持系统分享时抛出。

#### `ERR_SHARING_IN_PROGRESS`

上一次分享面板尚未关闭时再次调用 `shareAsync()` 抛出。

#### `ERR_SHARING_FAILED`

生成分享文件地址或打开系统分享面板失败时抛出。

#### `ERR_SHARING_RUNTIME_DESTROYED`

应用运行时关闭或重载后继续调用分享接口时抛出。

#### `ERR_FAILED_TO_RESOLVE_SHARED_DATA`

读取或解析接收的数据失败时抛出，例如 URL 请求失败、文件地址不可读或缓存副本无法创建。

#### `ERR_SHARING_ABILITY_NOT_INITIALIZED`

宿主 Ability 尚未启用本包的分享接收能力时抛出。

#### `ERR_INVALID_ARGUMENT_TYPE`

`options`、`anchor` 或其字段的类型不符合要求时抛出。

### Permissions

#### `ohos.permission.INTERNET`

解析接收的 HTTP(S) 链接时需要网络访问权限。本包已声明此权限，无需运行时弹窗授权；分享本地文件或解析接收的文件不需要此权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
