# @expo-harmony/expo-navigation-bar

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-navigation-bar) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/navigation-bar/)

为 HarmonyOS 上的 React Native 应用提供 Expo Navigation Bar 的原生实现，与官方同版本的 `expo-navigation-bar` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-navigation-bar expo-navigation-bar
```

## API 对照表

### Hooks

#### `useVisibility()`

返回 `NavigationBarVisibility | null`。初始值为 `null`，读取到导航栏状态后返回 `'visible'` 或 `'hidden'`；导航栏状态变化时更新。该 Hook 已废弃。

### Methods

#### `NavigationBar`

声明式设置导航栏按钮样式和显隐状态。组件属性如下：

| 属性 | 类型 | 默认值 | HarmonyOS 上的行为 |
| --- | --- | --- | --- |
| `style` | `NavigationBarStyle` | `'light'` | 设置导航栏按钮颜色。`'light'` 为浅色按钮，`'dark'` 为深色按钮；`'auto'` 在浅色界面使用深色按钮、在深色界面使用浅色按钮，`'inverted'` 则相反。 |
| `hidden` | `boolean` | `false` | 为 `true` 时隐藏底部导航栏和手势指示条，为 `false` 时显示。 |

#### `NavigationBar.setStyle(style)`

同步返回 `void`。运行时设置按钮颜色，接受 `NavigationBarStyle`。`'auto'` 在浅色界面使用深色按钮、在深色界面使用浅色按钮；`'inverted'` 使用相反颜色。

#### `setStyle(style)`

与 `NavigationBar.setStyle(style)` 行为相同，已废弃，请使用 `NavigationBar.setStyle(style)`。

#### `NavigationBar.setHidden(hidden)`

同步返回 `void`。`hidden` 为布尔值；设为 `true` 隐藏底部导航栏和手势指示条，设为 `false` 显示。

#### `setVisibilityAsync(visibility)`

已废弃，请使用 `NavigationBar.setHidden(hidden)`。返回 `Promise<void>`；`visibility` 接受 `'visible'` 或 `'hidden'`，分别显示或隐藏底部导航栏和手势指示条。

#### `getVisibilityAsync()`

已废弃。返回 `Promise<NavigationBarVisibility>`，结果为当前导航栏的 `'visible'` 或 `'hidden'` 状态。

### Event subscriptions

#### `addVisibilityListener(listener)`

返回 `EventSubscription`。导航栏可见状态变化时调用 `listener`，事件类型为 `NavigationBarVisibilityEvent`。此方法已废弃。

### Types

#### `NavigationBarProps`

`NavigationBar` 组件的属性：`style?: NavigationBarStyle` 和 `hidden?: boolean`。

#### `NavigationBarStyle`

可选值为 `'auto'`、`'inverted'`、`'light'` 和 `'dark'`。`'light'` 和 `'dark'` 指按钮颜色；`'auto'` 在浅色界面选择深色按钮、在深色界面选择浅色按钮，`'inverted'` 则相反。

#### `NavigationBarVisibility`

可选值为 `'visible'` 和 `'hidden'`。该类型已废弃。

#### `NavigationBarVisibilityEvent`

事件包含 `visibility: NavigationBarVisibility` 和 `rawVisibility: number`。HarmonyOS 上 `rawVisibility` 在导航栏显示时为 `0`，隐藏时为 `2`。

### Error codes

调用显隐查询或设置方法时，Promise 被拒绝可能包含以下错误码：

#### `ERR_NAVIGATION_BAR_DESTROYED`

操作完成前，导航栏功能所属的运行环境已关闭。

#### `ERR_NAVIGATION_BAR_WINDOW`

查询或设置时没有可用的应用窗口。

#### `ERR_NAVIGATION_BAR_VISIBILITY`

HarmonyOS 无法读取或更改导航栏显隐状态。

## 启动配置

使用配置插件设置应用启动时的按钮颜色和显示状态。`style` 接受 `'light'` 或 `'dark'`，`hidden` 接受布尔值；两项均可省略。

```json
{
  "expo": {
    "plugins": [
      ["@expo-harmony/expo-navigation-bar", { "style": "dark", "hidden": false }]
    ]
  }
}
```

HarmonyOS 上不支持以下配置项：

- `backgroundColor`：HarmonyOS 不提供设置导航栏背景色的接口。
- `borderColor`：HarmonyOS 不提供设置导航栏分隔线颜色的接口。
- `behavior`：HarmonyOS 不提供配置导航栏手势交互方式的接口。
- `position`：HarmonyOS 不提供调整导航栏相对于应用内容位置的接口。
- `enforceContrast`：HarmonyOS 不提供此项对比度配置。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
