# @expo-harmony/expo-audio

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-audio) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/audio/)

为 HarmonyOS 上的 React Native 应用提供 Expo Audio 的原生实现，与官方 `expo-audio` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-audio expo-audio@~57.0.5
```

## API 对照表

### Hooks

#### `useAudioPlayer(source = null, options = {})`

返回 `AudioPlayer`。播放器创建后立即加载音源；Hook 会在组件卸载时释放播放器。

#### `useAudioPlayerStatus(player)`

返回当前 `AudioStatus`，并订阅播放器状态变化。订阅时会先取得当前状态。

#### `useAudioPlaylist(options = {})`

返回 `AudioPlaylist`，组件卸载时自动释放。`sources` 默认为 `[]`，`loop` 默认为 `'none'`。切换曲目时会重新加载音源，不保证无缝衔接。

#### `useAudioPlaylistStatus(playlist)`

返回当前 `AudioPlaylistStatus`，并订阅播放列表状态变化。

#### `useAudioRecorder(options, statusListener?)`

返回 `AudioRecorder`，组件卸载时自动释放。`options` 会作为录音默认参数，在调用 `prepareToRecordAsync()` 时应用；开始录制前仍需先准备录音。传入 `statusListener` 后可接收录音状态事件。

#### `useAudioRecorderState(recorder, interval = 500)`

按指定间隔轮询并返回 `RecorderState`；默认每 500 毫秒更新一次。

#### `useAudioStream(options = {})`

创建实时麦克风 PCM 流，返回 `{ stream, isStreaming }`。取得麦克风权限后调用 `await stream.start()` 开始采集，调用 `stream.stop()` 停止；组件卸载时自动停止。格式、缓冲数据和中断行为见 [`AudioStreamOptions`](#audiostreamoptions)、[`AudioStreamBuffer`](#audiostreambuffer) 和 [`AudioStream`](#audiostream)。

##### HarmonyOS 上不支持的 Hook

- `useAudioSampleListener(player, listener)`：播放器不提供解码后的 PCM 帧，因此采样属性始终为 `false`，不会触发采样回调。

### Constants

#### `RecordingPresets`

提供 `HIGH_QUALITY` 和 `LOW_QUALITY` 两种录音参数预设。HarmonyOS 上两者均生成 M4A（AAC）：分别为 44100 Hz、双声道、128000 bps 和 44100 Hz、双声道、64000 bps。

### Methods

#### `AudioModule`

导出的音频模块对象，可调用本节列出的全局方法，例如 `AudioModule.requestRecordingPermissionsAsync()`。播放器、录音器、播放列表和实时流可通过对应 Hook 或创建方法取得。

#### `createAudioPlayer(source = null, options = {})`

创建 `AudioPlayer`，不会自动释放；使用完毕后调用 `player.remove()`。`source` 默认为 `null`，`options` 默认为 `{}`。

#### `createAudioPlaylist(options = {})`

创建 `AudioPlaylist`，不会自动释放；使用完毕后调用 `playlist.destroy()`。`options` 默认为 `{}`。

#### `setAudioModeAsync(mode)`

返回 `Promise<void>`，设置全局音频模式。只更新传入的字段，其余字段保留当前值。支持的字段和后台行为见 [`AudioMode`](#audiomode)。

#### `setIsAudioActiveAsync(active)`

返回 `Promise<void>`。设为 `false` 会暂停所有播放器和播放列表；设回 `true` 不会自动恢复播放。

#### `preload(source, options = {})`

返回 `Promise<void>`，预加载音源。`preferredForwardBufferDuration` 默认为 10 秒。同一音源地址和请求头相同时复用预加载项。

#### `clearPreloadedSource(source)`

返回 `Promise<void>`，清除指定音源的预加载项。

#### `clearAllPreloadedSources()`

返回 `Promise<void>`，清除所有预加载项。

#### `getPreloadedSources()`

返回 `Promise<string[]>`，列出已预加载的音源地址。播放器使用预加载音源后，该地址仍会保留在列表中，直到显式清除。

#### `getRecordingPermissionsAsync()`

返回 `Promise<PermissionResponse>`，查询麦克风权限，不显示授权请求。

#### `requestRecordingPermissionsAsync()`

返回 `Promise<PermissionResponse>`，请求麦克风权限。应用需声明 `ohos.permission.MICROPHONE`；录音器准备和实时流启动前均须取得授权。

#### `requestNotificationPermissionsAsync()`

返回 `Promise<PermissionResponse>`，查询并请求通知显示权限。用户拒绝或系统不允许时，返回未授权状态。

### Classes

#### `AudioPlayer`

音频播放器。音源支持本地文件、打包资源、HTTP/HTTPS 地址及 base64 `data:` 地址；`data:` 内容解码后不得超过 32 MB。

#### `AudioPlayer.id`

只读 `string`，播放器标识。

#### `AudioPlayer.playing`

只读 `boolean`，表示是否正在播放。仍有播放请求且正在缓冲时也为 `true`。

#### `AudioPlayer.paused`

只读 `boolean`，表示播放器是否暂停。

#### `AudioPlayer.muted`

可读写 `boolean`。静音时输出音量为零，不改变 `volume` 的值。

#### `AudioPlayer.loop`

可读写 `boolean`，设置当前音源是否循环播放。

#### `AudioPlayer.isLoaded`

只读 `boolean`，表示音源是否已加载并可播放。

#### `AudioPlayer.isBuffering`

只读 `boolean`，表示是否正在缓冲。

#### `AudioPlayer.isAudioSamplingSupported`

只读 `boolean`，始终为 `false`。

#### `AudioPlayer.currentTime`

只读 `number`，当前播放位置，单位为秒。

#### `AudioPlayer.duration`

只读 `number`，音源时长，单位为秒；尚未取得时长时为 `0`。

#### `AudioPlayer.volume`

可读写 `number`，范围为 `0` 到 `1`；超出范围的值会钳制到边界。

#### `AudioPlayer.playbackRate`

只读 `number`，当前播放倍速。可通过 `setPlaybackRate()` 修改，支持范围为 `0.125` 到 `2`。HarmonyOS API 20 之前仅支持 `0.5`、`0.75`、`1`、`1.25`、`1.5`、`1.75` 和 `2`；API 20 起支持该范围内任意倍速。设置低于 `0.125` 的倍速会报错。

#### `AudioPlayer.shouldCorrectPitch`

可读写 `boolean`，始终为 `true`；设为 `false` 会报错。

#### `AudioPlayer.play()`

开始播放。播放结束后再次调用会从头播放。

#### `AudioPlayer.pause()`

暂停播放。

#### `AudioPlayer.replace(source)`

更换音源；传入 `null` 会卸载当前音源。

#### `AudioPlayer.seekTo(seconds, toleranceMillisBefore?, toleranceMillisAfter?)`

返回 `Promise<void>`，在系统完成跳转后兑现。跳转位置以秒为单位，超出音源范围时会钳制到开头或结尾；两个容差参数不生效。

#### `AudioPlayer.setPlaybackRate(rate, pitchCorrectionQuality?)`

设置播放倍速，范围和系统版本限制与 `playbackRate` 相同。

##### HarmonyOS 上不支持的参数

- `pitchCorrectionQuality`：不生效。

#### `AudioPlayer.setAudioSamplingEnabled(enabled)`

##### HarmonyOS 上不支持

- 播放器不提供解码后的 PCM 帧；传入 `true` 会报错，传入 `false` 不启用采样。

#### `AudioPlayer.setActiveForLockScreen(active, metadata?, options?)`

接管或取消锁屏播放控制。同一时间只有一个播放器可以接管。`metadata` 可设置标题、艺术家、专辑和封面；`showSeekForward`、`showSeekBackward` 可显示快进和快退按钮，步进为 10 秒。`isLiveStream: true` 会隐藏时长和跳转控制，实际布局由系统决定。

#### `AudioPlayer.updateLockScreenMetadata(metadata)`

更新锁屏元数据；仅在该播放器已接管锁屏控制时生效。

#### `AudioPlayer.clearLockScreenControls()`

取消该播放器的锁屏控制。

#### `AudioPlayer.remove()`

释放播放器资源。

#### `AudioPlaylist`

播放列表。曲目切换时重新加载音源，不保证无缝衔接。

#### `AudioPlaylist.id`

只读 `string`，播放列表标识。

#### `AudioPlaylist.currentIndex`

只读 `number`，当前曲目索引。

#### `AudioPlaylist.trackCount`

只读 `number`，曲目数量。

#### `AudioPlaylist.sources`

只读 `AudioSourceInfo[]`，播放列表中的音源。

#### `AudioPlaylist.playing`

只读 `boolean`，表示播放列表是否正在播放。

#### `AudioPlaylist.muted`

可读写 `boolean`，设置播放列表是否静音。

#### `AudioPlaylist.isLoaded`

只读 `boolean`，表示当前曲目是否已加载。

#### `AudioPlaylist.isBuffering`

只读 `boolean`，表示当前曲目是否正在缓冲。

#### `AudioPlaylist.currentTime`

只读 `number`，当前曲目播放位置，单位为秒。

#### `AudioPlaylist.duration`

只读 `number`，当前曲目时长，单位为秒；尚未取得时长时为 `0`。

#### `AudioPlaylist.volume`

可读写 `number`，范围为 `0` 到 `1`；超出范围的值会钳制到边界。

#### `AudioPlaylist.playbackRate`

可读写 `number`，播放倍速，限制与 `AudioPlayer.setPlaybackRate()` 相同。

#### `AudioPlaylist.loop`

可读写 `AudioPlaylistLoopMode`，设置播放列表循环方式。

#### `AudioPlaylist.play()`

开始播放当前曲目。

#### `AudioPlaylist.pause()`

暂停播放。

#### `AudioPlaylist.next()`

切换到下一首。到达末尾时，`loop: 'all'` 会回到第一首，其他模式下不动作。

#### `AudioPlaylist.previous()`

切换到上一首。位于第一首时，`loop: 'all'` 会跳到最后一首，其他模式下不动作。

#### `AudioPlaylist.skipTo(index)`

切换到指定索引；索引越界时不动作。

#### `AudioPlaylist.seekTo(seconds)`

返回 `Promise<void>`，在系统完成跳转后兑现。跳转至当前曲目的指定秒数，超出范围时钳制到曲目边界。

#### `AudioPlaylist.add(source)`

将音源追加到列表末尾；空音源不加入。

#### `AudioPlaylist.insert(source, index)`

在指定位置插入音源；音源为空或索引不在 `0` 到列表长度之间时不动作。

#### `AudioPlaylist.remove(index)`

移除指定曲目；索引越界时不动作。移除当前曲目后会切换到相邻曲目。

#### `AudioPlaylist.clear()`

清空播放列表并卸载当前曲目。

#### `AudioPlaylist.destroy()`

释放播放列表资源。

#### `AudioRecorder`

录音器。录音前须先取得麦克风权限并调用 `prepareToRecordAsync()`。

#### `AudioRecorder.id`

只读 `string`，录音器标识。

#### `AudioRecorder.currentTime`

只读 `number`，当前录音时长，单位为秒；暂停后继续录制时会累计。

#### `AudioRecorder.isRecording`

只读 `boolean`，表示是否正在录音。

#### `AudioRecorder.uri`

只读 `string | null`，录音文件的 `file://` 地址；文件尚未生成时为 `null`。

