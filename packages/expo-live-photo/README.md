# @expo-harmony/expo-live-photo

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-live-photo) | [Expo 官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/live-photo/)

为 HarmonyOS 上的 React Native 应用提供 Expo LivePhoto 的原生实现，与官方同版本的 `expo-live-photo` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-live-photo expo-live-photo@55.0.15
```

鸿蒙适配会通过 Autolinking 自动接入，无需额外配置插件或申请权限。最低支持 HarmonyOS 6.0.0（API 20），宿主的 `compatibleSdkVersion` 也需满足此要求。业务代码依旧使用官方包：

```tsx
import { LivePhotoView } from 'expo-live-photo';

<LivePhotoView source={{ photoUri, pairedVideoUri }} style={{ width: 300, height: 240 }} contentFit="contain" isMuted />;
```

`photoUri` 与 `pairedVideoUri` 须指向应用可读取的沙箱文件，支持文件 URI 或绝对路径。网络资源或相册媒体应由调用方先保存为本地图片和视频，不接受带查询参数或片段的文件 URI。

## API 对照表

### Component

#### `LivePhotoView`

实况照片视图，显示静态图片，播放时呈现配对的视频。除下列属性外还接受 `ViewProps`。设备不支持时渲染为空并打印警告。

#### `source`

类型：`LivePhotoAsset | null`，默认 `null`

要显示的实况照片资源。`photoUri` 与 `pairedVideoUri` 须指向应用可读取的沙箱文件，支持文件 URI 或绝对路径。网络资源或相册媒体应由调用方先保存为本地图片和视频；带查询参数或片段的文件 URI 被拒绝。赋 `null` 清空当前内容并停止播放，换成另一个资源会停止当前播放并重新加载。

字段缺失或地址非法时触发 `onLoadError`，不触发 `onLoadComplete`；重新设置有效资源可以恢复。图片与视频的格式和编解码兼容性由系统决定，不校验 Apple Live Photo 的配对元数据，iOS 的图片与 MOV 组合不保证能直接播放。

#### `isMuted`

类型：`boolean`，默认 `true`

播放时是否静音。修改该值会停止当前播放。

#### `contentFit`

类型：`ContentFit`，默认 `'contain'`

图片在容器内的缩放方式。修改该值会重新加载资源。

#### `useDefaultGestureRecognizer`

类型：`boolean`，默认 `true`

是否启用默认长按手势。为 `true` 时用户长按视图开始播放。修改该值会停止当前播放。长按的视觉反馈与 iOS 不同。

#### `onLoadStart`

类型：`() => void`

开始加载资源时调用。

#### `onPreviewPhotoLoad`

类型：`() => void`

静态图片加载完成、可以显示时调用。

#### `onLoadComplete`

类型：`() => void`

图片与视频均加载完成、可以播放时调用，在 `onPreviewPhotoLoad` 之后。

#### `onLoadError`

类型：`(error: LivePhotoLoadError) => void`

加载或播放失败时调用。系统无法给出具体原因时 `message` 为通用说明。

#### `onPlaybackStart`

类型：`() => void`

播放开始时调用。

#### `onPlaybackStop`

类型：`() => void`

播放停止时调用，包括正常结束、暂停，以及更换资源或修改属性导致的停止。

### Static methods

#### `LivePhotoView.isAvailable()`

返回 `boolean`，设备是否支持显示实况照片。

### Component methods

#### `startPlayback(playbackStyle?)`

开始播放视频部分。`playbackStyle` 取 `'hint'` 或 `'full'`，省略时按 `'full'`。资源未加载完成时调用没有效果。组件不可用时抛出 `UnavailabilityError`。

#### `stopPlayback()`

停止播放视频部分。组件不可用时抛出 `UnavailabilityError`。

### Types

#### `ContentFit`

`'contain' | 'cover'`。`'contain'` 让较大的一边贴合容器，`'cover'` 铺满容器。

#### `LivePhotoAsset`

| 属性             | 类型     | 说明             |
| ---------------- | -------- | ---------------- |
| `photoUri`       | `string` | 图片部分的地址。 |
| `pairedVideoUri` | `string` | 视频部分的地址。 |

两个地址须指向应用可读取的本地文件。

#### `LivePhotoLoadError`

| 属性      | 类型     | 说明             |
| --------- | -------- | ---------------- |
| `message` | `string` | 加载失败的原因。 |

#### `LivePhotoViewStatics`

| 属性          | 类型            | 说明                       |
| ------------- | --------------- | -------------------------- |
| `isAvailable` | `() => boolean` | 设备是否支持显示实况照片。 |

#### `LivePhotoViewType`

| 属性            | 类型                                      | 说明       |
| --------------- | ----------------------------------------- | ---------- |
| `startPlayback` | `(playbackStyle?: PlaybackStyle) => void` | 开始播放。 |
| `stopPlayback`  | `() => void`                              | 停止播放。 |

#### `PlaybackStyle`

`'hint' | 'full'`。`'hint'` 本意是播放一小段用于提示实况照片，`'full'` 播放完整视频。HarmonyOS 上没有短片段播放模式，两种取值都播放完整视频。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
