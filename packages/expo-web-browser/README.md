# @expo-harmony/expo-web-browser

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-web-browser) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/webbrowser/)

为 HarmonyOS 上的 React Native 应用提供 Expo WebBrowser 的原生实现，与官方同版本的 `expo-web-browser` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-web-browser expo-web-browser
```

## API 对照表

### Methods

#### `WebBrowser.openBrowserAsync(url, browserParams)`

`url` 须为带主机的 HTTP 或 HTTPS 地址；`browserParams` 为可选的 `WebBrowserOpenOptions`，默认 `{}`。在系统选择的外部浏览器中打开网页，返回 `Promise<WebBrowserResult>`。浏览器启动成功后返回 `{ type: 'opened' }`，不等待页面加载或浏览器关闭。浏览器启动中或认证会话进行中再次调用时返回 `{ type: 'locked' }`。调用时应用不在前台会抛出 `ERR_WEB_BROWSER_UNAVAILABLE`。

HarmonyOS 打开的是外部浏览器，浏览器由系统选择，页面外观由浏览器决定；传入的 `browserParams` 不改变浏览器选择或页面显示。

#### `WebBrowser.openAuthSessionAsync(url, redirectUrl, options)`

`url` 须为带主机的 HTTP 或 HTTPS 地址；`redirectUrl` 可省略、为 `null`，或传入绝对 URI；`options` 为可选的 `AuthSessionOpenOptions`，默认 `{}`。返回 `Promise<WebBrowserAuthSessionResult>`。收到以 `redirectUrl` 开头的回跳时返回 `{ type: 'success', url }`，其中 `url` 保留完整 query 和 fragment。

应用回到前台但没有匹配回跳时返回 `{ type: 'dismiss' }`；HarmonyOS 无法区分用户关闭浏览器与切回应用。没有提供 `redirectUrl` 时不会返回 `success`，等待可由 `dismissAuthSession()` 结束。已有认证会话或浏览器启动请求未完成时抛出 `ERR_WEB_BROWSER_ALREADY_OPEN`。启动浏览器失败时抛出 `ERR_WEB_AUTH_SESSION_FAILED_TO_START`；等待期间 UIAbility 被销毁时抛出 `ERR_WEB_BROWSER_DESTROYED`。

应用不在前台时调用会抛出 `ERR_WEB_BROWSER_UNAVAILABLE`。在分屏或仅支持 PC/2-in-1 的窗口模式下，应用可能不会收到前后台切换事件；此时可调用 `dismissAuthSession()` 结束等待。

#### `WebBrowser.dismissAuthSession()`

返回 `void`，立即以 `{ type: 'dismiss' }` 结束当前认证等待；没有进行中的认证会话时不做任何事。此方法只结束等待，不会关闭外部浏览器。

#### `WebBrowser.dismissBrowser()`

- 声明返回 `Promise<{ type: 'dismiss' }>`；HarmonyOS 无法关闭外部浏览器页面，调用会以 `ERR_WEB_BROWSER_DISMISS_UNAVAILABLE` 拒绝。

#### `WebBrowser.warmUpAsync(browserPackage?)`

- 接受可选的 `browserPackage`，返回 `Promise<WebBrowserWarmUpResult>`。HarmonyOS 不提供外部浏览器的预热或预加载控制；此方法不执行操作并返回空对象 `{}`。

#### `WebBrowser.coolDownAsync(browserPackage?)`

- 接受可选的 `browserPackage`，返回 `Promise<WebBrowserCoolDownResult>`。HarmonyOS 不提供外部浏览器的预热或预加载控制；此方法不执行操作并返回空对象 `{}`。

#### `WebBrowser.mayInitWithUrlAsync(url, browserPackage?)`

- 接受 `url` 和可选的 `browserPackage`，返回 `Promise<WebBrowserMayInitWithUrlResult>`。HarmonyOS 不提供外部浏览器的预热或预加载控制；此方法不执行操作并返回空对象 `{}`。

#### `WebBrowser.getCustomTabsSupportingBrowsersAsync()`

- 返回 `Promise<WebBrowserCustomTabsResults>`。HarmonyOS 不提供查询浏览器及其 Custom Tabs 服务的能力；`browserPackages` 和 `servicePackages` 为空数组，`defaultBrowserPackage` 和 `preferredBrowserPackage` 为 `undefined`。

#### `WebBrowser.maybeCompleteAuthSession(options?)`

- `options` 为可选的 `WebBrowserCompleteAuthSessionOptions`，默认 `{}`；返回 `WebBrowserCompleteAuthSessionResult`。HarmonyOS 没有认证弹窗的完成流程，调用返回 `{ type: 'failed', message: 'Not supported on this platform' }`，`options` 不生效。

### Types

#### `WebBrowserOpenOptions`

可传给 `openBrowserAsync()` 的可选配置对象。HarmonyOS 打开外部浏览器，以下字段均不改变浏览器选择、页面外观或窗口行为：`toolbarColor`、`browserPackage`、`enableBarCollapsing`、`secondaryToolbarColor`、`showTitle`、`enableDefaultShareMenuItem`、`showInRecents`、`createTask`、`useProxyActivity`、`controlsColor`、`dismissButtonStyle`、`readerMode`、`presentationStyle`、`windowName` 和 `windowFeatures`。

#### `AuthSessionOpenOptions`

继承 `WebBrowserOpenOptions`，并包含 `preferEphemeralSession?: boolean` 和 `preferUniversalLinks?: boolean`。HarmonyOS 不处理这些配置；Cookie 和登录状态由系统浏览器管理，应用无法要求使用隔离的临时会话。

#### `WebBrowserResult`

结果对象的 `type` 为 `WebBrowserResultType`。HarmonyOS 上 `openBrowserAsync()` 返回 `opened` 或 `locked`，认证等待被结束时返回 `dismiss`。

#### `WebBrowserRedirectResult`

认证成功时返回 `{ type: 'success', url: string }`；`url` 是触发结果的完整回跳 URI。

#### `WebBrowserAuthSessionResult`

`WebBrowserRedirectResult` 与 `WebBrowserResult` 的联合类型。

#### `WebBrowserCustomTabsResults`

包含 `browserPackages: string[]`、`servicePackages: string[]`、`defaultBrowserPackage?: string` 和 `preferredBrowserPackage?: string`。HarmonyOS 返回空数组，两个可选字段均为 `undefined`。

#### `WebBrowserWarmUpResult`

包含可选字段 `servicePackage?: string`；HarmonyOS 对应方法返回空对象 `{}`。

#### `WebBrowserCoolDownResult`

包含可选字段 `servicePackage?: string`；HarmonyOS 对应方法返回空对象 `{}`。

#### `WebBrowserMayInitWithUrlResult`

包含可选字段 `servicePackage?: string`；HarmonyOS 对应方法返回空对象 `{}`。

#### `WebBrowserCompleteAuthSessionOptions`

包含 `skipRedirectCheck?: boolean`；HarmonyOS 上不生效。

#### `WebBrowserCompleteAuthSessionResult`

字段为 `type: 'success' | 'failed'` 和 `message: string`；HarmonyOS 调用 `maybeCompleteAuthSession()` 时返回 `failed` 及不支持提示。

#### `WebBrowserWindowFeatures`

类型为 `Record<string, number | boolean | string>`。HarmonyOS 没有对应的窗口配置，`windowFeatures` 不生效。

### Enums

#### `WebBrowserResultType`

HarmonyOS 上会返回 `OPENED`（`'opened'`）、`LOCKED`（`'locked'`）和 `DISMISS`（`'dismiss'`）。

`CANCEL` 不会作为结果返回；HarmonyOS 无法区分用户关闭浏览器与切回应用。

#### `WebBrowserPresentationStyle`

- HarmonyOS 没有应用内浏览器窗口；`AUTOMATIC`、`FULL_SCREEN`、`PAGE_SHEET`、`FORM_SHEET`、`CURRENT_CONTEXT`、`OVER_FULL_SCREEN`、`OVER_CURRENT_CONTEXT` 和 `POPOVER` 均不改变展示方式。

### Error codes

#### `ERR_WEB_BROWSER_INVALID_URL`

浏览器地址不是带主机的 HTTP 或 HTTPS 地址，或回跳地址不是有效的绝对 URI。错误消息不包含原始 URL。

#### `ERR_WEB_BROWSER_OPEN_BROWSER`

`openBrowserAsync()` 启动浏览器失败。错误消息不包含原始 URL。

#### `ERR_WEB_AUTH_SESSION_FAILED_TO_START`

`openAuthSessionAsync()` 启动浏览器失败。认证会话会结束，可再次发起认证；错误消息不包含原始 URL。

#### `ERR_WEB_BROWSER_UNAVAILABLE`

调用时应用不在前台。

#### `ERR_WEB_BROWSER_DESTROYED`

发起调用的 UIAbility 已销毁，或认证等待期间该 UIAbility 被销毁。

#### `ERR_WEB_BROWSER_ALREADY_OPEN`

已有认证会话进行中，或浏览器启动请求尚未完成。

#### `ERR_WEB_BROWSER_DISMISS_UNAVAILABLE`

调用 `dismissBrowser()`；HarmonyOS 无法关闭外部浏览器页面。

### Permissions

打开浏览器和接收认证回跳不需要额外权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
