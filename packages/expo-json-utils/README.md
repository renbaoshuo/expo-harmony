# @expo-harmony/expo-json-utils

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-json-utils)

为 HarmonyOS 上的 React Native 应用提供 Expo JSON Utils 的原生实现，与官方 `expo-json-utils` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-json-utils
```

## API 对照表

### Methods

#### `JSONObjectUtils.hasValue(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `boolean`。只检查对象自身的字段；字段值为 `null` 或 `undefined` 时仍返回 `true`。

#### `JSONObjectUtils.require(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回对应的 `JSONValue`。字段不存在时抛出 `JSONUtilsError`；字段值为 `undefined` 时返回 `undefined`。

#### `JSONObjectUtils.getNullable(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回对应的 `JSONValue`。字段不存在时返回 `null`；字段存在且值为 `undefined` 时返回 `undefined`。

#### `JSONObjectUtils.requireString(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `string`。字符串原样返回；`null` 转为 `"null"`；布尔值和有限数值转为文本；数组和普通对象序列化为 JSON 文本。其他值或无法序列化的数组、对象会抛出 `JSONUtilsError`。

#### `JSONObjectUtils.getNullableString(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `string | null`。字段不存在时返回 `null`；字段存在时按 `requireString()` 的规则转换。

#### `JSONObjectUtils.requireNumber(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `number`。数值原样返回，包括 `NaN` 和正负无穷。字符串去除首尾空白后，可包含十进制数、指数、`NaN` 或 `Infinity`，并可带正负号；十进制数字末尾也可带 `f`、`F`、`d` 或 `D`。其他字符串和值会抛出 `JSONUtilsError`。数值超过 JavaScript 安全整数范围时可能丢失精度。

#### `JSONObjectUtils.getNullableNumber(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `number | null`。字段不存在时返回 `null`；字段存在时按 `requireNumber()` 的规则转换。

#### `JSONObjectUtils.requireBoolean(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `boolean`。布尔值原样返回；忽略大小写的字符串 `"true"` 和 `"false"` 分别转为 `true` 和 `false`。其他字符串和值会抛出 `JSONUtilsError`。

#### `JSONObjectUtils.getNullableBoolean(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `boolean | null`。字段不存在时返回 `null`；字段存在时按 `requireBoolean()` 的规则转换。

#### `JSONObjectUtils.requireArray(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `JSONValue[]`。字段值不是数组时抛出 `JSONUtilsError`。

#### `JSONObjectUtils.getNullableArray(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `JSONValue[] | null`。字段不存在时返回 `null`；字段存在但不是数组时抛出 `JSONUtilsError`。

#### `JSONObjectUtils.requireObject(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `JSONObject`。字段值不是普通对象时抛出 `JSONUtilsError`；数组和 `null` 不视为普通对象。

#### `JSONObjectUtils.getNullableObject(json, key)`

接收 JSON 对象 `json` 和字段名 `key`，返回 `JSONObject | null`。字段不存在时返回 `null`；字段存在但不是普通对象时抛出 `JSONUtilsError`。

### Types

#### `JSONValue`

`Object | null | undefined`，表示字段可读取的 JSON 值；字段值为 `undefined` 时仍视为已设置。

#### `JSONObject`

`Record<string, JSONValue>`，以字符串字段名映射到 JSON 值的对象。

#### `JSONUtilsError`

继承自 `Error`，读取失败时抛出，`name` 为 `'JSONUtilsError'`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors)

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
