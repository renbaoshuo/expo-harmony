# @expo-harmony/expo-linking

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-linking) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/linking/)

为 HarmonyOS 上的 React Native 应用提供 Expo Linking 原生实现，与 `expo-linking` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-linking expo-linking
```

## API 对照表

### Hooks

#### `Linking.useLinkingURL()`

返回 `string | null`，当前链接；收到新深链后更新。应用重新加载后会立即返回最近一次收到的链接，没有深链时返回 `null`。

#### `Linking.useURL()`

返回 `string | null`，启动时收到的链接及之后收到的新链接。此 Hook 已弃用，建议使用 `useLinkingURL()`。

### Methods

#### `Linking.clearInitialURL()`

清除当前链接缓存，不返回值。调用后 `getLinkingURL()` 返回 `null`，直到收到新的深链；`getInitialURL()` 的结果不变。

#### `Linking.canOpenURL(url)`

参数 `url` 为待查询的 URL；返回 `Promise<boolean>`，表示 HarmonyOS 是否能找到处理该 URL 的应用。`tel:` 检查拨号能力，`sms:` 检查短信能力和短信功能；这些检查不代表设备插有可用的 SIM 卡。其他 scheme 由系统查询。默认可查询 `http`、`https`、`tel`、`sms` 和应用配置的 scheme；查询其他自定义 scheme 前，需在 `app.json` 的 `expo.harmony.querySchemes` 中声明。系统无法查询时抛出 `ERR_LINKING_CAN_OPEN_URL`。

#### `Linking.collectManifestSchemes()`

返回 `string[]`，读取应用配置顶层 `expo.scheme` 中的 scheme；配置为数组时返回其中的字符串。

#### `Linking.createURL(path, namedParameters?)`

`path` 为要追加到链接的路径；可选的 `namedParameters` 可设置 `scheme`、`queryParams` 和 `isTripleSlashed`。返回 `string`，用应用配置的 scheme 生成指向本应用的深链，默认使用双斜杠形式。HarmonyOS 从顶层 `expo.scheme` 读取默认 scheme。没有可用 scheme 时抛出错误。

#### `Linking.getInitialURL()`

返回 `Promise<string | null>`，应用启动时收到的链接；之后收到的新链接不会改变此值。没有启动链接时返回 `null`。

#### `Linking.getLinkingURL()`

返回 `string | null`，最近一次收到的链接。没有收到过深链或调用 `clearInitialURL()` 后返回 `null`。

#### `Linking.hasConstantsManifest()`

返回 `boolean`，表示是否能从应用配置读取到 Constants manifest。配置为空或不可用时返回 `false`。

#### `Linking.hasCustomScheme()`

返回 `boolean`，HarmonyOS 应用使用自定义 scheme，因此返回 `true`。

#### `Linking.openSettings()`

返回 `Promise<void>`，打开当前应用的 HarmonyOS 系统设置页。启动失败时抛出 `ERR_LINKING_OPEN_SETTINGS`。

#### `Linking.openURL(url)`

参数 `url` 为要打开的 URL；返回 `Promise<true>`。`tel:` 交给系统拨号能力处理，`sms:` 打开系统短信编辑界面；其他 scheme 交给系统打开。`sms:` 支持 `sms:号码1,号码2?body=正文` 和 `sms:号码&body=正文`，多个号码以逗号分隔，国际号码使用 `+` 前缀；号码和正文中的特殊字符需进行 URL 编码。设备缺少拨号或短信能力时抛出 `ERR_LINKING_UNAVAILABLE`；系统无法打开 URL 时抛出 `ERR_LINKING_OPEN_URL`。Promise 成功表示系统已接受打开请求，电话或短信的后续操作由用户在系统应用中完成。

#### `Linking.parse(url)`

参数 `url` 为待解析的链接；返回 `ParsedURL`，包含 scheme、hostname、path 和 queryParams。解析失败时将完整输入作为 `path` 返回。

#### `Linking.parseInitialURLAsync()`

返回 `Promise<ParsedURL>`，解析应用启动时收到的链接。没有启动链接时，所有字段均为 `null`。

#### `Linking.resolveScheme(options)`

`options` 可包含 `scheme?: string` 和 `isSilent?: boolean`。返回 `string`；指定 `scheme` 时使用该值，省略时使用应用配置顶层 `expo.scheme` 的第一个值。配置了多个 scheme 时使用第一个并打印警告；没有可用 scheme 时抛出错误。`isSilent` 为 `true` 时不打印多 scheme 警告。

#### `Linking.sendIntent(action, extras?)`

- HarmonyOS 没有与该 Android Intent 操作对应的系统接口，调用时抛出 `UnavailabilityError`。

### Event subscriptions

#### `Linking.addEventListener(type, handler)`

`type` 只能为 `'url'`；`handler` 接收 `{ url: string }`。收到新的深链时触发，不重放启动链接；可通过 `getInitialURL()` 或 `getLinkingURL()` 读取启动链接。返回的订阅对象提供 `remove()` 用于取消订阅。HarmonyOS 不提供 `nativeEvent`。

### Types

#### `CreateURLOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `scheme` | `string` | 可选；生成链接时使用的 scheme。 |
| `queryParams` | `QueryParams` | 可选；转换为查询字符串的参数。 |
| `isTripleSlashed` | `boolean` | 可选；是否生成 `scheme:///path`，默认生成 `scheme://path`。 |

#### `EventType`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `url` | `string` | 收到的深链。 |
| `nativeEvent` | `MessageEvent?` | HarmonyOS 不提供此字段。 |

#### `NativeURLListener`

- HarmonyOS 的链接事件不提供 `MessageEvent`，不支持此类型对应的回调。

#### `ParsedURL`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `scheme` | `string \| null` | 链接的 scheme。 |
| `hostname` | `string \| null` | 链接的主机名。 |
| `path` | `string \| null` | 指向应用的路径。 |
| `queryParams` | `QueryParams \| null` | 查询参数。 |

#### `QueryParams`

`Record<string, string | string[] | undefined>`，查询参数名到字符串、字符串数组或 `undefined` 的映射。

#### `SendIntentExtras`

- HarmonyOS 不支持 `sendIntent()`，因此不提供此类型对应的 Intent extras。

#### `URLListener`

`(event: EventType) => void`，`addEventListener('url', handler)` 的回调类型。

### Error codes

#### `ERR_LINKING_INVALID_URL`

`openURL()` 或 `canOpenURL()` 收到空 URL 或缺少 scheme 的 URL 时抛出。

#### `ERR_LINKING_ABILITY_NOT_INITIALIZED`

应用启动时的链接状态不可用时抛出。

#### `ERR_LINKING_UNAVAILABLE`

设备缺少拨号或短信能力，或当前无法打开系统界面时抛出。

#### `ERR_LINKING_CAN_OPEN_URL`

HarmonyOS 无法查询某个 URL 是否可打开时抛出。查询自定义 scheme 前，需在 `app.json` 的 `expo.harmony.querySchemes` 中声明；默认可查询 `http`、`https`、`tel`、`sms` 和应用配置的 scheme。

#### `ERR_LINKING_OPEN_URL`

系统无法打开 URL 或启动短信编辑界面时抛出。

#### `ERR_LINKING_OPEN_SETTINGS`

无法打开当前应用的 HarmonyOS 系统设置页时抛出。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