#### `AudioRecorder.prepareToRecordAsync(options?)`

返回 `Promise<void>`，准备录音并应用参数。`options` 会覆盖同名默认项。`directory` 支持 `'cache'`（默认，系统可回收）和 `'document'`（应用持久目录），两者都位于应用私有目录。

#### `AudioRecorder.record(options?)`

开始录音，须先准备录音。`options.atTime` 只支持 `0`；大于 `0` 会报错。`options.forDuration` 可设置录制时长，到时自动停止。

#### `AudioRecorder.stop()`

返回 `Promise<void>`，停止录音并完成文件写入。

#### `AudioRecorder.pause()`

暂停录音；再次调用 `record()` 会继续录制。

#### `AudioRecorder.recordForDuration(seconds)`

录制指定秒数后自动停止。该方法已弃用，建议使用 `record({ forDuration: seconds })`。

#### `AudioRecorder.startRecordingAtTime(seconds)`

该方法已弃用，只支持 `0`；传入大于 `0` 的值会报错。

#### `AudioRecorder.getAvailableInputs()`

返回 `RecordingInput[]`，列出可用录音输入设备。须先准备录音。

#### `AudioRecorder.getCurrentInput()`

返回 `Promise<RecordingInput>`，取得当前录音输入设备。须先准备录音。

