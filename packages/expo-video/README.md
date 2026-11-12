# @expo-harmony/expo-video

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-video) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/video/)

为 HarmonyOS 上的 React Native 应用提供 Expo Video 的原生实现，与官方同版本的 `expo-video` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 20（HarmonyOS 6.0.0）。

```bash
npm install @expo-harmony/expo-video expo-video
```

## 使用

```tsx
import { useVideoPlayer, VideoView } from 'expo-video';

export function Player({ uri }: { uri: string }) {
  const player = useVideoPlayer(uri, instance => {
    instance.loop = true;
    instance.play();
  });

  return <VideoView player={player} style={{ width: '100%', height: 240 }} />;
}
```

## API 对照表

### Hooks

#### `useVideoPlayer(source, setup?, playerBuilderOptions?)`

创建 `VideoPlayer`，并在组件卸载时释放。`source` 是播放源；`setup` 在播放器创建后调用；`playerBuilderOptions` 可设置控制栏前进和后退按钮的跳转秒数，默认为 10 秒。

### Methods

#### `createVideoPlayer(source, playerBuilderOptions?)`

创建 `VideoPlayer` 并返回实例。`playerBuilderOptions` 可设置控制栏的跳转步长，未设置时前进和后退均为 10 秒。此方法创建的实例不会随组件卸载自动释放，使用完毕后调用 `release()`。

#### `isPictureInPictureSupported()`

返回 `boolean`，表示系统当前是否允许画中画。

#### `getCurrentVideoCacheSize()`

返回 `0`。HarmonyOS 上不提供持久化视频缓存。

#### `clearVideoCacheAsync()`

返回 `Promise<void>`。HarmonyOS 上没有持久化视频缓存，调用不清除数据；调用前仍须释放所有 `VideoPlayer`，否则 Promise 以 `ERR_VIDEO_CACHE_IN_USE` 拒绝。

#### `setVideoCacheSizeAsync(sizeBytes)`

接收缓存大小（字节），返回 `Promise<void>`。HarmonyOS 上不支持持久化视频缓存，释放所有 `VideoPlayer` 后调用仍会以 `ERR_VIDEO_UNSUPPORTED` 拒绝；仍有播放器时以 `ERR_VIDEO_CACHE_IN_USE` 拒绝。

#### `VideoPlayer.play()`

开始播放。播放器可以在数据源准备完成前接收播放请求；视频视图准备好后按该请求播放。

#### `VideoPlayer.pause()`

暂停播放。

#### `VideoPlayer.replay()`

从开头开始播放。

#### `VideoPlayer.seekBy(seconds)`

相对当前位置前进或后退指定秒数。直播源不支持跳转，会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `VideoPlayer.replace(source)`

替换当前数据源。传入 `null` 或不含 `uri` 的对象会清空数据源。加载失败通过 `statusChange` 事件报告；再次换源会取消前一次加载。

#### `VideoPlayer.replaceAsync(source)`

异步替换当前数据源，返回 `Promise<void>`；加载失败时拒绝。传入 `null` 或不含 `uri` 的对象会清空数据源。没有挂载视图时也可换源；视频准备在视图挂载且有尺寸后进行。再次换源会取消前一次加载。

#### `VideoPlayer.release()`

释放直接通过 `createVideoPlayer()` 创建的播放器。通过 `useVideoPlayer()` 创建的播放器会在组件卸载时自动释放。

#### `VideoPlayer.generateThumbnailsAsync(times, options?)`

从当前数据源提取帧，`times` 为秒数或秒数数组，返回 `Promise<VideoThumbnail[]>`。`options.maxWidth` 和 `maxHeight` 以像素为单位限制尺寸并保持宽高比，只缩小不放大。当前播放器没有数据源时以 `ERR_VIDEO_NO_SOURCE` 拒绝；本地 HLS 播放列表不支持提取缩略图。

#### `VideoView.enterFullscreen()`

进入全屏，返回 `Promise<void>`。全屏不会改变窗口方向；系统返回操作也可退出全屏。`fullscreenOptions.enable` 为 `false` 时调用会以 `ERR_VIDEO_FULLSCREEN_DISABLED` 失败。

