# @expo-harmony/expo-video-thumbnails

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-video-thumbnails) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/video-thumbnails/)

为 HarmonyOS 上的 React Native 应用提供 Expo VideoThumbnails 的原生实现，与官方同版本的 `expo-video-thumbnails` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 20（HarmonyOS 6.0.0）。

```bash
npm install @expo-harmony/expo-video-thumbnails expo-video-thumbnails
```

## API 对照表

### Methods

#### `VideoThumbnails.getThumbnailAsync(sourceFilename, options?)`

从视频中提取一帧并保存为 JPEG，返回 `Promise<VideoThumbnailsResult>`。`sourceFilename` 接受 HTTP(S) 地址、`file://` URI 或应用可读取的绝对路径。

| 参数 | 类型 | 默认值 | HarmonyOS 行为 |
| --- | --- | --- | --- |
| `options.time` | `number` | `0` | 提取位置，单位为毫秒；小数部分截断，使用距离该时间点最近的同步帧。非有限值或超出安全范围时拒绝调用。负值或超出视频时长的值由设备媒体解码器处理。 |
| `options.quality` | `number` | `1` | JPEG 质量，范围为 `0` 到 `1`，值越大质量越高；超出范围或不是有限数值时拒绝调用。 |
| `options.headers` | `Record<string, string>` | `{}` | HTTP(S) 视频请求头，本地视频不使用此参数。 |

相邻时间可能得到同一张缩略图。HarmonyOS 支持的本地视频格式、编码和分辨率取决于设备媒体解码器。

每次调用会生成一个 JPEG 文件，保存在应用缓存目录中。返回值的 `uri` 是 `file://` URI，可用作图片资源地址；`width` 和 `height` 是提取帧的宽高。系统可能清理缓存中的文件。

未实现项：

- `content://`、`asset://`、`rawfile://` 和 data URI 不受支持；HarmonyOS 实现只接受 HTTP(S)、`file://` URI 或绝对路径。

### Types

#### `VideoThumbnailsOptions`

`getThumbnailAsync` 的可选参数。包含 `quality`、`time` 和 `headers`，具体行为见该方法的参数表。

#### `VideoThumbnailsResult`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `uri` | `string` | JPEG 文件的 `file://` URI。 |
| `width` | `number` | 提取帧的宽度。 |
| `height` | `number` | 提取帧的高度。 |

### Error codes

#### `ERR_VIDEO_THUMBNAILS_INVALID_ARGUMENT`

`quality` 不是 `0` 到 `1` 之间的有限数值，或 `time` 不是有限数值、超出安全范围时，Promise 以此错误拒绝。

#### `ERR_INVALID_SOURCE_FILENAME`

`sourceFilename` 不是 HTTP(S) 地址、`file://` URI 或绝对路径时，Promise 以此错误拒绝。

#### `ERR_THUMBNAIL_FILE`

本地视频源不是常规文件或为空时，Promise 以此错误拒绝。

#### `E_VIDEO_THUMBNAILS`

设备不支持视频帧提取，或提取、解码、保存缩略图失败时，Promise 以此错误拒绝。

### Permissions

#### `ohos.permission.INTERNET`

获取 HTTP(S) 视频缩略图需要网络访问。本包声明此普通权限；处理应用可读取的本地视频不需要媒体库读取权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