#### `AudioRecorder.setInput(uid)`

切换录音输入设备，`uid` 取自 `RecordingInput.uid`。需要 HarmonyOS API 21 及以上；较低版本会报错。

#### `AudioRecorder.getStatus()`

返回当前 `RecorderState`。

#### `AudioStream`

实时麦克风 PCM 流。实际 `sampleRate` 和 `channels` 在 `start()` 成功后可用。采集被音频中断时流会停止，恢复后需再次调用 `start()`。

#### `AudioStream.id`

只读 `string`，流标识。

#### `AudioStream.sampleRate`

只读 `number`，实际采样率，单位为 Hz；开始采集前为 `0`。

#### `AudioStream.channels`

只读 `number`，实际声道数；开始采集前为 `0`。

#### `AudioStream.isStreaming`

只读 `boolean`，表示是否正在采集。

#### `AudioStream.start()`

返回 `Promise<void>`，开始采集。须先取得麦克风权限；设备无法提供请求的采样率时会报错。

#### `AudioStream.stop()`

停止采集并释放流资源。应用进入后台时，实时流会停止；回到前台后不会自动重新开始。

### Event subscriptions

#### `playbackStatusUpdate`

播放器状态变化事件，载荷类型为 `AudioStatus`。开始订阅时会收到当前状态。