#### `VideoView.exitFullscreen()`

退出全屏，返回 `Promise<void>`。

#### `VideoView.startPictureInPicture()`

启动系统画中画，返回 `Promise<void>`。启动前需启用 `allowsPictureInPicture` 并等待 `onFirstFrameRender`。设为 `startsPictureInPictureAutomatically` 后，正在播放的视频在应用进入后台时可自动启动画中画。画中画受设备能力及系统多窗设置影响；视图卸载时画中画结束。[HarmonyOS 画中画](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/pipwindow-xcomponent/)

#### `VideoView.stopPictureInPicture()`

停止系统画中画，返回 `Promise<void>`。

### Event subscriptions

#### `VideoPlayer.addListener(event, listener)`

监听播放器事件。回调接收对应事件负载，返回的订阅对象可调用 `remove()` 取消监听。`timeUpdate` 事件只有在 `timeUpdateEventInterval` 大于 0 时触发。

##### `statusChange`

播放器状态改变时触发，负载含 `status`、`oldStatus`；发生错误时还含 `error.message`。

##### `playingChange`

播放状态改变时触发，负载含 `isPlaying` 和 `oldIsPlaying`。

##### `playbackRateChange`

倍速改变时触发，负载含 `playbackRate` 和 `oldPlaybackRate`。

##### `volumeChange`

音量改变时触发，负载含 `volume` 和 `oldVolume`。

##### `mutedChange`

静音状态改变时触发，负载含 `muted` 和 `oldMuted`。

##### `playToEnd`

播放到当前数据源末尾时触发，不含负载。

##### `timeUpdate`

按 `timeUpdateEventInterval` 触发，负载含 `currentTime`、`bufferedPosition`、`currentLiveTimestamp` 和 `currentOffsetFromLive`。后两项在 HarmonyOS 上始终为 `null`。

##### `sourceChange`

当前数据源改变时触发，负载含新旧 `source`。

##### `sourceLoad`

数据源准备完成时触发，负载含 `videoSource`、`duration`、`availableVideoTracks`、`availableAudioTracks` 和 `availableSubtitleTracks`。

##### `availableAudioTracksChange`

可用音轨改变时触发，负载含 `availableAudioTracks` 和 `oldAvailableAudioTracks`。

##### `availableSubtitleTracksChange`

可用字幕轨改变时触发，负载含 `availableSubtitleTracks` 和 `oldAvailableSubtitleTracks`。

##### `audioTrackChange`

当前音轨改变时触发，负载含 `audioTrack` 和 `oldAudioTrack`。

##### `subtitleTrackChange`

当前字幕轨改变时触发，负载含 `subtitleTrack` 和 `oldSubtitleTrack`。

##### `videoTrackChange`

当前视频轨改变时触发，负载含 `videoTrack` 和 `oldVideoTrack`。

##### `isExternalPlaybackActiveChange`

- HarmonyOS 不提供外部播放，此事件不会触发。

#### `VideoView` 回调

以下回调作为 `VideoView` 属性传入，不含负载：

##### `onFirstFrameRender`

视频视图首次显示视频帧时触发；换轨后首次显示新帧时也会触发。

##### `onFullscreenEnter`

进入全屏时触发。

##### `onFullscreenExit`

退出全屏时触发。

##### `onPictureInPictureStart`

画中画开始时触发。

##### `onPictureInPictureStop`

画中画结束时触发。

### Types

#### `VideoViewProps`

`VideoView` 接受以下与视频播放相关的属性：

##### `VideoViewProps.player`

要显示的 `VideoPlayer`，默认为 `null`。同一个播放器同时只能连接到一个视图。

##### `VideoViewProps.nativeControls`

是否显示控制栏，默认为 `true`。全屏时控制栏始终显示，以便退出全屏。

##### `VideoViewProps.contentFit`

画面适配方式，默认为 `'contain'`；`'cover'` 裁剪溢出部分，`'fill'` 拉伸画面。

##### `VideoViewProps.contentPosition`

