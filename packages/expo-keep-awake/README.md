# @expo-harmony/expo-keep-awake

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-keep-awake) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/keep-awake/)

为 HarmonyOS 上的 React Native 应用提供 Expo KeepAwake 的原生实现，与官方 `expo-keep-awake` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-keep-awake expo-keep-awake@~57.0.2
```

## API 对照表

### Hooks

#### `useKeepAwake(tag?: string, options?: KeepAwakeOptions)`

返回 `void`。组件挂载期间按标签请求屏幕常亮，卸载时释放该标签。省略 `tag` 时使用该组件唯一的 ID。HarmonyOS 应用进入后台时暂停常亮请求，回到前台后恢复；窗口未就绪或常亮请求失败时，无法保证屏幕保持常亮。`options` 见 `KeepAwakeOptions`。

### Constants

#### `ExpoKeepAwakeTag`

值为 `'ExpoKeepAwakeDefaultTag'`，是省略标签的常亮方法使用的默认标签。

### Methods

#### `activateKeepAwake(tag?: string)`

已废弃，请改用 `activateKeepAwakeAsync()`。返回 `Promise<void>`，按标签请求屏幕常亮；省略 `tag` 时使用 `ExpoKeepAwakeTag`。

#### `activateKeepAwakeAsync(tag?: string)`

返回 `Promise<void>`，按标签请求屏幕常亮；省略 `tag` 时使用 `ExpoKeepAwakeTag`。同一标签重复激活不叠加，多个标签分别生效。应用在前台且至少有一个有效标签时，屏幕保持常亮；进入后台时暂停请求，回到前台后恢复。请求只作用于当前窗口，不会修改系统休眠设置。窗口未就绪或系统无法设置常亮时，Promise 会拒绝；系统仍可能自行关闭屏幕，异源虚拟屏也不保证常亮。

#### `deactivateKeepAwake(tag?: string)`

返回 `Promise<void>`，释放标签对应的常亮请求；省略 `tag` 时使用 `ExpoKeepAwakeTag`。释放未激活的标签不会报错。释放全部标签后，屏幕恢复系统默认的休眠行为。

#### `isAvailableAsync(): Promise<boolean>`

返回 `Promise<boolean>`。有界面的应用返回 `true`，无界面任务返回 `false`。`true` 不表示窗口已就绪；在无界面任务中激活或释放常亮会导致 Promise 拒绝。

### Event subscriptions

#### `addListener(tagOrListener: string | KeepAwakeListener, listener?: KeepAwakeListener)`

原方法返回 `EventSubscription`；HarmonyOS 不提供常亮状态变化事件，调用此方法会抛出不可用错误，不会返回订阅。

### Types

#### `KeepAwakeOptions`

`useKeepAwake` 的可选配置。

##### `suppressDeactivateWarnings?: boolean`

默认为 `false`。设为 `true` 时，Hook 卸载时会捕获释放常亮请求产生的 Promise 拒绝；此选项不影响激活和主动释放操作。

##### `listener?: KeepAwakeListener`

类型为 `KeepAwakeListener`。

- HarmonyOS 不提供常亮状态变化事件，因此不会调用此回调。

#### `KeepAwakeEvent`

事件对象包含 `state: KeepAwakeEventState`。

- HarmonyOS 不发出常亮状态变化事件，因此不会产生此事件对象。

#### `KeepAwakeListener`

类型为接收 `KeepAwakeEvent` 的回调函数。

- HarmonyOS 不发出常亮状态变化事件，因此不会调用此回调。

### Enums

#### `KeepAwakeEventState`

`RELEASE` 的值为 `'release'`。

- HarmonyOS 不发出常亮状态变化事件，因此不会传出此枚举值。

### Error codes

#### `ERR_KEEP_AWAKE_DESTROYED`

运行环境已销毁时，激活或释放常亮请求会以此错误码拒绝。

#### `ERR_KEEP_AWAKE_WINDOW`

窗口不可用、窗口状态发生变化，或系统无法设置或释放常亮请求时，Promise 会以此错误码拒绝。

### Permissions

#### 屏幕常亮

不需要声明或请求额外权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
