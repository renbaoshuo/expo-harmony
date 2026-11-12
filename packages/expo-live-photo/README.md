# @expo-harmony/expo-live-photo

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-live-photo) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/live-photo/)

为 HarmonyOS 上的 React Native 应用提供 Expo Live Photo 的原生实现，与官方同版本的 `expo-live-photo` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 20（HarmonyOS 6.0.0）。

```bash
npm install @expo-harmony/expo-live-photo expo-live-photo
```

## API 对照表

### Methods

#### `LivePhotoView.isAvailable()`

返回 `boolean`，设备是否支持显示实况照片。HarmonyOS SDK API 20 以下或系统不支持实况照片时返回 `false`。

#### `LivePhotoViewType.startPlayback(playbackStyle?)`

返回 `void`，开始播放视频部分。`playbackStyle` 可传 `'hint'` 或 `'full'`，省略时为 `'full'`。资源尚未加载完成时调用不会开始播放；设备不支持实况照片时抛出 `UnavailabilityError`。

#### `LivePhotoViewType.stopPlayback()`

返回 `void`，停止播放视频部分。设备不支持实况照片时抛出 `UnavailabilityError`。

### Event subscriptions

以下事件作为 `LivePhotoView` 的属性传入，回调不接收参数。

#### `onLoadStart`

开始加载非空 `source` 时调用。

#### `onPreviewPhotoLoad`

静态图片加载完成并可显示时调用。

#### `onLoadComplete`

图片和视频均加载完成、可以播放时调用，在 `onPreviewPhotoLoad` 之后触发。

#### `onLoadError(error)`

加载失败时调用，`error` 类型为 `LivePhotoLoadError`。播放期间发生系统错误时会停止播放并保留静态预览，不会通过此事件报告。

#### `onPlaybackStart`

视频开始播放时调用。

#### `onPlaybackStop`

视频停止播放时调用，包括播放结束、暂停，以及更换资源或修改播放相关属性导致的停止。

### Types

#### `LivePhotoViewProps`

`LivePhotoView` 接受 React Native `ViewProps`，并增加以下属性。设备不支持实况照片时，视图不显示内容；可用 `LivePhotoView.isAvailable()` 查询支持状态。

##### `source`

类型：`LivePhotoAsset | null`，默认 `null`。

要显示的实况照片资源。`photoUri` 和 `pairedVideoUri` 都需要指向应用可读取的沙箱文件，支持文件 URI 或绝对路径；网络资源需先保存到沙箱。文件 URI 不能带查询参数或片段。使用 HarmonyOS 上的 `expo-image-picker` 选择实况照片时，可以将 `asset.uri` 和 `asset.pairedVideoAsset.uri` 分别传入这两个字段；读取所选文件不需要申请访问整个图库的权限。

将 `source` 设为 `null` 会清空内容并停止播放。传入其他资源会停止当前播放并重新加载。缺少字段或地址无效时触发 `onLoadError`；修复后重新传入 `source` 可以重试，包括重新传入相同地址。图片和视频的格式、编解码及配对关系由系统决定。

##### `isMuted`

类型：`boolean`，默认 `true`。控制播放时是否静音。修改后会停止当前播放。

##### `contentFit`

类型：`ContentFit`，默认 `'contain'`。控制静态图片的缩放方式。修改后会重新加载资源。

##### `useDefaultGestureRecognizer`

类型：`boolean`，默认 `true`。启用后，用户长按视图即可开始播放。修改后会停止当前播放。

#### `LivePhotoAsset`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `photoUri` | `string` | 图片部分的地址。 |
| `pairedVideoUri` | `string` | 视频部分的地址。 |

两个地址都需要指向应用可读取的本地文件。

#### `LivePhotoLoadError`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `message` | `string` | 加载失败的原因。 |

#### `LivePhotoViewStatics`

包含静态方法 `isAvailable()`，用于查询设备是否支持显示实况照片。

#### `LivePhotoViewType`

包含 `startPlayback(playbackStyle?)` 和 `stopPlayback()`，用于控制视频播放。

### Enums

#### `ContentFit`

取值为 `'contain' | 'cover'`。`'contain'` 在容器内完整显示图片；`'cover'` 铺满容器，可能裁去图片边缘。

#### `PlaybackStyle`

取值为 `'hint' | 'full'`。HarmonyOS 上两种取值都会播放完整视频。

- `'hint'`：HarmonyOS 不提供短片段提示播放模式。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
