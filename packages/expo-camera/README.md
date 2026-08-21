# @expo-harmony/expo-camera

为 HarmonyOS 上的 React Native 应用提供 Expo Camera 的原生实现，与官方同版本的 `expo-camera` 配套使用。

当前实现基于 HarmonyOS CameraKit 和 AVRecorder，覆盖运行时相机/麦克风权限、前后摄切换、相机预览、拍照、录像、缩放、闪光灯、手电筒、对焦、暂停与恢复预览。条码识别相关 API 由于没有接入 Scan Kit，相关函数保留空实现。

## 安装

同时安装官方 JavaScript 包和 HarmonyOS 原生包：

```sh
yarn add expo-camera @expo-harmony/expo-camera
```

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
