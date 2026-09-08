# @expo-harmony/expo-brightness

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-brightness)

为 HarmonyOS 上的 React Native 应用提供 Expo Brightness 的原生实现，与官方同版本的 `expo-brightness` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-brightness expo-brightness@55.0.13
```

当前窗口亮度无需申请权限，只在窗口处于前台且获焦时生效。系统亮度相关接口沿用官方非 Android 平台行为：读写作用于当前窗口，恢复跟随系统和设置亮度模式为空操作；亮度变化事件不会触发。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
