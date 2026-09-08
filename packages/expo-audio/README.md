# @expo-harmony/expo-audio

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-audio) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/audio/)

为 HarmonyOS 上的 React Native 应用提供 Expo Audio 的原生实现，支持音频播放、播放列表、预加载、录音、音频焦点、后台播放和锁屏媒体控制，与官方同版本的 `expo-audio` 配套使用。JavaScript API、类型和 React Hooks 由官方 `expo-audio` 包提供。

## 安装

```bash
npm install @expo-harmony/expo-audio expo-audio@55.0.14
```

使用录音或后台音频能力时，必须在 `app.json` 的 `plugins` 中配置 `@expo-harmony/expo-audio`：

```json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-audio",
        {
          "enableBackgroundPlayback": true,
          "enableBackgroundRecording": false
        }
      ]
    ]
  }
}
```

`enableBackgroundPlayback` 默认为 `true`，`enableBackgroundRecording` 默认为 `false`。Config Plugin 默认配置麦克风权限，并仅在启用相应后台能力时添加 HarmonyOS 连续任务权限和 Ability 后台模式；仅使用前台播放时可以将两个选项都设为 `false`。

可通过 `microphonePermission: "允许应用录制音频"` 自定义麦克风权限说明。插件会将文案写入 entry 模块的字符串资源，并在 `module.json5` 中使用资源引用；也支持直接传入已有的 `$string:资源名` 或构建占位符。将 `microphonePermission` 或 `recordAudioAndroid` 设为 `false` 可移除麦克风权限。

受 HarmonyOS Media Kit 能力限制，当前不支持 PCM 音频采样和关闭变调校正，录音格式仅支持 M4A（AAC）和 MP3；播放列表切换也不保证无缝衔接。调用不受支持的能力会抛出错误。

## API 对照表

### Constants

#### `Audio.RecordingPresets`

录音参数预设。

`HIGH_QUALITY` 为 44100 Hz、双声道、128000 bps，`LOW_QUALITY` 为 44100 Hz、双声道、64000 bps。两个预设在这里都录成 M4A（AAC），官方预设中 Android 用的 3GP/AMR 分支不生效。

### Hooks

#### `useAudioPlayer(source, options)`

返回 `AudioPlayer`。创建后立即开始加载 `source`，组件卸载时自动释放。`source` 默认 `null`，`options` 默认 `{}`。

#### `useAudioPlayerStatus(player)`

返回 `AudioStatus`，订阅播放状态变化，初始值为当前状态。

#### `useAudioPlaylist(options)`

返回 `AudioPlaylist`，组件卸载时自动释放。`sources` 默认 `[]`，`loop` 默认 `'none'`。

#### `useAudioPlaylistStatus(playlist)`

返回 `AudioPlaylistStatus`，订阅播放列表状态变化。

#### `useAudioRecorder(options, statusListener)`

返回 `AudioRecorder`。`options` 作为默认录音参数，在 `prepareToRecordAsync()` 时应用；录制前仍需先调用 `prepareToRecordAsync()`。传入 `statusListener` 时订阅录音状态事件。

#### `useAudioRecorderState(recorder, interval)`

按 `interval` 轮询录音器状态，默认 500 毫秒，返回 `RecorderState`。

> **未实现的内容**
>
> - `useAudioSampleListener(player, listener)`：HarmonyOS 的播放能力不提供解码后的 PCM 帧，`isAudioSamplingSupported` 恒为 `false`，该 Hook 不会启用采样，也不触发回调。

### Classes

#### `AudioPlayer`

音频播放器。

#### `AudioPlayer.id`

类型：`string`，只读

播放器标识。

#### `AudioPlayer.playing`

类型：`boolean`，只读

是否正在播放。正在缓冲但播放请求仍在时也为 `true`。

#### `AudioPlayer.paused`

类型：`boolean`，只读

是否处于暂停状态，与 `playing` 相反。

#### `AudioPlayer.muted`

类型：`boolean`，可读写

静音时按 0 音量输出，不影响 `volume` 的取值。

#### `AudioPlayer.loop`

类型：`boolean`，可读写

是否循环播放当前音频。

#### `AudioPlayer.isLoaded`

类型：`boolean`，只读

音频是否已加载完成、可以播放。

#### `AudioPlayer.isBuffering`

类型：`boolean`，只读

是否正在缓冲。

#### `AudioPlayer.isAudioSamplingSupported`

