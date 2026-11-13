# @expo-harmony/expo-router

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-router) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/router/)

为 HarmonyOS 上的 React Native 应用提供 Expo Router 的原生实现，与 `expo-router` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-router expo-router@~57.0.29 expo-linking@~57.0.13 react-native-screens react-native-safe-area-context
```

## API 对照表

### Methods

#### `Link`

HarmonyOS 应用启动或运行期间收到的链接会交给 Expo Router 解析；可通过重定向规则或 `+native-intent` 将链接映射到应用路由。

#### `Stack`

HarmonyOS 上的堆栈路由用于按页面顺序呈现路由。

#### `Stack.Screen`

`gestureEnabled` 接受 `boolean`，默认值为 `true`，用于启用或禁用返回手势；`fullScreenGestureEnabled` 接受 `boolean`，默认值为 `false`，设为 `true` 后可从屏幕内开始返回手势。`gestureDirection` 接受 `'horizontal'` 或 `'vertical'`，默认值为 `'horizontal'`，分别以水平或垂直方向返回上一页。`presentation: 'formSheet'` 和 `'pageSheet'` 以 HarmonyOS 对话框形式展示页面。

- HarmonyOS 不支持配置表单弹窗的 detent 高度；`sheetAllowedDetents`、`sheetLargestUndimmedDetentIndex` 和 `sheetInitialDetentIndex` 不控制对话框高度或背景遮罩。
- `sheetGrabberVisible`、`sheetCornerRadius`、`sheetElevation`、`sheetExpandsWhenScrolledToEdge`、`sheetShouldOverflowTopInset` 和 `sheetResizeAnimationEnabled` 不会改变 HarmonyOS 对话框外观或滚动行为；系统没有对应的表单弹窗配置能力。

#### `ExperimentalStack`

HarmonyOS 上支持水平侧滑返回上一页。

#### `ExperimentalStack.Screen`

屏幕选项支持 `title`、`headerShown`、`headerTransparent` 和 `headerBackVisible`。

- 自定义标题栏、动画、模态呈现、表单弹窗和状态栏选项不生效；HarmonyOS 实验栈仅接受上述四项屏幕选项。

#### `NativeTabs`

- HarmonyOS 尚未提供原生标签栏组件，渲染 `NativeTabs` 会报错。

#### `SplitView`

HarmonyOS 上显示单列路由页面。

- `SplitView.Column` 和 `SplitView.Inspector` 不会创建分栏界面；HarmonyOS 尚未提供 Expo Router 分栏导航能力。

### Event subscriptions

#### `BackHandler.addEventListener('hardwareBackPress', listener)`

HarmonyOS 系统返回操作会触发 `listener`。回调返回 `true` 时消费该操作；返回 `false` 时导航栈返回上一页。方法返回的订阅对象提供 `remove()` 用于取消订阅。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
