# @expo-harmony/expo-image-loader

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-image-loader)

为 HarmonyOS 上的 React Native 应用提供 Expo ImageLoader 的原生实现，与官方 `expo-image-loader` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-image-loader expo-image-loader@~57.0.1
```

## API 对照表

### Constants

#### `ImageLoaderInterfaceKey`

类型：`ExpoServiceKey<ImageLoaderInterface>`。用于取得 `ImageLoaderInterface` 接口。

### Methods

#### `ImageLoaderInterface.loadImageForDisplayFromURL(url)`

参数 `url` 的类型为 `string`。返回 `Promise<image.PixelMap>`，解析为供展示的图片。返回图片保持原始尺寸，不做降采样；动画图片只取第一帧，系统能读到 EXIF 方向时按方向摆正。

支持以下地址形式：

- `http://`、`https://` 远程地址，使用系统 HTTP 缓存，响应大小不能超过 100 MiB。
- 应用沙箱内的绝对路径，以 `/` 开头。
- `file://` 地址，需要应用已经获得该文件的访问授权。
- `data:image/<subtype>[;参数];base64,<数据>` 地址。协议、媒体类型和 `base64` 标记不区分大小写；数据中的空白会被忽略，末尾填充字符 `=` 可以省略。
- `asset://path` 对应 `rawfile/assets/path`；`resource://RAWFILE/path`、`rawfile://path`、`rawfile:path` 和相对资源名对应 `rawfile/path`。

地址为空、协议或打包资源路径无效、`data:` 地址未使用 base64 编码、HTTP 响应码不在 2xx 范围内，或图片解码失败时，Promise 会以 `ERR_IMAGE_LOADER` 拒绝。

#### `ImageLoaderInterface.loadImageForDisplayFromURL(url, listener)`

参数为 `url: string` 和 `listener: ImageLoaderResultListener`。返回 `void`，加载方式与 Promise 形式相同；成功或失败结果分别通过 `onSuccess`、`onFailure` 回调。

#### `ImageLoaderInterface.loadImageForManipulationFromURL(url)`

参数 `url` 的类型为 `string`。返回 `Promise<image.PixelMap>`，加载供编辑的图片。支持的地址形式和方向处理与展示加载相同，图片保持原始尺寸，不做降采样；每次调用返回独立图片，远程图片每次都会重新请求，不使用缓存。

加载失败时，Promise 会以 `ERR_IMAGE_LOADER` 拒绝。

#### `ImageLoaderInterface.loadImageForManipulationFromURL(url, listener)`

参数为 `url: string` 和 `listener: ImageLoaderResultListener`。返回 `void`，加载方式与 Promise 形式相同；成功或失败结果分别通过 `onSuccess`、`onFailure` 回调。

### Types

#### `ImageLoaderInterface`

提供上述图片加载方法。方法成功时返回可编辑的 `image.PixelMap`；图片不再使用时，调用方须调用 `release()` 释放。

#### `ImageLoaderResultListener`

供调用方实现的图片加载结果监听器。加载成功时调用 `onSuccess`，失败时调用 `onFailure`。

| 成员        | 类型                              | 说明                                              |
| ----------- | --------------------------------- | ------------------------------------------------- |
| `onSuccess` | `(pixel: image.PixelMap) => void` | 图片加载成功后调用；调用方负责释放收到的 `PixelMap` |
| `onFailure` | `(cause: Error) => void`          | 图片加载失败时调用；错误码为 `ERR_IMAGE_LOADER`      |

### Error codes

#### `ERR_IMAGE_LOADER`

地址、资源、文件访问、`data:` 内容、HTTP 状态或 100 MiB 响应上限导致加载失败，以及图片解码失败时，Promise 会以此错误码拒绝，listener 重载会通过 `onFailure` 收到对应错误。

### Permissions

#### `ohos.permission.INTERNET`

用于加载 HTTP(S) 图片，由本包的 HarmonyOS 模块声明。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