类型：`boolean`，只读

恒为 `false`。

#### `AudioPlayer.currentTime`

类型：`number`，只读

当前播放位置，单位秒。

#### `AudioPlayer.duration`

类型：`number`，只读

音频总时长，单位秒；尚未确定时为 0。

#### `AudioPlayer.volume`

类型：`number`，可读写

音量，取值 0 到 1，越界会被钳制。

#### `AudioPlayer.playbackRate`

类型：`number`，只读

播放倍速，改变倍速请调用 `setPlaybackRate()`。取值 0.1 到 2.0；API 20 之前只支持 0.5、0.75、1、1.25、1.5、1.75、2 这几档，设置其他值会抛出错误，API 20 起支持区间内的任意值。

#### `AudioPlayer.shouldCorrectPitch`

类型：`boolean`，可读写

是否对倍速变化做音高修正，恒为 `true`。设为 `false` 会抛出错误。

#### `AudioPlayer.play()`

开始播放。播放结束后再次调用会从头开始。

#### `AudioPlayer.pause()`

暂停播放。

#### `AudioPlayer.replace(source)`

更换音频源，`source` 为 `null` 时卸载当前音频。

#### `AudioPlayer.seekTo(seconds, toleranceMillisBefore?, toleranceMillisAfter?)`

返回 `Promise<void>`。跳转到指定位置，单位秒，越界时钳制到 0 或总时长。两个容差参数不生效。

#### `AudioPlayer.setPlaybackRate(rate, pitchCorrectionQuality?)`

设置播放倍速，`pitchCorrectionQuality` 不生效，取值限制与 `playbackRate` 一致。

#### `AudioPlayer.setAudioSamplingEnabled(enabled)`

传入 `true` 会抛出错误，HarmonyOS 不支持音频采样。

#### `AudioPlayer.setActiveForLockScreen(active, metadata?, options?)`

接管或取消锁屏控制。同一时间只有一个播放器可以接管。`metadata` 用于展示标题、艺术家、专辑和封面；`options` 的 `showSeekForward`、`showSeekBackward` 会在锁屏上显示快进、快退按钮，每次跳转 10 秒。

#### `AudioPlayer.updateLockScreenMetadata(metadata)`

更新锁屏展示的元数据，仅在当前播放器已接管锁屏控制时生效。

#### `AudioPlayer.clearLockScreenControls()`

取消接管锁屏控制。

#### `AudioPlayer.remove()`

释放播放器占用的资源。

#### `AudioPlaylist`

播放列表。切换曲目时重新加载音频源，不保证无缝衔接。

#### `AudioPlaylist.id`

类型：`string`，只读

播放列表标识。

#### `AudioPlaylist.currentIndex`

类型：`number`，只读

当前曲目索引。

#### `AudioPlaylist.trackCount`

类型：`number`，只读

曲目数量。

#### `AudioPlaylist.sources`

类型：`AudioSourceInfo[]`，只读

列表中的音频源。

#### `AudioPlaylist.playing`

类型：`boolean`，只读

是否正在播放。

#### `AudioPlaylist.muted`

类型：`boolean`，可读写

是否静音。

#### `AudioPlaylist.isLoaded`

类型：`boolean`，只读

当前曲目是否已加载完成。

#### `AudioPlaylist.isBuffering`

类型：`boolean`，只读

是否正在缓冲。

#### `AudioPlaylist.currentTime`

类型：`number`，只读

当前曲目的播放位置，单位秒。

#### `AudioPlaylist.duration`

类型：`number`，只读

当前曲目的总时长，单位秒；尚未确定时为 0。

#### `AudioPlaylist.volume`

类型：`number`，可读写

音量，取值 0 到 1，越界会被钳制。

#### `AudioPlaylist.playbackRate`

类型：`number`，可读写

播放倍速，取值和版本限制与 `AudioPlayer.playbackRate` 一致。

#### `AudioPlaylist.loop`

类型：`AudioPlaylistLoopMode`，可读写

循环模式，取值 `'none'`、`'single'`、`'all'`。

#### `AudioPlaylist.play()`

播放当前曲目。

#### `AudioPlaylist.pause()`

暂停播放。

#### `AudioPlaylist.next()`

跳到下一首。已在最后一首时，`loop` 为 `'all'` 回到第一首，否则不动作。

#### `AudioPlaylist.previous()`

