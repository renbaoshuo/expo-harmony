# @expo-harmony/expo-status-bar

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-status-bar) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/status-bar/)

为 HarmonyOS 上的 React Native 应用提供 Expo StatusBar 的原生实现，与官方 `expo-status-bar` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-status-bar expo-status-bar@~57.0.1
```

在 `app.json` 的 `expo.plugins` 中加入 `["@expo-harmony/expo-status-bar", { "style": "dark", "hidden": false }]`，可以在 JavaScript 启动前设置状态栏。`style` 接受 `'light'` 或 `'dark'`。`hidden` 接受布尔值，`false` 显式显示状态栏。省略的属性由窗口默认设置决定。

系统在受支持设备的全屏或最大化主窗口上应用状态栏设置。自由窗口模式下由系统管理状态栏。

## API 对照表

### Components

#### `StatusBar`

控制状态栏文字和图标颜色，以及状态栏的显示和隐藏。参数见 [`StatusBarProps`](#statusbarprops)。

### Methods

#### `StatusBar.setStyle(style, animated?)`

设置状态栏文字和图标颜色，`style` 接受 [`StatusBarStyle`](#statusbarstyle)，`animated` 为可选布尔值。返回 `void`。

- 当前 RNOH 的状态栏样式切换无动画效果。

#### `StatusBar.setHidden(hidden, animation?)`

显示或隐藏状态栏。`hidden` 为布尔值；`animation` 接受 [`StatusBarAnimation`](#statusbaranimation)，省略时默认为 `'none'`。返回 `void`。

- 当前 RNOH 的状态栏显隐使用系统默认行为，`animation` 不生效。

#### `setStatusBarStyle(style, animated?)`

已弃用。参数和返回值与 `StatusBar.setStyle()` 相同。

#### `setStatusBarHidden(hidden, animation?)`

已弃用。参数和返回值与 `StatusBar.setHidden()` 相同。

### Types

#### `StatusBarProps`

`StatusBar` 的属性：`style` 为可选的 [`StatusBarStyle`](#statusbarstyle)，默认值为 `'auto'`；`hidden` 为可选布尔值，默认显示状态栏；`animated` 为可选布尔值；`hideTransitionAnimation` 为可选的 [`StatusBarAnimation`](#statusbaranimation)，默认值为 `'fade'`。

- 当前 RNOH 的状态栏样式切换无动画效果。

#### `StatusBarStyle`

可选值为 `'auto'`、`'inverted'`、`'light'` 和 `'dark'`。`'light'` 设置浅色文字和图标，`'dark'` 设置深色文字和图标；`'auto'` 在系统浅色模式下使用深色文字和图标，在深色模式下使用浅色；`'inverted'` 使用相反颜色。

#### `StatusBarAnimation`

可选值为 `'none'`、`'fade'` 和 `'slide'`。

- 当前 RNOH 的状态栏显隐使用系统默认行为。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).