#### `audioSampleUpdate`

HarmonyOS 上不会触发：播放器不提供解码后的 PCM 帧。

#### `playlistStatusUpdate`

播放列表状态变化事件，载荷类型为 `AudioPlaylistStatus`。

#### `trackChanged`

曲目切换事件，载荷包含 `previousIndex` 和 `currentIndex`。

#### `recordingStatusUpdate`

录音状态事件，载荷类型为 `RecordingStatus`，包含录音是否结束、错误及录音文件地址。

#### `audioStreamBuffer`

实时采集缓冲事件，载荷类型为 `AudioStreamBuffer`。

#### `audioStreamStatus`

实时流状态事件，载荷类型为 `AudioStreamStatus`。

### Types

#### `InterruptionMode`

支持 `'mixWithOthers'`、`'doNotMix'` 和 `'duckOthers'`，默认 `'mixWithOthers'`，分别表示混音、请求其他音频暂停和请求其他音频降低音量。音频并发行为由系统处理。

#### `AudioPlaylistLoopMode`

支持 `'none'`、`'single'` 和 `'all'`，默认 `'none'`，分别表示不循环、循环当前曲目和循环整个列表。

#### `AudioStreamEncoding`

支持 `'float32'` 和 `'int16'`，默认 `'float32'`。

#### `PitchCorrectionQuality`

##### HarmonyOS 上不支持

- `setPlaybackRate()` 不使用此参数。

#### `AudioSource`

音源可为 URI 字符串、`require()` 返回的数字、`null`，或包含以下字段的对象：

- `uri`：本地文件路径或 `file://` 地址、`asset://` 或 `rawfile://` 打包资源地址、HTTP/HTTPS 地址或 base64 `data:` 地址。
- `assetId`：打包资源 ID。
- `name`：显示名称。
- `headers`：远程音源请求头。

`data:` 地址须使用 base64 编码，解码后最大为 32 MB。

#### `AudioSourceInfo`

播放列表音源信息，包含可选的 `uri` 和 `name`。

#### `AudioPlayerOptions`

播放器配置：`updateInterval`（状态事件间隔，默认 500 毫秒，最小 16 毫秒）、`downloadFirst`（是否先下载音源，默认 `false`）、`keepAudioSessionActive`（暂停或播放结束后是否保留音频会话，默认 `false`）和 `preferredForwardBufferDuration`（预缓冲秒数，默认 `0`，由系统决定）。

##### HarmonyOS 上不支持的属性

- `crossOrigin`：不生效。

#### `AudioLoadOptions`