跳到上一首。已在第一首时，`loop` 为 `'all'` 跳到最后一首，否则不动作。

#### `AudioPlaylist.skipTo(index)`

跳到指定索引，越界不动作。

#### `AudioPlaylist.seekTo(seconds)`

返回 `Promise<void>`，跳转到当前曲目的指定位置，单位秒。

#### `AudioPlaylist.add(source)`

把音频源追加到列表末尾，`source` 为空时不动作。

#### `AudioPlaylist.insert(source, index)`

在指定位置插入音频源，越界不动作。

#### `AudioPlaylist.remove(index)`

移除指定索引的曲目，越界不动作。移除当前曲目后切到相邻曲目。

#### `AudioPlaylist.clear()`

清空列表。

#### `AudioPlaylist.destroy()`

释放播放列表占用的资源。

#### `AudioRecorder`

录音器。

#### `AudioRecorder.id`

类型：`string`，只读

录音器标识。

#### `AudioRecorder.currentTime`

类型：`number`，只读

当前录音时长，单位秒。暂停后继续录制时累计。

#### `AudioRecorder.isRecording`

类型：`boolean`，只读

是否正在录音。

#### `AudioRecorder.uri`

类型：`string | null`，只读

录音文件的 `file://` 地址，尚未生成时为 `null`。

#### `AudioRecorder.prepareToRecordAsync(options?)`

返回 `Promise<void>`，准备录音并应用录音参数，需要先获得麦克风权限。`options` 与构造时的参数合并，传入的字段优先。

#### `AudioRecorder.record(options?)`

开始录音，需先调用 `prepareToRecordAsync()`。`options.atTime` 只支持 0，传入大于 0 的值会抛出错误；`options.forDuration` 会在指定秒数后自动停止。

#### `AudioRecorder.stop()`

返回 `Promise<void>`，停止录音并写入文件。

#### `AudioRecorder.pause()`

暂停录音，再次调用 `record()` 继续。

#### `AudioRecorder.recordForDuration(seconds)`

录制指定秒数后自动停止。

#### `AudioRecorder.startRecordingAtTime(seconds)`

已弃用。只支持 0，传入大于 0 的值会抛出错误。

#### `AudioRecorder.getAvailableInputs()`

返回 `RecordingInput[]`，列出可用的录音输入设备。需先调用 `prepareToRecordAsync()`。

#### `AudioRecorder.getCurrentInput()`

返回 `Promise<RecordingInput>`，当前使用的录音输入设备。需先调用 `prepareToRecordAsync()`。

#### `AudioRecorder.setInput(uid)`

切换录音输入设备，`uid` 取自 `RecordingInput.uid`。需要 API 21 及以上，低版本调用会抛出错误。

#### `AudioRecorder.getStatus()`

返回 `RecorderState`。

### Methods

#### `Audio.clearAllPreloadedSources()`

返回 `Promise<void>`，释放所有预加载的音频源。

#### `Audio.clearPreloadedSource(source)`

返回 `Promise<void>`，释放指定的预加载音频源，按地址匹配。

#### `Audio.createAudioPlayer(source?, options?)`

返回 `AudioPlayer`，不会自动释放，需要自行调用 `remove()`。

#### `Audio.createAudioPlaylist(options?)`

返回 `AudioPlaylist`，不会自动释放，需要自行调用 `destroy()`。

#### `Audio.getPreloadedSources()`

返回 `Promise<string[]>`，已预加载音频源的地址。音频源被播放器使用后仍留在列表里，需要显式清除。

#### `Audio.getRecordingPermissionsAsync()`

返回 `Promise<PermissionResponse>`，查询麦克风权限，不弹出授权弹窗。

#### `Audio.preload(source, options?)`

返回 `Promise<void>`，提前加载音频源，同一地址重复调用不会重复加载。`options.preferredForwardBufferDuration` 默认 10 秒。

#### `Audio.requestNotificationPermissionsAsync()`

返回 `Promise<PermissionResponse>`，请求通知权限，用于展示后台播放的通知。

#### `Audio.requestRecordingPermissionsAsync()`

返回 `Promise<PermissionResponse>`，请求麦克风权限，会弹出授权弹窗。

#### `Audio.setAudioModeAsync(mode)`

返回 `Promise<void>`，配置全局音频行为。只更新传入的字段，未传入的保留之前的值。`shouldRouteThroughEarpiece` 为 `true` 时切换听筒输出，需要 API 20 及以上，低版本抛出错误；切换听筒输出会清空预加载缓存。

