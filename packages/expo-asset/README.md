# @expo-harmony/expo-asset

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-asset) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/asset/)

为 HarmonyOS 上的 React Native 应用提供 Expo Asset 的原生实现，与官方同版本的 `expo-asset` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-asset expo-asset@55.0.18
```

## API 对照表

### Hooks

#### `useAssets(moduleIds)`

返回 `[Asset[] | undefined, Error | undefined]`。资源就绪前第一项是 `undefined`，加载失败时第二项是错误。动态改变传入的资源列表不会触发重新加载。

### Classes

#### `Asset`

表示应用中的一个资源，提供名称、类型等元数据和加载资源的方法。

#### `Asset.downloaded`

类型：`boolean`

`downloadAsync()` 完成后为 `true`，默认 `false`。

#### `Asset.hash`

类型：`string | null`，只读

资源数据的 MD5 值，没有时为 `null`。

#### `Asset.height`

类型：`number | null`

图片高度除以缩放系数后的值。

#### `Asset.localUri`

类型：`string | null`

`downloadAsync()` 完成后指向本地文件的 `file://` 地址。

#### `Asset.name`

类型：`string`

不含扩展名、也不含 `@` 起缩放后缀的文件名。

#### `Asset.type`

类型：`string`，只读

文件扩展名。

#### `Asset.uri`

类型：`string`，只读

资源数据地址。开发时指向 Metro 开发服务器；打包后是 `asset://` 开头的应用内资源路径，可以直接交给 `Image` 使用。这一点和 Android 用资源名、iOS 用包内相对路径不同。

#### `Asset.width`

类型：`number | null`

图片宽度除以缩放系数后的值。

#### `Asset.downloadAsync()`

返回 `Promise<Asset>`。把资源数据下载到应用缓存目录，文件名形如 `ExponentAsset-{cacheFileId}.{extension}`。

缓存里已有同名文件时，资源带 `hash` 会校验内容，不匹配则重新下载；没有 `hash` 时直接复用。缓存目录由系统管理，应用会话之间不保证保留。

支持 `http`、`https`、`asset://`、`rawfile://` 和本地 `file://` 地址；不带协议的地址按打包资源处理。`file://` 直接返回，`asset://` 和 `rawfile://` 从应用内打包资源复制，其他协议报错。下载允许使用计费网络和漫游。

#### `Asset.fromMetadata(meta)`

用资源元数据构造 `Asset`。hash 相同的资源重复构造返回同一个实例。

#### `Asset.fromModule(virtualAssetModule)`

参数是 `require('path/to/file')` 的返回值、外部网络 URL，或含 `uri`、`width`、`height` 的对象。传入模块 ID 时按 `require` 的结果解析，找不到对应的打包资源会抛出错误。

#### `Asset.fromURI(uri)`

按地址构造 `Asset`。同一个地址重复调用返回同一个实例。

#### `Asset.loadAsync(moduleId)`

返回 `Promise<Asset[]>`。`Asset.fromModule(module).downloadAsync` 的便捷封装。参数可以是单个资源或数组，全部保存到磁盘后返回 `Asset` 数组。

### Types

#### `AssetDescriptor`

| 属性             | 类型             |
| ---------------- | ---------------- |
| `hash`（可选）   | `string \| null` |
| `height`（可选） | `number \| null` |
| `name`           | `string`         |
| `type`           | `string`         |
| `uri`            | `string`         |
| `width`（可选）  | `number \| null` |

#### `AssetMetadata`

`Pick<PackagerAsset, 'httpServerLocation' | 'name' | 'hash' | 'type' | 'scales' | 'width' | 'height'>` 加上：

| 属性                 | 类型       |
| -------------------- | ---------- |
| `fileHashes`（可选） | `string[]` |
| `fileUris`（可选）   | `string[]` |
| `uri`（可选）        | `string`   |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