画面在视图内的偏移 `{ dx, dy }`，默认为 `{ dx: 0, dy: 0 }`。

##### `VideoViewProps.showsTimecodes`

是否显示当前时间和总时长，默认为 `true`，格式为分:秒。

##### `VideoViewProps.requiresLinearPlayback`

默认为 `false`；设为 `true` 后禁用进度条和前进、后退按钮。

##### `VideoViewProps.fullscreenOptions`

全屏选项，见下方 `FullscreenOptions`。默认允许全屏。

##### `VideoViewProps.buttonOptions`

控制播放、前进、后退及底栏显隐，见下方 `ButtonOptions`。

##### `VideoViewProps.allowsPictureInPicture`

是否允许手动启动画中画，默认为 `false`。

##### `VideoViewProps.startsPictureInPictureAutomatically`

应用进入后台时是否自动启动画中画，默认为 `false`。

##### `VideoViewProps.surfaceType`

- HarmonyOS 只接受 `'surfaceView'`；设为 `'textureView'` 会抛出 `ERR_VIDEO_UNSUPPORTED`。

##### `VideoViewProps.allowsVideoFrameAnalysis`

- HarmonyOS 不提供视频帧分析。

##### `VideoViewProps.useExoShutter`

- HarmonyOS 不提供此画面遮罩选项。

##### `VideoViewProps.crossOrigin`

- HarmonyOS 不提供此网络显示选项。

##### `VideoViewProps.playsInline`

- HarmonyOS 不提供此播放显示选项。

##### `VideoViewProps.useAudioNodePlayback`

- HarmonyOS 不提供此播放选项。

#### `VideoPlayer`

播放器的数据源准备在 `VideoView` 挂载且视图有尺寸后完成。之前 `status` 为 `loading`，`duration` 和轨道列表为空。播放器在应用进入后台时暂停，并在回到前台后恢复之前的播放请求；画中画或已获系统后台播放许可时可以继续播放。

##### `VideoPlayer.playing`

只读 `boolean`，当前正在播放时为 `true`；缓冲时为 `false`。

##### `VideoPlayer.status`

只读 `VideoPlayerStatus`，可为 `'idle'`、`'loading'`、`'readyToPlay'` 或 `'error'`。缓冲期间为 `'loading'`。

##### `VideoPlayer.duration`

只读 `number`，视频总时长（秒）；直播或加载完成前为 `0`。

##### `VideoPlayer.currentTime`

可读写 `number`，当前播放位置（秒）。写入会跳转到对应位置；负值按 0 处理，超过片长的值按片尾处理。直播源不支持跳转。

##### `VideoPlayer.isLive`

只读 `boolean`，数据源初始化后由系统判断是否为直播。

##### `VideoPlayer.bufferedPosition`

只读 `number`，已缓冲位置（秒）；未设置数据源时为 `-1`，尚无缓存时长或正在缓冲时为 `0`。

##### `VideoPlayer.loop`

`boolean`，默认 `false`；播放结束后从头继续。直播源设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。

##### `VideoPlayer.muted`

`boolean`，默认 `false`。修改时触发 `mutedChange`。

##### `VideoPlayer.volume`

`number`，范围为 0 到 1，默认 `1`；超出范围会抛出 `ERR_VIDEO_INVALID_ARGUMENT`。静音不会改变此值，修改时触发 `volumeChange`。

##### `VideoPlayer.playbackRate`

`number`，范围为 0.125 到 4，默认 `1`；直播源不支持修改。修改时触发 `playbackRateChange`。

##### `VideoPlayer.preservesPitch`

固定为 `true`，倍速播放时修正音高。

- HarmonyOS 不支持关闭音高修正；设为 `false` 会抛出 `ERR_VIDEO_UNSUPPORTED`。

##### `VideoPlayer.timeUpdateEventInterval`

`number`，单位为秒，默认 `0`；大于 0 时按该间隔触发 `timeUpdate`。

##### `VideoPlayer.keepScreenOnWhilePlaying`

`boolean`，默认 `true`；播放期间保持屏幕常亮，暂停或视图卸载后恢复原设置。