#### `Audio.setIsAudioActiveAsync(active)`

返回 `Promise<void>`。设为 `false` 时暂停所有播放并停用音频会话；设回 `true` 不会自动恢复播放。

### Event Subscriptions

> **未实现的内容**
>
> - `Audio.useAudioSampleListener(player, listener)`：HarmonyOS 的播放能力不提供解码后的 PCM 帧，没有采样数据可订阅。

### Types

#### `AudioEvents`

| 事件                   | 载荷           | 说明                     |
| ---------------------- | -------------- | ------------------------ |
| `playbackStatusUpdate` | `AudioStatus`  | 播放状态变化时触发       |
| `audioSampleUpdate`    | `AudioSample`  | 不会触发，不支持音频采样 |

#### `AudioLoadOptions`

`AudioPlayerOptions` 的别名，已弃用。

#### `AudioLockScreenOptions`

| 属性（可选）       | 类型      | 说明                         |
| ------------------ | --------- | ---------------------------- |
| `showSeekForward`  | `boolean` | 锁屏显示快进按钮，步进 10 秒 |
| `showSeekBackward` | `boolean` | 锁屏显示快退按钮，步进 10 秒 |

#### `AudioMetadata`

| 属性（可选） | 类型     |
| ------------ | -------- |
| `title`      | `string` |
| `artist`     | `string` |
| `albumTitle` | `string` |
| `artworkUrl` | `string` |

#### `AudioMode`

| 属性（可选）                         | 类型               | 说明                                                                 |
| ------------------------------------ | ------------------ | -------------------------------------------------------------------- |
| `interruptionMode`                   | `InterruptionMode` | 与其他应用音频的并发方式，默认 `'mixWithOthers'`                     |
| `shouldPlayInBackground`             | `boolean`          | 切到后台后是否继续播放，默认 `false`                                 |
| `shouldRouteThroughEarpiece`         | `boolean`          | 是否从听筒输出，默认 `false`，需要 API 20 及以上                     |
| `allowsBackgroundRecording`          | `boolean`          | 切到后台后是否继续录音，默认 `false`                                 |

`shouldPlayInBackground` 和 `allowsBackgroundRecording` 需要 Config Plugin 开启对应的后台能力，否则切到后台时播放或录音会暂停。

> **未实现的内容**
>
> - `playsInSilentMode`、`allowsRecording`：iOS 专属字段，HarmonyOS 上没有对应行为。
> - `interruptionModeAndroid`：已弃用的 Android 专属字段，HarmonyOS 上不读取。

#### `AudioPlayerOptions`

| 属性（可选）                     | 类型      | 说明                                                   |
| -------------------------------- | --------- | ------------------------------------------------------ |
| `updateInterval`                 | `number`  | 播放状态事件的间隔毫秒数，默认 500，最小 16             |
| `downloadFirst`                  | `boolean` | 是否先把音频下载到本地再播放，默认 `false`              |
| `keepAudioSessionActive`         | `boolean` | 播放器暂停或结束时是否保留音频会话，默认 `false`        |
| `preferredForwardBufferDuration` | `number`  | 预缓冲秒数，默认 0，由系统决定                          |

> **未实现的内容**
>
> - `crossOrigin`：Web 专属字段，HarmonyOS 上不生效。

#### `AudioPlaylistEvents`

| 事件                   | 载荷                                              | 说明                   |
| ---------------------- | ------------------------------------------------- | ---------------------- |
| `playlistStatusUpdate` | `AudioPlaylistStatus`                             | 播放列表状态变化时触发 |
| `trackChanged`         | `{ previousIndex: number; currentIndex: number }` | 曲目切换时触发         |

#### `AudioPlaylistLoopMode`

`'none' | 'single' | 'all'`，默认 `'none'`。

#### `AudioPlaylistOptions`

| 属性（可选）     | 类型                    | 说明                         |
| ---------------- | ----------------------- | ---------------------------- |
| `sources`        | `AudioSource[]`         | 初始曲目，默认 `[]`          |
| `updateInterval` | `number`                | 状态事件间隔毫秒数，默认 500 |
| `loop`           | `AudioPlaylistLoopMode` | 循环模式，默认 `'none'`      |

> **未实现的内容**
>
> - `crossOrigin`：Web 专属字段，HarmonyOS 上不生效。

