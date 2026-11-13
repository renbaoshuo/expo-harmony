# @expo-harmony/expo-asset

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-asset) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/asset/)

为 HarmonyOS 上的 React Native 应用提供 Expo Asset 的原生实现，与官方 `expo-asset` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-asset expo-asset@~57.0.20
```

## API 对照表

### Hooks

#### `useAssets(moduleIds)`

参数为一个 Metro 资源模块 ID 或模块 ID 数组，返回 `[Asset[] | undefined, Error | undefined]`。资源加载完成前第一项为 `undefined`；加载失败时第二项为错误。组件挂载后动态改变资源列表不会触发重新加载。

### Types

#### `Asset`

资源实例，包含资源地址及可用的名称、类型、尺寸和本地地址等信息。

#### `Asset.downloaded`

类型：`boolean`。下载完成后为 `true`，初始值通常为 `false`。

#### `Asset.hash`

类型：`string | null`，只读。资源的 MD5 值；通过 `Asset.fromURI()` 创建时为 `null`。

#### `Asset.height`

类型：`number | null`。图片高度，按资源缩放系数折算；未提供时为 `null`。

#### `Asset.localUri`

类型：`string | null`。`downloadAsync()` 成功后为指向本地资源的 `file://` 地址；尚无本地地址时为 `null`。

#### `Asset.name`

类型：`string`。打包资源使用元数据中的文件名（不含扩展名及 `@` 缩放后缀）；由 `Asset.fromURI()` 创建时为空字符串。

#### `Asset.type`

类型：`string`，只读。资源文件扩展名；通过 `Asset.fromURI()` 创建时从地址后缀推断，Base64 data URI 则从 MIME 类型推断。

#### `Asset.uri`

类型：`string`，只读。资源来源地址。通过 `Asset.fromURI()` 创建时保留传入地址；打包资源可使用下文 `downloadAsync()` 支持的 HarmonyOS 资源地址。

#### `Asset.width`

类型：`number | null`。图片宽度，按资源缩放系数折算；未提供时为 `null`。

#### `AssetDescriptor`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `name` | `string` | 资源名称 |
| `type` | `string` | 文件扩展名 |
| `uri` | `string` | 资源地址 |
| `hash`（可选） | `string \| null` | 资源 MD5 |
| `width`（可选） | `number \| null` | 图片宽度 |
| `height`（可选） | `number \| null` | 图片高度 |

#### `AssetMetadata`

包含 `PackagerAsset` 的 `httpServerLocation`、`name`、`hash`、`type`、`scales`、`width`、`height` 字段，并可选提供 `uri`、`fileHashes` 和 `fileUris`。

### Methods

#### `new Asset(descriptor)`

以 `AssetDescriptor` 创建资源实例，返回 `Asset`。

#### `Asset.downloadAsync()`

返回 `Promise<Asset>`。下载或读取资源后，`localUri` 指向本地 `file://` 地址，`downloaded` 变为 `true`。系统可能清理本地缓存。

支持 `http://`、`https://`、`file://`、`asset://`、`rawfile://`、`resource://RAWFILE/` 和不带协议的打包资源地址。`file://` 地址会原样作为 `localUri` 返回；不支持的协议会以 `ERR_ASSET_UNSUPPORTED_URI` 拒绝 Promise。

- 不支持 `data:` URI；HarmonyOS 实现不提供将内嵌数据 URI 保存为本地文件的处理。

打包资源中，`asset://` 对应 `resources/rawfile/assets/`，`rawfile://`、`resource://RAWFILE/` 和不带协议的地址对应 `resources/rawfile/`。`rawfile://` 路径按 URL 百分号编码解析，文件名中的 `#`、`?` 等字符应百分号编码；其他打包资源路径按字面值解析。路径不能包含 `..`。

提供 `hash` 时会校验本地缓存内容，不匹配时重新获取资源；没有 `hash` 时会复用已有缓存。HTTP(S) 下载可使用计费网络和漫游网络。

#### `Asset.fromMetadata(meta)`

根据 `AssetMetadata` 创建资源实例。具有相同资源 `hash` 的元数据会返回同一个实例。

#### `Asset.fromModule(virtualAssetModule)`

根据 Metro 资源模块 ID（如 `require('./image.png')` 的返回值）、字符串 URI，或包含 `uri`、`width`、`height` 的对象创建 `Asset`。模块 ID 不在资源注册表中时会抛出错误。

#### `Asset.fromURI(uri)`

根据 URI 创建 `Asset`。重复传入相同 URI 会返回同一个实例。

#### `Asset.loadAsync(moduleIds)`

参数为单个数字模块 ID 或 URI 字符串，或数字 ID 数组、URI 字符串数组。返回 `Promise<Asset[]>`；全部资源加载完成后解析。

### Error codes

#### `ERR_ASSET_DOWNLOAD_FAILED`

HTTP(S) 下载无法启动或完成时，资源 Promise 会携带此 `code` 拒绝。

#### `ERR_ASSET_INVALID_HASH`

`hash` 不是 32 位十六进制 MD5 时，资源 Promise 会携带此 `code` 拒绝。

#### `ERR_ASSET_INVALID_RESOURCE`

打包资源 URI 或路径格式无效时，资源 Promise 会携带此 `code` 拒绝。

#### `ERR_ASSET_INVALID_TYPE`

文件扩展名超过 64 个字符，或包含不支持的字符时，资源 Promise 会携带此 `code` 拒绝。

#### `ERR_ASSET_RESOURCE_UNAVAILABLE`

无法读取对应的打包资源时，资源 Promise 会携带此 `code` 拒绝。

#### `ERR_ASSET_RUNTIME_DESTROYED`

下载尚未完成时 Expo 运行时已结束，资源 Promise 会携带此 `code` 拒绝。

#### `ERR_ASSET_UNSUPPORTED_URI`

URI 使用了不支持的协议时，资源 Promise 会携带此 `code` 拒绝。

#### `ERR_ASSET_WRITE_FAILED`

无法完整写入本地资源文件时，资源 Promise 会携带此 `code` 拒绝。

### Permissions

#### `ohos.permission.INTERNET`

用于 HTTP(S) 资源下载；本包在 HarmonyOS 模块中声明此权限。

## 配置插件

要将资源加入 Harmony 应用包，可在 Expo 配置中加入插件并列出文件或目录，路径相对项目根目录。目录只读取第一层文件。插件支持 `.png`、`.jpg`、`.gif`、`.mp4`、`.mp3`、`.lottie`、`.riv`、`.glb`、`.json` 和 `.db`，字体请使用 `@expo-harmony/expo-font`。

```json
{
  "expo": {
    "plugins": [
      ["@expo-harmony/expo-asset", { "assets": ["./fixtures/example.glb"] }]
    ]
  }
}
```

插件会将资源放在 `expo-asset/` 目录下，各文件名须唯一。用 `Asset.fromURI('rawfile:///expo-asset/example.glb').downloadAsync()` 加载资源。

如果 Expo 配置中已通过 `expo-asset` 插件设置 `assets`，Harmony 插件也会使用这些路径。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