##### `VideoPlayer.audioMixingMode`

`AudioMixingMode`，默认 `'auto'`。多个播放器同时播放时按 `doNotMix`、`auto`、`duckOthers`、`mixWithOthers` 的优先顺序协调音频；`auto` 在播放器静音、音量为 0 或没有音轨时不会打断其他应用。系统音频中断使播放暂停后，中断结束时会恢复播放请求。

##### `VideoPlayer.availableAudioTracks`

只读数组，数据源准备完成后提供可选轨道。

##### `VideoPlayer.availableSubtitleTracks`

只读数组，数据源准备完成后提供可选轨道。

##### `VideoPlayer.availableVideoTracks`

只读数组，数据源准备完成后提供可选轨道。

##### `VideoPlayer.audioTrack`

可写音轨；须从 `availableAudioTracks` 中选择。设为 `null` 会静音。

##### `VideoPlayer.subtitleTrack`

可写字幕轨；须从 `availableSubtitleTracks` 中选择。设为 `null` 会隐藏字幕。

##### `VideoPlayer.videoTrack`

只读当前视频轨道；无当前轨道时为 `null`。

##### `VideoPlayer.bufferOptions`

`BufferOptions`，须在数据源准备前设置。

##### `VideoPlayer.currentLiveTimestamp`

- HarmonyOS 不提供直播节目时间戳；此属性始终为 `null`。

##### `VideoPlayer.currentOffsetFromLive`

- HarmonyOS 不提供直播延迟数据；此属性始终为 `null`。

##### `VideoPlayer.targetOffsetFromLive`

- HarmonyOS 不支持设置直播播放偏移；此属性始终为 `0`，设为非零值会抛出 `ERR_VIDEO_UNSUPPORTED`。

##### `VideoPlayer.isExternalPlaybackActive`

- HarmonyOS 不提供外部播放；此属性始终为 `false`。

##### `VideoPlayer.showNowPlayingNotification`

`boolean`，默认 `false`。设为 `true` 后，系统媒体控件显示播放状态并提供播放、暂停和跳转操作；设备须具备 AVSession 能力。可在数据源的 `metadata` 中提供标题、作者和封面。[HarmonyOS 媒体会话](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/avsession-faq-local/)

##### `VideoPlayer.staysActiveInBackground`

`boolean`，默认 `false`。需 HarmonyOS API 22 或更新版本及系统 AVSession、连续后台任务能力；同时须为应用配置 `supportsBackgroundPlayback: true`。系统媒体控件会显示播放状态，暂停、结束或释放播放器后后台播放停止。[HarmonyOS 后台播放](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/avsession-background-scene/)

##### `VideoPlayer.allowsExternalPlayback`

- HarmonyOS 不支持外部播放；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。

##### `VideoPlayer.seekTolerance`

- HarmonyOS 只支持零容差；非零值会抛出 `ERR_VIDEO_UNSUPPORTED`。

##### `VideoPlayer.scrubbingModeOptions`

- HarmonyOS 不支持该选项；启用任一选项会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `VideoSource`

`VideoSource` 可以是 `string`、`number`、`null` 或 `VideoSourceObject`。数字表示应用内视频资源。

#### `VideoSourceObject`

数据源对象可包含以下字段：

- `uri`：HTTP(S) 地址、本地 `file://` URI、绝对路径或打包资源地址。
- `assetId`：应用中的视频资源编号。
- `headers`：网络请求头，类型为 `Record<string, string>`。
- `metadata`：媒体信息，见 `VideoMetadata`。
- `contentType`：内容类型，见 `ContentType`。省略或设为 `'auto'` 时交由系统识别；本地或打包的 HLS 播放列表可指定 `'hls'`。

打包资源可使用 `asset://`、`rawfile://` 或 `resource://RAWFILE/` 地址。网络视频需要网络访问权限；本地文件须在应用可读目录中，或已通过系统文件选择器取得访问授权。可播放的格式由设备和 HarmonyOS 版本决定。[HarmonyOS 播放地址设置](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/playback-url-setting-method/)