#### `AudioPlaylistStatus`

| 属性            | 类型                    |
| --------------- | ----------------------- |
| `id`            | `string`                |
| `currentIndex`  | `number`                |
| `trackCount`    | `number`                |
| `currentTime`   | `number`                |
| `duration`      | `number`                |
| `playing`       | `boolean`               |
| `isBuffering`   | `boolean`               |
| `isLoaded`      | `boolean`               |
| `playbackRate`  | `number`                |
| `muted`         | `boolean`               |
| `volume`        | `number`                |
| `loop`          | `AudioPlaylistLoopMode` |
| `didJustFinish` | `boolean`               |

#### `AudioSource`

字符串、`require('...')` 返回的数字、`null`，或带以下字段的对象：

| 属性（可选） | 类型                     | 说明                                      |
| ------------ | ------------------------ | ----------------------------------------- |
| `uri`        | `string`                 | 音频地址                                  |
| `assetId`    | `number`                 | 打包资源的模块 ID，取自 `require`         |
| `name`       | `string`                 | 展示名称                                  |
| `headers`    | `Record<string, string>` | 请求头，只对 `http`、`https` 远程地址生效 |

`uri` 支持本地文件路径和 `file://` 地址、打包资源 `asset://` 与 `rawfile://`、远程 `http`、`https`，以及 `data:` 地址。`data:` 地址必须是 base64 编码，解码后不超过 32 MB。数字和 `assetId` 会解析为打包资源地址后加载。

#### `AudioSourceInfo`

| 属性（可选） | 类型     |
| ------------ | -------- |
| `uri`        | `string` |
| `name`       | `string` |

#### `AudioStatus`

| 属性                     | 类型             | 说明                                                         |
| ------------------------ | ---------------- | ------------------------------------------------------------ |
| `id`                     | `string`         | 播放器标识                                                   |
| `currentTime`            | `number`         | 当前播放位置，单位秒                                         |
| `duration`               | `number`         | 总时长，单位秒                                               |
| `playing`                | `boolean`        | 是否正在播放                                                 |
| `loop`                   | `boolean`        | 是否循环                                                     |
| `didJustFinish`          | `boolean`        | 是否刚刚播放结束                                             |
| `isBuffering`            | `boolean`        | 是否正在缓冲                                                 |
| `isLoaded`               | `boolean`        | 是否已加载完成                                               |
| `mute`                   | `boolean`        | 是否静音                                                     |
| `playbackRate`           | `number`         | 播放倍速                                                     |
| `shouldCorrectPitch`     | `boolean`        | 是否做音高修正，恒为 `true`                                  |
| `playbackState`          | `string`         | `'buffering'`、`'ready'`、`'ended'`、`'idle'` 或 `'unknown'` |
| `timeControlStatus`      | `string`         | `'playing'` 或 `'paused'`                                    |
| `reasonForWaitingToPlay` | `string \| null` | 恒为 `null`                                                  |

> **未实现的内容**
>
> - `currentOffsetFromLive`、`isLive`：HarmonyOS 上没有直播流的判断来源，不返回。
> - `error`：播放错误不通过状态返回，加载失败时方法直接拒绝。
> - `mediaServicesDidReset`：iOS 专属字段。

#### `InterruptionMode`

`'mixWithOthers' | 'doNotMix' | 'duckOthers'`，默认 `'mixWithOthers'`。分别对应与其他应用混音、独占音频焦点让他人暂停、压低他人音量。被其他应用压低音量时，本应用的输出音量减半。

#### `PermissionExpiration`

`'never' | number`。

#### `PermissionResponse`

| 属性          | 类型                   | 说明             |
| ------------- | ---------------------- | ---------------- |
| `status`      | `PermissionStatus`     | 权限状态         |
| `granted`     | `boolean`              | 是否已授权       |
| `expires`     | `PermissionExpiration` | 恒为 `'never'`   |
| `canAskAgain` | `boolean`              | 是否还能再次请求 |

#### `PreloadOptions`

| 属性（可选）                     | 类型     | 说明       |
| -------------------------------- | -------- | ---------- |
| `preferredForwardBufferDuration` | `number` | 默认 10 秒 |

#### `RecorderState`

