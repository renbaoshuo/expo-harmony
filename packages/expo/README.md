# @expo-harmony/expo

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/expo/)

为 HarmonyOS 上的 React Native 应用提供 Expo 主包的原生实现，与官方同版本的 `expo` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 20（HarmonyOS 6.0.0）。

```bash
npm install @expo-harmony/expo expo
```

## API 对照表

### Hooks

#### `useEvent(eventEmitter, eventName, initialValue?)`

接收事件发射器和事件名，`initialValue` 可省略，默认值为 `null`。返回最近一次事件参数；事件首次触发前返回初始值。可监听 Expo 模块、共享对象或 `EventEmitter` 发出的事件。

#### `useEventListener(eventEmitter, eventName, listener)`

接收事件发射器、事件名和回调；无返回值。事件触发时调用回调，组件卸载后移除监听。

### Methods

#### `registerRootComponent(component)`

`component` 为 React 组件；返回 `void`。将组件注册为 HarmonyOS 应用的根组件。

#### `reloadAppAsync(reason?)`

`reason` 为可选字符串，默认值为 `"Reloaded from JS call"`；返回 `Promise<void>`。重新加载当前应用并继续使用当前 JavaScript bundle。

#### `isRunningInExpoGo()`

无参数，返回 `boolean`。HarmonyOS 应用不运行在 Expo Go 中，因此返回 `false`。

#### `fetch(input, init?)`（`expo/fetch`）

`input: string | URL | FetchRequestLike`；`init?: FetchRequestInit`，可设置请求体、凭证、请求头、方法、`AbortSignal` 和重定向模式。返回 `Promise<FetchResponse>`，响应体支持流式读取。

HarmonyOS 支持 `http`、`https` 和 `file` 地址；其他协议会使请求失败。凭证默认按 `include` 处理，`same-origin` 也按 `include` 处理；响应 Cookie 会保存供后续请求使用。重定向默认跟随，最多 20 次；跨源重定向会移除 `Authorization`、`Cookie` 等敏感请求头。网络响应支持 gzip 或未压缩内容；其他压缩格式会使请求失败。`file://` 只支持 `GET` 和 `HEAD`，不能携带请求体；文件不存在时返回 404，且只能读取应用沙箱内或已获授权的路径。

- `integrity`、`keepalive`、`mode`、`referrer` 和 `window` 暂不支持；Expo SDK 57 的 `FetchRequestInit` 不实现这些选项。

### Types

#### `FetchRequestInit`

`expo/fetch` 的请求选项类型，包含请求体、凭证、请求头、方法、`AbortSignal` 和重定向模式。

#### `FetchRequestLike`

`expo/fetch` 接受的 Request-like 对象类型，包含 `url`、`body`、`method` 和 `headers`；凭证、`AbortSignal` 和重定向模式为可选字段。

### Permissions

#### `ohos.permission.INTERNET`

本包声明的普通权限，供 `expo/fetch` 发起网络请求使用。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