##### `VideoSourceObject.drm`

- HarmonyOS 不支持 DRM；传入此字段会抛出 `ERR_VIDEO_UNSUPPORTED`。

##### `VideoSourceObject.useCaching`

- HarmonyOS 不支持持久化视频缓存；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。

##### `VideoSourceObject.contentType`

- HarmonyOS 只接受省略、`'auto'` 或本地/打包 HLS 播放列表上的 `'hls'`；显式指定其他类型会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `VideoMetadata`

可选字段为 `title`、`artist` 和 `artwork`，用于系统媒体控件显示媒体标题、作者和封面。

#### `DRMOptions`

- HarmonyOS 不支持 DRM；在 `VideoSourceObject.drm` 中传入选项会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `PlayerBuilderOptions`

可设置控制栏的 `seekBackwardIncrement` 和 `seekForwardIncrement`，单位为秒，默认均为 10。两项须为有限且大于 0 的数值。

#### `BufferOptions`

只有 `preferredForwardBufferDuration` 会生效，单位为秒。设为 `0` 使用系统默认值，或设为 1 到 20 秒。必须在数据源准备前设置。

- `waitsToMinimizeStalling`：HarmonyOS 不支持此选项，设置后会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `minBufferForPlayback`：HarmonyOS 不支持此选项，设置后会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `maxBufferBytes`：HarmonyOS 不支持此选项，设置后会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `prioritizeTimeOverSizeThreshold`：HarmonyOS 不支持此选项，设置后会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `SeekTolerance`

包含 `toleranceBefore` 和 `toleranceAfter` 两个以秒为单位的非负数值。HarmonyOS 只支持两个值均为 0；非零值会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `ScrubbingModeOptions`

- `scrubbingModeEnabled`：HarmonyOS 不支持此拖动优化；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `increaseCodecOperatingRate`：HarmonyOS 不支持此拖动优化；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `enableDynamicScheduling`：HarmonyOS 不支持此拖动优化；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `useDecodeOnlyFlag`：HarmonyOS 不支持此拖动优化；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `allowSkippingMediaCodecFlush`：HarmonyOS 不支持此拖动优化；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `ButtonOptions`

可设置 `showPlayPause`、`showSeekBackward`、`showSeekForward` 和 `showBottomBar`。默认均显示；`showBottomBar: false` 会隐藏普通视图的底栏，全屏时仍显示控制栏。

- `showNext`：HarmonyOS 控制栏不提供下一项按钮；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `showPrevious`：HarmonyOS 控制栏不提供上一项按钮；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `showSubtitles`：HarmonyOS 控制栏不提供字幕按钮；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `showSettings`：HarmonyOS 控制栏不提供设置按钮；设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `FullscreenOptions`

- `enable`：是否允许全屏，默认 `true`；设为 `false` 时隐藏全屏按钮，并禁止调用 `enterFullscreen()`。
- `orientation`：只接受 `'default'`；HarmonyOS 全屏不会设置窗口方向。
- `autoExitOnRotate`：默认 `false`；HarmonyOS 不提供旋转后自动退出全屏，设为 `true` 会抛出 `ERR_VIDEO_UNSUPPORTED`。
- `keepFullscreenOnPiPStop`：可设置 `'always'`、`'autoEnter'` 或 `'never'`，但 HarmonyOS 不应用此选项。

#### `ContentPosition`

`{ dx?: number; dy?: number }`，设置画面在 `VideoView` 中的水平和垂直偏移。

#### `VideoThumbnailOptions`

可设置 `maxWidth` 和 `maxHeight`（像素），用于限制缩略图尺寸并保持宽高比。数值必须大于 0。

#### `VideoThumbnail`

`generateThumbnailsAsync()` 返回的图像对象，包含 `width`、`height` 和 `requestedTime`。图像资源不再使用时调用 `release()`。

- HarmonyOS 不提供 `actualTime`。

#### `VideoAirPlayButtonProps`

