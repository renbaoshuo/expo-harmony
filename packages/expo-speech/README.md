# @expo-harmony/expo-speech

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-speech) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/speech/)

为 HarmonyOS 上的 React Native 应用提供 Expo Speech 的原生实现，与官方同版本的 `expo-speech` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 19（HarmonyOS 5.1.1）。

```bash
npm install @expo-harmony/expo-speech expo-speech
```

## API 对照表

### Constants

#### `Speech.maxSpeechInputLength`

类型：`number`。

返回 `10000`，表示文本长度上限，单位为 UTF-16 代码单元。检查文本前会移除首尾空白；超出上限时，`Speech.speak()` 会通过 `onError` 报告错误。

### Methods

#### `Speech.speak(text, options?)`

参数：`text` 为待播报文本；`options` 为可选的 `SpeechOptions`。

返回 `void`，将文本加入队列并按调用顺序播报。语音由系统已安装的离线音色合成，不会自动下载音色。空文本不会播报，但仍会触发 `onStart` 和 `onDone`。

| 选项 | HarmonyOS 行为 |
| --- | --- |
| `language` | 语言标签。优先匹配该语言，再匹配同一语种的音色；没有匹配项时使用系统语言对应的音色，仍找不到则使用列表中的第一个音色。 |
| `voice` | `getAvailableVoicesAsync()` 返回的音色 `identifier`，优先于 `language`。音色未安装或标识无效时，通过 `onError` 报告错误。 |
| `rate` / `pitch` | 默认值均为 `1`，有效范围为 `0.5` 到 `2`。非有限数值或超出范围时，通过 `onError` 报告错误。 |
| `volume` | 默认值为 `1`。有限数值会限制在 `0` 到 `1`；非有限数值时通过 `onError` 报告错误。 |

使用 `en-US` 音色时，数字按英语读法处理；其他音色使用系统语音服务的默认数字读法。设备不支持语音合成或没有可用离线音色时，通过 `onError` 报告错误。

#### `Speech.stop()`

返回 `Promise<void>`，停止当前播报并清空等待队列。当前文本和队列中每条被取消的文本都会触发一次 `onStopped`。

#### `Speech.isSpeakingAsync()`

返回 `Promise<boolean>`，表示系统当前是否正在合成或播放语音。队列中尚未开始的文本不计入状态，因此可能返回 `false`。

#### `Speech.getAvailableVoicesAsync()`

返回 `Promise<Voice[]>`，列出系统提供的已安装离线音色。设备不支持语音合成时返回空数组；查询失败时 Promise 会被拒绝。系统未提供安装状态的音色仍可能出现在列表中，选用后若不可用会通过 `onError` 报告错误。

#### `Speech.pause()`

返回 `Promise<void>`。

- HarmonyOS 系统语音服务不支持暂停，调用会抛出 `UnavailabilityError`。

#### `Speech.resume()`

返回 `Promise<void>`。

- HarmonyOS 系统语音服务不支持恢复播报，调用会抛出 `UnavailabilityError`。

### Event subscriptions

#### `SpeechOptions.onStart`

当前文本开始播报时调用，不接收参数。

#### `SpeechOptions.onDone`

当前文本播报完成时调用，不接收参数。空文本也会触发此回调。

#### `SpeechOptions.onStopped`

当前文本因调用 `Speech.stop()` 被停止或从队列中取消时调用，不接收参数。

#### `SpeechOptions.onError`

文本无法播报或选项校验失败时调用，参数为 `Error`。`error.message` 包含对应错误码。

#### `SpeechOptions.onBoundary`

- HarmonyOS 系统不提供逐词位置回调，因此此回调不会触发。

#### `SpeechOptions.onMark`

- HarmonyOS 系统不提供标记事件，因此此回调不会触发。

#### `SpeechOptions.onPause`

- HarmonyOS 系统不提供暂停事件，因此此回调不会触发。

#### `SpeechOptions.onResume`

- HarmonyOS 系统不提供恢复事件，因此此回调不会触发。

### Types

#### `SpeechOptions`

`Speech.speak()` 的可选参数，包含 `language?: string`、`voice?: string`、`rate?: number`、`pitch?: number`、`volume?: number`。回调选项见 Event subscriptions。

- `useApplicationAudioSession`：HarmonyOS 系统语音服务不提供此选项对应的音频会话控制。
- `_voiceIndex`：HarmonyOS 不按列表序号选择音色；请使用 `voice` 标识。

#### `Voice`

由 `getAvailableVoicesAsync()` 返回的音色信息。

| 属性 | 类型 | HarmonyOS 行为 |
| --- | --- | --- |
| `identifier` | `string` | 音色标识；传给 `SpeechOptions.voice` 时使用返回的完整字符串。 |
| `name` | `string` | 系统提供的音色名称；名称为空时与 `identifier` 相同。 |
| `language` | `string` | 音色语言标签，例如 `zh-CN` 或 `en-US`；返回时下划线会转换为连字符。 |
| `quality` | `VoiceQuality` | 始终为 `VoiceQuality.Default`。 |

#### `SpeechEventCallback`

SDK 定义的回调类型带有事件参数；HarmonyOS 触发 `SpeechOptions` 回调时不提供事件对象。

#### `NativeBoundaryEvent`

类型为 `{ charIndex: number; charLength: number }`。

- HarmonyOS 系统不提供逐词位置回调，因此不会产生此类型的事件。

#### `NativeBoundaryEventCallback`

接收 `NativeBoundaryEvent` 的回调类型。

- HarmonyOS 系统不提供逐词位置回调，因此不会调用此回调。

#### `WebVoice`

- HarmonyOS 的音色查询返回 `Voice[]`，不会返回此类型或其附加字段。

### Enums

#### `VoiceQuality`

表示音色质量。HarmonyOS 返回的所有 `Voice` 均使用 `VoiceQuality.Default`。

##### `VoiceQuality.Default`

系统返回的音色均使用此值。

##### `VoiceQuality.Enhanced`

- HarmonyOS 不提供音色质量等级，返回的音色不会使用此值。

### Error codes

#### `ERR_SPEECH_INPUT_IS_TOO_LONG`

`Speech.speak()` 的文本去除首尾空白后，长度超过 `Speech.maxSpeechInputLength` 时通过 `onError` 报告。

#### `ERR_SPEECH_INVALID_OPTIONS`

`rate` 或 `pitch` 不是有限数值或不在 `0.5` 到 `2` 之间，或 `volume` 不是有限数值时通过 `onError` 报告。

#### `ERR_SPEECH_UNAVAILABLE`

设备不支持语音合成时通过 `onError` 报告。此时 `getAvailableVoicesAsync()` 返回空数组。

#### `ERR_SPEECH_NO_VOICES`

设备没有已安装的离线音色可供播报时通过 `onError` 报告。

#### `ERR_SPEECH_INVALID_VOICE`

`voice` 指定的音色未安装或不在可用音色列表中时通过 `onError` 报告。

#### `ERR_SPEECH_UNABLE_TO_GET_VOICES`

音色查询失败时，`getAvailableVoicesAsync()` 的 Promise 以此错误拒绝。

#### `ERR_SPEECH_STOP`

系统无法停止语音服务时，`Speech.stop()` 的 Promise 以此错误拒绝；被取消的文本会通过 `onError` 报告停止错误。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