`AudioPlayerOptions` 的别名，已弃用。

#### `PreloadOptions`

包含可选的 `preferredForwardBufferDuration`，预缓冲时长默认 10 秒。

#### `AudioStatus`

播放器状态对象包含：`id`、`currentTime`、`duration`、`playing`、`loop`、`didJustFinish`、`isBuffering`、`isLoaded`、`mute`、`playbackRate`、`shouldCorrectPitch`、`playbackState`、`timeControlStatus`、`reasonForWaitingToPlay`、`isLive`、`currentOffsetFromLive` 和 `error`。`reasonForWaitingToPlay` 与 `currentOffsetFromLive` 始终为 `null`；`shouldCorrectPitch` 始终为 `true`。`playbackState` 为 `'buffering'`、`'ready'`、`'ended'`、`'idle'` 或 `'unknown'`；`timeControlStatus` 为 `'playing'` 或 `'paused'`。

##### HarmonyOS 上未提供的字段

- `mediaServicesDidReset`：状态中不提供该字段。

#### `AudioEvents`

播放器事件载荷定义：`playbackStatusUpdate` 的载荷为 `AudioStatus`，`audioSampleUpdate` 的载荷为 `AudioSample`。

#### `AudioMetadata`

锁屏元数据的可选字段：`title`、`artist`、`albumTitle` 和 `artworkUrl`。

#### `AudioLockScreenOptions`

锁屏选项包括 `showSeekForward`、`showSeekBackward` 和 `isLiveStream`。快进、快退按钮的步进均为 10 秒；直播模式不显示时长或跳转控制。

#### `AudioMode`

HarmonyOS 支持的音频模式字段：

- `playsInSilentMode`：默认 `true`。设为 `false` 后，系统静音或振动时会暂停播放，并拒绝新的播放请求。
- `interruptionMode`：并发模式，默认为 `'mixWithOthers'`。
- `shouldPlayInBackground`：是否允许后台播放，默认 `false`。
- `shouldRouteThroughEarpiece`：是否使用听筒输出，默认 `false`；需要 HarmonyOS API 20 及以上，较低版本设为 `true` 会报错。
- `allowsBackgroundRecording`：是否允许后台录音，默认 `false`。

后台播放或录音须同时启用对应的 Config Plugin 选项和音频模式字段。未同时启用时，应用进入后台后相应播放或录音会暂停；回到前台后播放器和录音器会恢复，实时麦克风流需重新调用 `start()`。

##### HarmonyOS 上不支持的属性

- `allowsRecording`：不提供该录音会话开关。

#### `AudioPlaylistOptions`

播放列表选项：`sources` 初始音源列表，默认 `[]`；`updateInterval` 状态事件间隔，默认 500 毫秒；`loop` 循环模式，默认 `'none'`。

##### HarmonyOS 上不支持的属性

- `crossOrigin`：不生效。

#### `AudioPlaylistStatus`

播放列表状态对象包含：`id`、`currentIndex`、`trackCount`、`currentTime`、`duration`、`playing`、`isBuffering`、`isLoaded`、`playbackRate`、`muted`、`volume`、`loop` 和 `didJustFinish`。

#### `AudioPlaylistEvents`

播放列表事件载荷定义：`playlistStatusUpdate` 的载荷为 `AudioPlaylistStatus`；`trackChanged` 的载荷包含 `previousIndex` 和 `currentIndex`。

#### `AudioStreamOptions`

实时流参数：`sampleRate` 默认为 48000 Hz，须为正整数且设备需支持；`channels` 只支持 `1` 或 `2`，默认为 `1`；`encoding` 默认为 `'float32'`，也可设为 `'int16'`；`onBuffer` 在有新缓冲时接收 `AudioStreamBuffer`。

#### `AudioStreamBuffer`

缓冲载荷包含 `data: ArrayBuffer`、实际 `sampleRate`、实际 `channels` 和从采集开始计算的秒数 `timestamp`。`float32` 取值范围为 `[-1, 1)`；`int16` 为小端有符号整数。多声道样本交错排列。

#### `AudioStreamStatus`

包含 `isStreaming: boolean`，表示实时流状态。

#### `AudioStreamEvents`

