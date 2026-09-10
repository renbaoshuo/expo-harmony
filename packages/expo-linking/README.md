# @expo-harmony/expo-linking

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-linking) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/linking/)

为 HarmonyOS 上的 React Native 应用提供 Expo Linking 的原生实现，与官方同版本的 `expo-linking` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-linking expo-linking@55.0.16 expo-modules-core@55.0.25
```

鸿蒙适配通过 Autolinking 自动接入，无需额外配置。最低支持 HarmonyOS 5.0.1（API 13），宿主的 `compatibleSdkVersion` 也需满足这一要求。

预构建时会自动把 `http`、`https`、`tel`、`sms` 和应用自身 scheme 加入可查询列表。要用 `canOpenURL` 查询其他 scheme，需要在 `app.json` 的 `expo.harmony.querySchemes` 中声明，没有声明的 scheme 查不到：

```json
{
  "expo": {
    "harmony": {
      "querySchemes": ["my-custom-scheme"]
    }
  }
}
```

电话和短信链接需要设备支持对应的系统能力。

## API 对照表

### Hooks

#### `useLinkingURL()`

返回 `string | null`，当前链接 URL。重新加载后立即拿到缓存值，收到新的深链时更新。同一个 Ability 内跨 React 运行时重载保留。

#### `useURL()`

返回 `string | null`，启动链接和之后的变化。官方已标记废弃，建议改用 `useLinkingURL()`。

### Methods

#### `Linking.canOpenURL(url)`

返回 `Promise<boolean>`，判断设备上是否有应用能处理该 URL。

`tel:` 只要设备具备通话能力就返回 `true`；`sms:` 需要设备同时具备短信能力和短信功能；其他 scheme 交给系统查询。自定义 scheme 要先按安装一节声明，未声明的查不到。

`url` 为空、缺少 scheme 或无法解析时抛出 `ERR_LINKING_INVALID_URL`，系统查询失败时抛出 `ERR_LINKING_CAN_OPEN_URL`。

#### `Linking.clearInitialURL()`

清除缓存的链接，无返回值。调用后 `getLinkingURL()` 返回 `null`，直到收到新的深链。不改变 `getInitialURL()` 的取值。官方标记为 Android 和 iOS 专属，HarmonyOS 上可用。

#### `Linking.collectManifestSchemes()`

返回 `string[]`，从应用配置读取 scheme。HarmonyOS 只读取顶层的 `expo.scheme`，Android 和 iOS 各自的 scheme 不读取。

#### `Linking.createURL(path, namedParameters?)`

返回 `string`，用应用配置的 scheme 拼出指向本应用的深链，默认双斜杠形式。`namedParameters` 见 `CreateURLOptions`。应用没有配置 `scheme` 时抛出错误。

#### `Linking.getInitialURL()`

返回 `Promise<string | null>`，Ability 启动时携带的链接。取值在 Ability 创建时确定，之后收到的新链接不会改变它；没有启动链接时返回 `null`。

#### `Linking.getLinkingURL()`

返回 `string | null`，最近一次收到的链接。没有收到过深链时返回 `null`，收到新深链后更新，同一个 Ability 内跨 React 运行时重载保留，调用 `clearInitialURL()` 后重新变为 `null`。

#### `Linking.hasConstantsManifest()`

返回 `boolean`，expo-constants 是否能读到应用配置。读取不到时 `createURL` 和 `resolveScheme` 无法确定 scheme。

#### `Linking.hasCustomScheme()`

返回 `boolean`。HarmonyOS 上的应用都使用自定义 scheme，该值恒为 `true`。

#### `Linking.openSettings()`

返回 `Promise<void>`，打开当前应用的系统设置页。启动失败时抛出 `ERR_LINKING_OPEN_SETTINGS`。

#### `Linking.openURL(url)`

返回 `Promise<true>`，把 URL 交给系统打开。

`tel:` 直接发起拨号，`sms:` 打开短信应用，设备缺少对应能力时抛出 `ERR_LINKING_UNAVAILABLE`；其他 scheme 交给系统处理，没有应用能处理时抛出 `ERR_LINKING_OPEN_URL`。

`url` 为空、缺少 scheme 或无法解析时抛出 `ERR_LINKING_INVALID_URL`。

#### `Linking.parse(url)`

返回 `ParsedURL`，拆出 scheme、hostname、path 和查询参数。解析失败时把整段字符串作为 `path` 返回。

#### `Linking.parseInitialURLAsync()`

返回 `Promise<ParsedURL>`，对启动链接做解析。没有启动链接时各字段为 `null`。

#### `Linking.resolveScheme(options)`

返回 `string`，解析应用使用的 scheme。配置了多个时取第一个并打印警告，一个都没有时抛出错误。

> **未实现的内容**
>
> - `Linking.sendIntent()`：Android 专属接口，HarmonyOS 上调用抛出 `UnavailabilityError`。

### Event Subscriptions

#### `Linking.addEventListener(type, handler)`

返回 `EmitterSubscription`，`type` 只能是 `'url'`。应用运行期间收到新的深链时触发回调，回调收到 `EventType`，`nativeEvent` 不提供。冷启动携带的链接不会触发，需要从 `getInitialURL()` 或 `getLinkingURL()` 获取。调用返回对象的 `remove()` 取消订阅。

### Types

#### `CreateURLOptions`

| 属性              | 类型           |
| ----------------- | -------------- |
| `scheme`          | `string?`      |
| `queryParams`     | `QueryParams?` |
| `isTripleSlashed` | `boolean?`     |

#### `EventType`

| 属性          | 类型            |
| ------------- | --------------- |
| `url`         | `string`        |
| `nativeEvent` | `MessageEvent?` |

`nativeEvent` 在 HarmonyOS 上不提供。

#### `ParsedURL`

| 属性          | 类型                  |
| ------------- | --------------------- |
| `scheme`      | `string \| null`      |
| `hostname`    | `string \| null`      |
| `path`        | `string \| null`      |
| `queryParams` | `QueryParams \| null` |

#### `QueryParams`

`Record<string, string | string[] | undefined>`，查询参数。

#### `URLListener`

`(event: EventType) => void`，`addEventListener` 的回调。

#### `NativeURLListener`

`(nativeEvent: MessageEvent) => void`，Web 上的原生事件回调，HarmonyOS 上不使用。

> **未实现的内容**
>
> - `SendIntentExtras`：只用于 `sendIntent`，该接口在 HarmonyOS 上不可用。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