- HarmonyOS 不提供隔空播放按钮；`tint` 不会改变显示内容。
- HarmonyOS 不提供隔空播放按钮；`activeTint` 不会改变显示内容。
- HarmonyOS 不提供隔空播放设备选择；`prioritizeVideoDevices` 不生效。
- HarmonyOS 不提供隔空播放路由选择；`onBeginPresentingRoutes` 不触发。
- HarmonyOS 不提供隔空播放路由选择；`onEndPresentingRoutes` 不触发。

#### `AudioTrack`

音轨对象包含 `id`、`language`、`label`，并可能包含 `name`。系统未提供的默认轨道信息不会返回。`id` 必须来自当前播放器的 `availableAudioTracks`。

#### `SubtitleTrack`

字幕轨对象包含 `id`、`language`、`label`，并可能包含 `name`。系统未提供的默认轨道和自动选择标记不会返回。`id` 必须来自当前播放器的 `availableSubtitleTracks`。

#### `VideoTrack`

包含 `id`、`url`、`size`、`mimeType`、`isSupported`、`bitrate`、`averageBitrate`、`peakBitrate`、`frameRate` 和 `videoRange`。HarmonyOS 上 `url`、`averageBitrate`、`peakBitrate` 为 `null`，`isSupported` 为 `true`；未知码率、帧率或 MIME 类型为 `null`，无效宽高为 0。本地文件和打包资源可提供动态范围信息；网络视频的 `videoRange` 返回 `'sdr'`，不能据此判断 HDR 格式。

#### `VideoSize`

包含以像素为单位的 `width` 和 `height`。

#### `PlayerError`

播放器错误对象包含 `message: string`。

#### `VideoPlayerEvents`

播放器可监听的事件及其负载类型见本节事件订阅。`timeUpdate` 的直播时间戳与延迟字段在 HarmonyOS 上始终为 `null`。

#### `StatusChangeEventPayload`

包含 `status`、`oldStatus` 和可选的 `error`。

#### `PlayingChangeEventPayload`

包含 `isPlaying` 和 `oldIsPlaying`。

#### `PlaybackRateChangeEventPayload`

包含 `playbackRate` 和 `oldPlaybackRate`。

#### `VolumeChangeEventPayload`

包含 `volume` 和 `oldVolume`。

#### `MutedChangeEventPayload`

包含 `muted` 和 `oldMuted`。

#### `SourceChangeEventPayload`

包含新旧 `source`。

#### `TimeUpdateEventPayload`

包含 `currentTime`、`bufferedPosition`、`currentLiveTimestamp` 和 `currentOffsetFromLive`。后两个字段在 HarmonyOS 上始终为 `null`。

#### `SourceLoadEventPayload`

包含 `videoSource`、`duration` 及可用的音轨、字幕轨和视频轨。

#### `AvailableSubtitleTracksChangeEventPayload`

包含当前及先前可用的字幕轨列表。

#### `SubtitleTrackChangeEventPayload`

包含当前和先前选中的 `subtitleTrack`。

#### `VideoTrackChangeEventPayload`

包含当前和先前选中的 `videoTrack`。

#### `IsExternalPlaybackActiveChangeEventPayload`

- HarmonyOS 不提供外部播放，此事件不会触发。

#### `VideoAirPlayButton`

- HarmonyOS 不提供隔空播放。此组件显示为空白视图，默认最小宽高各为 30 个布局单位，可由 `style` 调整。

### Enums

#### `SurfaceType`

- HarmonyOS 只支持 `'surfaceView'`；`'textureView'` 会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `VideoPlayerStatus`

- `'idle'`：没有播放或加载数据源。
- `'loading'`：正在加载或缓冲。
- `'readyToPlay'`：数据已准备好，可以播放或继续播放。
- `'error'`：加载或播放遇到错误。

#### `VideoContentFit`

`'contain'` 保持比例并完整显示，`'cover'` 保持比例并铺满视图，`'fill'` 拉伸以填满视图。

#### `ContentType`

`'auto'`、`'progressive'`、`'hls'`、`'dash'` 或 `'smoothStreaming'`。默认 `'auto'`，由系统识别；显式指定时仅本地或打包 HLS 播放列表可设为 `'hls'`，其他显式类型不受支持。