实时流事件载荷定义：`audioStreamBuffer` 的载荷为 `AudioStreamBuffer`；`audioStreamStatus` 的载荷为 `AudioStreamStatus`。

#### `AudioStreamResult`

Hook `useAudioStream()` 返回的对象，包含 `stream: AudioStream` 和 `isStreaming: boolean`。

#### `RecordingOptions`

录音配置支持 `directory`、`extension`、`sampleRate`、`numberOfChannels`、`bitRate` 和 `isMeteringEnabled`。目录默认为 `'cache'`，也可设为 `'document'`；扩展名只支持 `.m4a` 和 `.mp3`。采样率范围为 8000 到 96000 Hz，声道数为 1 到 2，码率为 32000 到 320000 bps；越界值会钳制到范围边界。计量默认关闭。

##### HarmonyOS 上不支持的属性

- `android`、`ios`：不读取这些嵌套配置。

#### `RecordingOptionsWeb`

可选字段 `mimeType` 用于在未指定扩展名时选择格式：`audio/mpeg` 录为 MP3，其他值录为 M4A。`bitsPerSecond` 可作为 `bitRate` 的备用值。

#### `RecordingStartOptions`

`atTime` 只支持 `0`；`forDuration` 可设置录制秒数，到时自动停止。

#### `RecordingDirectory`

`'cache' | 'document'`。前者可由系统回收，后者保存在应用持久文件目录。

#### `RecordingInput`

录音输入设备包含 `name`、`type` 和 `uid`。输入设备切换需要 HarmonyOS API 21 及以上。

#### `RecorderState`

录音状态包含 `canRecord`、`isRecording`、`durationMillis`、`url`、`mediaServicesDidReset` 和可选的 `metering`。`mediaServicesDidReset` 始终为 `false`；仅在录音且开启计量时提供 `metering`。

#### `RecordingStatus`

录音事件载荷包含 `id`、`isFinished`、`hasError`、`error` 和 `url`。

#### `RecordingEvents`

录音事件载荷定义：`recordingStatusUpdate` 的载荷为 `RecordingStatus`。

##### HarmonyOS 上未提供的字段

- `mediaServicesDidReset`：事件载荷中不提供该字段。

#### `AudioSample`

播放器音频采样数据类型。

##### HarmonyOS 上不支持

- `AudioSample` 不会产生数据，因为播放器不提供解码后的 PCM 帧。

#### `AudioSampleChannel`

音频采样的单声道 PCM 帧数据类型。

##### HarmonyOS 上不支持

- 播放器不提供该类型的数据。

#### `PermissionResponse`

权限响应包含 `status`、`granted`、`expires` 和 `canAskAgain`；`expires` 始终为 `'never'`。

#### `PermissionExpiration`

权限到期信息的类型为 `'never' | number`；HarmonyOS 权限响应始终返回 `'never'`。

### Enums

#### `PermissionStatus`

权限状态枚举值为 `DENIED`、`GRANTED` 和 `UNDETERMINED`，对应 `'denied'`、`'granted'` 和 `'undetermined'`。

### Error codes

播放器、录音器、实时流及权限请求失败时，错误对象的 `code` 可能包含以下值。具体方法的行为和系统限制见对应 API 子章节。

#### 音源和播放