| 属性（可选）            | 类型             | 说明                                             |
| ----------------------- | ---------------- | ------------------------------------------------ |
| `canRecord`             | `boolean`        | 是否已准备好录音                                 |
| `isRecording`           | `boolean`        | 是否正在录音                                     |
| `durationMillis`        | `number`         | 录音时长，单位毫秒                               |
| `url`                   | `string \| null` | 录音文件的 `file://` 地址                        |
| `metering`              | `number`         | 当前录音电平，单位分贝，只在录音且开启计量时返回 |
| `mediaServicesDidReset` | `boolean`        | 恒为 `false`                                     |

#### `RecordingEvents`

| 事件                    | 载荷              | 说明                 |
| ----------------------- | ----------------- | -------------------- |
| `recordingStatusUpdate` | `RecordingStatus` | 录音状态变化时触发   |

#### `RecordingInput`

| 属性   | 类型     | 说明                                       |
| ------ | -------- | ------------------------------------------ |
| `name` | `string` | 设备名称                                   |
| `type` | `string` | 设备类型，如内置麦克风、有线耳机、蓝牙设备 |
| `uid`  | `string` | 设备标识，用于 `setInput()`                |

#### `RecordingOptions`

| 属性                | 类型                  | 说明                                                         |
| ------------------- | --------------------- | ------------------------------------------------------------ |
| `extension`         | `string`              | 文件扩展名，只支持 `.m4a` 和 `.mp3`，其他值抛出错误          |
| `sampleRate`        | `number`              | 采样率，取值 8000 到 96000，默认 44100                       |
| `numberOfChannels`  | `number`              | 声道数，取值 1 到 2，默认 2                                  |
| `bitRate`           | `number`              | 码率，取值 32000 到 320000，默认 128000                      |
| `isMeteringEnabled` | `boolean`（可选）     | 是否在 `RecorderState.metering` 中返回录音电平，默认 `false` |
| `web`               | `RecordingOptionsWeb`（可选） | 只读取 `mimeType` 和 `bitsPerSecond`，其余字段不生效 |

录音参数在取值范围内会被钳制到边界。未指定 `extension` 时，`web.mimeType` 为 `audio/mpeg` 录成 MP3，其他录成 M4A。

> **未实现的内容**
>
> - `android`、`ios`：平台专属子配置，HarmonyOS 上不读取。

#### `RecordingOptionsWeb`

| 属性（可选）    | 类型     | 说明                                                       |
| --------------- | -------- | ---------------------------------------------------------- |
| `mimeType`      | `string` | 未指定 `extension` 时用于决定录音格式，`audio/mpeg` 为 MP3 |
| `bitsPerSecond` | `number` | `bitRate` 的备用取值                                       |

#### `RecordingStartOptions`

| 属性（可选）  | 类型     | 说明                                              |
| ------------- | -------- | ------------------------------------------------- |
| `atTime`      | `number` | 只支持 0，传入大于 0 的值会抛出错误               |
| `forDuration` | `number` | 录制指定秒数后自动停止，不传则一直录到手动停止    |

#### `RecordingStatus`

| 属性         | 类型             | 说明                      |
| ------------ | ---------------- | ------------------------- |
| `id`         | `string`         | 录音器标识                |
| `isFinished` | `boolean`        | 录音是否已结束            |
| `hasError`   | `boolean`        | 是否出错                  |
| `error`      | `string \| null` | 错误信息                  |
| `url`        | `string \| null` | 录音文件的 `file://` 地址 |

以上类型中未实现的部分：

> **未实现的内容**
>
> - `RecordingStatus.mediaServicesDidReset`、`BitRateStrategy`、`PitchCorrectionQuality`、`RecordingOptionsIos`：iOS 专属，HarmonyOS 上没有对应取值。
> - `AudioSample`、`AudioSampleChannel`：用于音频采样，HarmonyOS 上没有数据来源。
> - `AndroidAudioEncoder`、`AndroidOutputFormat`、`RecordingOptionsAndroid`、`RecordingSource`：Android 专属，HarmonyOS 上没有对应取值。
> - `InterruptionModeAndroid`：已弃用的 Android 专属别名，HarmonyOS 上不读取。

### Enums

#### `PermissionStatus`

| 成员           | 值               |
| -------------- | ---------------- |
| `DENIED`       | `'denied'`       |
| `GRANTED`      | `'granted'`      |
| `UNDETERMINED` | `'undetermined'` |

> **未实现的内容**
>
> - `AudioQuality`、`IOSOutputFormat`：iOS 专属枚举，HarmonyOS 上没有对应取值。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