#### `AudioMixingMode`

- `'mixWithOthers'`：与其他应用混音。
- `'duckOthers'`：有可听音频时降低其他应用的音量。
- `'auto'`：有可听音频时打断其他应用；播放器静音、音量为 0 或没有音轨时允许其他应用继续播放。
- `'doNotMix'`：播放时打断其他应用，即使播放器静音。

多个播放器同时播放时，采用最高优先级：`doNotMix`、`auto`、`duckOthers`、`mixWithOthers`。

#### `VideoRange`

`'sdr'`（标准动态范围）、`'hlg'` 或 `'pq'`（HDR 动态范围）。网络视频目前返回 `'sdr'`。

#### `FullscreenOrientation`

HarmonyOS 只接受 `'default'`；其他方向值会抛出 `ERR_VIDEO_UNSUPPORTED`。

#### `KeepFullscreenOnPiPStopBehavior`

可选值为 `'always'`、`'autoEnter'` 和 `'never'`；HarmonyOS 接受这些值，但不应用此行为选项。

#### `DRMType`

- HarmonyOS 不支持受 DRM 保护的视频源。

### Error codes

#### `ERR_VIDEO_INVALID_ARGUMENT`

数值参数不是有限数、超出允许范围，或跳转间隔过大时抛出。

#### `ERR_VIDEO_INVALID_SOURCE`

数据源地址无效、不受支持或无法打开时抛出。

#### `ERR_VIDEO_UNSUPPORTED`

请求了 HarmonyOS 不支持的属性、数据源类型或播放操作时抛出。

#### `ERR_VIDEO_LOAD_CANCELLED`

数据源加载被后续换源或播放器释放取消时抛出。

#### `ERR_VIDEO_LOAD_TIMEOUT`

数据源初始化或视频准备超时时抛出。

#### `ERR_VIDEO_LOAD`

数据源加载失败且没有更具体错误码时抛出；错误信息包含系统返回的说明。

#### `ERR_VIDEO_PLAYBACK`

播放失败且没有更具体错误码时抛出；错误信息包含系统返回的说明。

#### `ERR_VIDEO_RELEASED`

播放器释放后仍对其调用操作时抛出。

#### `ERR_VIDEO_SURFACE_IN_USE`

同一个播放器同时连接到多个 `VideoView` 时抛出。

#### `ERR_VIDEO_INVALID_TRACK`

选择的音轨或字幕轨不属于当前播放器时抛出。

#### `ERR_VIDEO_NOT_READY`

数据源尚未准备好时尝试选择轨道会抛出。

#### `ERR_VIDEO_NO_SOURCE`

调用缩略图提取方法时播放器没有数据源，调用会失败。

#### `ERR_VIDEO_THUMBNAIL`

系统提取缩略图失败时抛出。

#### `ERR_VIDEO_CACHE_IN_USE`

调用清除或设置缓存大小的方法时仍有未释放的播放器，调用会失败。

#### `ERR_VIDEO_PIP_DISABLED`

调用 `startPictureInPicture()` 前未启用 `allowsPictureInPicture` 时抛出。

#### `ERR_VIDEO_PIP_NOT_READY`

画中画所需的视频帧或视图表面尚未准备好时抛出。

#### `ERR_VIDEO_PIP_UNAVAILABLE`

系统当前不支持画中画时抛出。

#### `ERR_VIDEO_VIEW_DESTROYED`

视图销毁后调用 `enterFullscreen()` 时抛出。

#### `ERR_VIDEO_FULLSCREEN_DISABLED`

全屏已禁用时调用 `enterFullscreen()` 会抛出。

### Permissions

#### `ohos.permission.INTERNET`

本包声明此普通权限，用于播放 HTTP(S) 视频。

#### `ohos.permission.KEEP_BACKGROUND_RUNNING`

需要后台播放时，配置插件的 `supportsBackgroundPlayback: true` 会为应用声明此权限和音频播放后台模式。后台视频播放还要求 HarmonyOS API 22 或更新版本及设备支持相应系统能力。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
