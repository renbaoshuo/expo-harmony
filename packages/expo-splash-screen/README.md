# @expo-harmony/expo-splash-screen

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-splash-screen) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/splash-screen/)

为 HarmonyOS 上的 React Native 应用提供 Expo Splash Screen 的原生实现，与官方同版本的 `expo-splash-screen` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-splash-screen expo-splash-screen
```

## 配置

在 `app.json` 的 `plugins` 中添加 `@expo-harmony/expo-splash-screen`，即可设置启动画面的外观：

```json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-splash-screen",
        {
          "backgroundColor": "#FFFFFF",
          "image": "./assets/splash.png",
          "imageWidth": 160,
          "resizeMode": "contain",
          "dark": {
            "backgroundColor": "#000000",
            "image": "./assets/splash-dark.png"
          }
        }
      ]
    ]
  }
}
```

也可以在 `app.config.ts` 中调用插件函数，并通过 `harmony` 单独设置鸿蒙外观：

```ts
import splashScreen from '@expo-harmony/expo-splash-screen/plugin';

export default {
  expo: {
    plugins: [
      splashScreen({
        backgroundColor: '#FFFFFF',
        image: './assets/splash.png',
        harmony: { resizeMode: 'contain' },
      }),
    ],
  },
};
```

`backgroundColor` 接受 `#RRGGBB` 或 `#RRGGBBAA`，默认值为 `#FFFFFF`。`image` 接受项目中的 png、jpg、jpeg、svg、webp 或 gif 文件路径；未配置时只显示背景色。`resizeMode` 支持 `contain`、`cover` 和 `native`。`contain` 按 `imageWidth` 等比缩放后居中显示，默认宽度为 100；`cover` 铺满窗口并裁剪超出的部分；`native` 按原始尺寸居中显示。

可在 `dark` 中设置深色模式的背景色和图片。深色背景色未设置时沿用 `backgroundColor`，深色图片未设置时沿用基础图片。`expo.userInterfaceStyle` 设为 `automatic` 时，启动画面会使用对应的深浅色资源；设为 `light` 或 `dark` 时会固定使用相应外观。修改启动画面配置后，需要重新生成原生工程。

冷启动时会先显示系统启动窗口，应用窗口准备好后会显示应用内启动画面，直到它自动隐藏或调用隐藏方法。应用内启动画面覆盖整个窗口，显示期间会拦截触摸事件。不注册插件时只显示系统启动窗口。

## 使用

启动画面默认会在应用窗口准备好后自动隐藏。若要等字体或接口数据加载完成后再隐藏，可在模块顶层调用 `SplashScreen.preventAutoHideAsync()`，就绪后调用 `SplashScreen.hide()`：

```ts
import * as SplashScreen from 'expo-splash-screen';

SplashScreen.preventAutoHideAsync();

// 加载字体、请求接口等
SplashScreen.hide();
```

## API 对照表

### Methods

#### `SplashScreen.hide()`

同步发起隐藏请求，返回 `void`。默认在 `400` 毫秒内淡出；可用 `setOptions()` 设置动画。`fade` 为 `false` 或 `duration` 为 `0` 时直接隐藏。启动画面未显示时调用无效果；应用内容尚未准备好时调用也会隐藏启动画面。

#### `SplashScreen.hideAsync()`

发出与 `hide()` 相同的隐藏请求，返回 `Promise<void>`。Promise 不等待淡出动画结束。

#### `SplashScreen.preventAutoHideAsync()`

返回 `Promise<boolean>`，成功时解析为 `true`。调用后会阻止启动画面自动隐藏，直到调用 `hide()` 或 `hideAsync()`；若启动画面已经隐藏，此方法不会重新显示它。

#### `SplashScreen.setOptions(options)`

设置隐藏启动画面时的动画，返回 `void`。需要在隐藏前设置才会生效；每次调用会应用整组选项，省略的字段恢复默认值。参数类型为 `SplashScreenOptions`。

### Types

#### `SplashScreenOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `duration` | `number` | 淡出时长，单位为毫秒，须为 `0` 到 `2147483547` 范围内的有限数值，默认值为 `400`。 |
| `fade` | `boolean` | 是否淡出隐藏启动画面，默认值为 `true`。 |

### Error codes

#### `ERR_SPLASH_SCREEN_OPTIONS`

`setOptions()` 的 `duration` 不是有限数值或超出 `0` 到 `2147483547` 的范围，或 `fade` 不是布尔值时抛出。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
