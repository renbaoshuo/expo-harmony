# @expo-harmony/expo-audio

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-audio)

为 HarmonyOS 上的 React Native 应用提供 Expo Audio 的原生实现，支持音频播放、播放列表、预加载、录音、音频焦点、后台播放和锁屏媒体控制，与官方同版本的 `expo-audio` 配套使用。JavaScript API、类型和 React Hooks 由官方 `expo-audio` 包提供。

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

受 HarmonyOS Media Kit 能力限制，当前不支持 PCM 音频采样和关闭变调校正，录音格式仅支持 M4A（AAC）和 MP3；播放列表切换也不保证无缝衔接。调用不受支持的能力会抛出错误。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
