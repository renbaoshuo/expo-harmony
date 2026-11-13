# @expo-harmony/expo__dom-webview

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo__dom-webview) | [官方文档](https://docs.expo.dev/guides/dom-components/)

为 HarmonyOS 上的 React Native 应用提供 Expo DOM WebView 的原生实现，与官方 `@expo/dom-webview` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 14（HarmonyOS 5.0.2）。

```bash
npm install @expo-harmony/expo__dom-webview @expo/dom-webview@~57.0.1
```

## 使用

直接渲染网页时，从 `@expo/dom-webview` 导入 `WebView` 组件。

```tsx
import { WebView } from '@expo/dom-webview';

<WebView
  source={{ uri: 'https://your-app.example/dom.html' }}
  style={{ height: 320 }}
  onMessage={({ nativeEvent }) => console.log(nativeEvent.data)}
/>;
```

使用带 `'use dom'` 指令的 DOM 组件时，在 `dom` 属性中设置 `useExpoDOMWebView: true`，让组件使用本包提供的 WebView。

网页调用应用中的 Expo 模块时，直接使用 `WebView` 需设置 `useExpoModulesBridge={true}`；DOM 组件还需在 `dom` 中设置 `unstable_useExpoModulesBridge: true`。只对可信网页开启此能力。普通属性、异步回调、`matchContents` 和 `onMessage` 不依赖此设置。

## API 对照表

### 组件

#### `WebView` / `DomWebView`

两个名称指向同一个 WebView 组件。

#### `DomWebViewProps`

组件属性的 TypeScript 类型。

#### `DomWebViewRef`

组件 `ref` 暴露的实例方法类型，包含 `scrollTo`、`injectJavaScript` 和 `reload`。

### 页面和脚本

#### `source`

接收 `{ uri: string }`，加载指定网页。支持网络地址、应用可访问的 `file://` 地址和 `resource://rawfile/` 应用资源。加载网络地址需要应用具有 `ohos.permission.INTERNET` 权限。`uri` 更新后加载新地址；其他属性更新不会把页面内导航或重定向后的地址改回初始地址。

#### `injectedJavaScriptBeforeContentLoaded`

类型：`string`，默认 `''`。

在每个新文档加载内容前执行。更新此属性会重新加载当前页面。

#### `injectedJavaScript`

类型：`string`，默认 `''`。

在每个新文档结束阶段执行。更新此属性会重新加载当前页面。

#### `injectedJavaScriptObject`

类型：`object`，默认 `{}`。

网页可调用 `window.ReactNativeWebView.injectedObjectJson()` 获取 JSON 字符串。更新此属性后，后续调用会返回新值，不需要重新加载页面。

### 外观、滚动和媒体

#### `style`

设置 WebView 样式。默认铺满外层容器，背景为白色；可通过 `backgroundColor` 更改背景色。

#### `containerStyle`

设置外层容器样式。容器默认 `flex: 1`，并裁剪超出边界的内容。

#### `showsHorizontalScrollIndicator` / `showsVerticalScrollIndicator`

类型：`boolean`，默认 `true`。

分别控制水平和垂直滚动条是否显示。

#### `nestedScrollEnabled`

类型：`boolean`，默认 `true`。

控制 WebView 与外层滚动容器的手势分配。`true` 时网页优先滚动，外层容器不接管网页滚动；`false` 时外层容器优先滚动，到达边界后网页再滚动。

#### `mediaPlaybackRequiresUserAction`

类型：`boolean`，默认 `true`。

控制媒体是否需要用户手势才能播放。设为 `false` 时是否能自动播放仍遵循系统网页组件的规则。

#### `webviewDebuggingEnabled`

类型：`boolean`，默认 `false`。

设为 `true` 后可通过 DevTools 调试网页；此属性仅在 Debug 构建中生效。

### Expo 模块桥接

#### `useExpoModulesBridge`

类型：`boolean`，默认 `false`。

设为 `true` 后，网页的顶层页面可调用应用中已安装的 Expo 模块，支持同步调用、Promise、事件监听和 SharedObject。只应对可信网页开启。同步调用等待超过 30 秒会超时；页面跳转会取消尚未开始的调用，已开始的调用可能继续执行。页面离开前应取消事件订阅并释放 SharedObject。更新此属性会重新加载当前页面。

### 事件

#### `onMessage`

网页调用 `window.ReactNativeWebView.postMessage(data)` 时触发，`data` 必须为字符串。回调参数为 `{ nativeEvent: { data, url, title } }`；三个字段均为字符串，`url` 和 `title` 对应发送消息时的页面。未设置此回调时，网页消息会被丢弃。

#### `onRenderProcessGone`

网页渲染进程退出时触发。回调参数为 `{ nativeEvent: { url, title, didCrash } }`；`url` 和 `title` 为进程退出前的页面信息，`didCrash` 表示进程是否因崩溃退出。

#### `onContentProcessDidTerminate`

网页渲染进程退出时触发。回调参数为 `{ nativeEvent: { url, title } }`，包含进程退出前的页面信息。渲染进程退出后可调用 `ref.reload()` 恢复页面。

### Ref 方法

#### `scrollTo({ x, y, animated })`

`x`、`y` 为可选数字，默认均为 `0`；`animated` 为可选布尔值，默认 `true`，动画时长为 250 ms。坐标单位为 vp，传入非有限数值会报 `ERR_INVALID_ARGUMENT`。方法无返回值；WebView 尚未就绪时会报 `ERR_WEBVIEW_NOT_READY`。

#### `injectJavaScript(script)`

在当前页面执行 `script` 字符串，不返回执行结果。WebView 尚未就绪或渲染进程已退出时会报 `ERR_WEBVIEW_NOT_READY`。

#### `reload()`

重新加载当前页面，无参数和返回值。加载失败时会报 `ERR_WEBVIEW_LOAD`。

### HarmonyOS 不支持的属性

#### 滚动与安全区

- `bounces`、`decelerationRate`、`scrollEnabled`、`pagingEnabled`、`automaticallyAdjustContentInsets`、`automaticallyAdjustsScrollIndicatorInsets`、`contentInset`、`contentInsetAdjustmentBehavior`、`directionalLockEnabled`：滚动和安全区布局由系统网页组件与宿主布局决定。

#### 键盘与媒体

- `hideKeyboardAccessoryView`、`allowsInlineMediaPlayback`、`allowsPictureInPictureMediaPlayback`、`allowsAirPlayForMediaPlayback`：这些属性不单独控制键盘附件栏或媒体播放方式，行为遵循系统网页组件规则。

#### 导航与文件访问

- `originWhitelist`、`allowsFullscreenVideo`：不限制网页导航，也不控制全屏播放；需要时由应用自行处理。
- `allowFileAccess`、`allowFileAccessFromFileURLs`：不控制本地文件访问范围；页面只能读取系统网页组件和应用权限允许访问的文件。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