| 错误码 | 含义 |
| --- | --- |
| `ERR_AUDIO_INVALID_SOURCE` | 音源为空、格式无效或不受支持。 |
| `ERR_AUDIO_INVALID_DATA_URI` | `data:` 音源格式错误或未使用 base64。 |
| `ERR_AUDIO_DATA_URI_TOO_LARGE` | `data:` 音源解码后超过 32 MB。 |
| `ERR_AUDIO_PLAYER_LOAD`、`ERR_AUDIO_PLAYER_INITIALIZE`、`ERR_AUDIO_PLAYER_INITIALIZE_TIMEOUT`、`ERR_AUDIO_PLAYER_STATE` | 音源加载、播放器初始化或播放状态失败。 |
| `ERR_AUDIO_NOT_LOADED` | 操作要求音源已加载，但当前没有可用音源。 |
| `ERR_AUDIO_PLAYER_RELEASED` | 播放器已释放。 |
| `ERR_AUDIO_SEEK`、`ERR_AUDIO_SEEK_TIMEOUT` | 跳转失败或未能及时完成。 |
| `ERR_AUDIO_PRELOAD` | 音源预加载失败。 |
| `ERR_AUDIO_PLAYBACK_RATE_UNSUPPORTED` | 当前系统版本不支持所设倍速。 |
| `ERR_AUDIO_PITCH_CORRECTION_UNSUPPORTED` | 不支持关闭音高修正。 |
| `ERR_AUDIO_SAMPLING_UNSUPPORTED` | 不支持播放器 PCM 采样。 |
| `ERR_AUDIO_INVALID_MODE`、`ERR_AUDIO_INVALID_INTERRUPTION_MODE` | 音频模式或并发模式无效。 |
| `ERR_AUDIO_EARPIECE_ROUTING_UNSUPPORTED` | 当前 HarmonyOS API 版本不支持听筒路由。 |

#### 录音和输入设备

| 错误码 | 含义 |
| --- | --- |
| `ERR_AUDIO_RECORDING_PERMISSION`、`ERR_AUDIO_PERMISSION_REQUEST` | 麦克风未授权或权限请求失败。 |
| `ERR_AUDIO_RECORDING_UNAVAILABLE` | 当前应用状态下不能录音。 |
| `ERR_AUDIO_RECORDING_DIRECTORY` | 录音目录不是 `'cache'` 或 `'document'`。 |
| `ERR_AUDIO_RECORDING_FORMAT_UNSUPPORTED` | 录音扩展名不是 `.m4a` 或 `.mp3`。 |
| `ERR_AUDIO_INVALID_RECORDING_TIME`、`ERR_AUDIO_RECORDING_AT_TIME_UNSUPPORTED` | 录音开始时间无效或不受支持。 |
| `ERR_AUDIO_INVALID_RECORDING_DURATION` | 录音时长不是有效的非负数。 |
| `ERR_AUDIO_RECORDER_ALREADY_PREPARED`、`ERR_AUDIO_RECORDER_NOT_PREPARED`、`ERR_AUDIO_RECORDER_PREPARE`、`ERR_AUDIO_RECORDER_RELEASED`、`ERR_AUDIO_RECORDING_STOP` | 录音器准备、状态或停止录音失败。 |
| `ERR_AUDIO_INPUT_UNAVAILABLE`、`ERR_AUDIO_INVALID_INPUT`、`ERR_AUDIO_INPUT_SELECTION_UNAVAILABLE`、`ERR_AUDIO_INPUT_NOT_FOUND` | 录音输入不可用、标识无效或无法切换。 |

#### 实时流

| 错误码 | 含义 |
| --- | --- |
| `ERR_AUDIO_STREAM_OPTIONS` | 实时流参数格式或取值无效。 |
| `ERR_AUDIO_STREAM_RELEASED` | 实时流已释放。 |
| `ERR_AUDIO_STREAM_START` | 实时流启动失败。 |

#### `ERR_AUDIO_NOTIFICATION_PERMISSION`

通知权限请求失败。

### Permissions

#### `ohos.permission.MICROPHONE`

录音器和实时麦克风流都需要麦克风权限。通过 `requestRecordingPermissionsAsync()` 请求授权；调用 `prepareToRecordAsync()` 或 `AudioStream.start()` 前须确认权限已授予。应用未声明权限时，权限请求会以 `ERR_AUDIO_PERMISSION_REQUEST` 失败。

#### 通知显示权限

`requestNotificationPermissionsAsync()` 查询并请求通知显示权限，结果以 `PermissionResponse` 返回；请求失败时会抛出 `ERR_AUDIO_NOTIFICATION_PERMISSION`。

## 后台播放和录音

要在后台播放或录音，需要在 `app.json` 的 `plugins` 中配置 `@expo-harmony/expo-audio`。`enableBackgroundPlayback` 默认开启，`enableBackgroundRecording` 默认关闭。录音还需要麦克风权限，`microphonePermission` 可设置向用户展示的用途说明；设为 `false` 可关闭插件添加的麦克风权限。只在前台播放时，可以关闭后台选项和麦克风权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
