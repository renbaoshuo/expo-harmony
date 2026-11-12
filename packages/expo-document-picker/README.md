# @expo-harmony/expo-document-picker

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-document-picker) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/document-picker/)

为 HarmonyOS 上的 React Native 应用提供 Expo DocumentPicker 的原生实现，与官方同版本的 `expo-document-picker` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-document-picker expo-document-picker
```

## API 对照表

### Methods

#### `DocumentPicker.getDocumentAsync(options?)`

打开系统文件选择器，返回 `Promise<DocumentPickerResult>`。用户选中文件时，`canceled` 为 `false`，`assets` 是所选文件数组；用户取消时，`canceled` 为 `true`，`assets` 为 `null`。

省略 `options` 时，`type` 默认为 `'*/*'`、`multiple` 默认为 `false`、`copyToCacheDirectory` 默认为 `true`。同一 UIAbility 的上一次选择尚未结束时再次调用，会抛出 `ERR_PICKING_IN_PROGRESS`。没有可用 UIAbility 时抛出 `ERR_DOCUMENT_PICKER_UNAVAILABLE`。

```ts
import * as DocumentPicker from 'expo-document-picker';

const result = await DocumentPicker.getDocumentAsync({
  type: ['application/pdf', 'image/*'],
  multiple: true,
});
```

### Types

#### `DocumentPickerOptions`

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `type` | `string \| string[]` | `'*/*'` | 允许选择的 MIME 类型；支持 `image/*` 等通配符。 |
| `multiple` | `boolean` | `false` | 是否允许一次选择多个文件。为 `false` 时最多选择一个；为 `true` 时选择数量由系统决定。 |
| `copyToCacheDirectory` | `boolean` | `true` | 是否将所选文件复制到应用缓存目录。为 `true` 时 `uri` 指向副本；为 `false` 时 `uri` 是系统返回的原始地址，其可读性和有效期由系统决定。 |

- `base64`：HarmonyOS 不返回 Base64 内容，`uri` 仍为文件地址。

系统按文件后缀过滤选择结果，并根据 HarmonyOS SDK 中注册的 MIME 类型确定后缀；`*/*` 不限制后缀。系统注册表中找不到对应后缀时抛出 `ERR_DOCUMENT_PICKER_UNSUPPORTED_MIME_TYPE`。`type` 为空数组时，在打开选择器前抛出 `ERR_DOCUMENT_PICKER_OPTIONS_EMPTY_LIST`。可用后缀随系统注册表变化。

#### `DocumentPickerAsset`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `uri` | `string` | 文件地址；默认指向缓存目录中的副本。 |
| `name` | `string` | 文件名。 |
| `size` | `number` | 文件大小，单位为字节；无法读取时省略。 |
| `mimeType` | `string` | 根据文件名后缀确定的 MIME 类型；无法确定时省略。 |
| `lastModified` | `number` | 最后修改时间，Unix 纪元以来的毫秒数；无法读取时使用当前时间。 |

- `file` 和 `base64`：HarmonyOS 不返回这两个字段。

HarmonyOS SDK API 15 及以上版本可提供更高精度的最后修改时间；较早版本使用秒精度的系统时间。Unix 纪元前的修改时间以负数毫秒表示。

#### `DocumentPickerResult`

`DocumentPickerSuccessResult | DocumentPickerCanceledResult`。

#### `DocumentPickerSuccessResult`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `canceled` | `false` | 用户没有取消选择。 |
| `assets` | `DocumentPickerAsset[]` | 所选文件。 |

- `output`：HarmonyOS 不返回此字段。

#### `DocumentPickerCanceledResult`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `canceled` | `true` | 用户取消了选择。 |
| `assets` | `null` | 取消时没有文件列表。 |

- `output`：HarmonyOS 不返回此字段。

### Error codes

#### `ERR_DOCUMENT_PICKER_OPTIONS_EMPTY_LIST`

`type` 为空数组时抛出。

#### `ERR_DOCUMENT_PICKER_UNSUPPORTED_MIME_TYPE`

HarmonyOS SDK 的 MIME 类型注册表中没有对应文件后缀时抛出。

#### `ERR_PICKING_IN_PROGRESS`

同一 UIAbility 的上一次文件选择尚未结束时再次调用 `getDocumentAsync()`，会抛出此错误。

#### `ERR_DOCUMENT_PICKER_UNAVAILABLE`

没有可用 UIAbility、无法打开系统文件选择器时抛出。

#### `ERR_FAILED_TO_READ_DOCUMENT`

所选对象不是普通文件、文件名不合法或文件信息读取失败时抛出。

#### `ERR_DOCUMENT_PICKER_FAILED`

系统文件选择器调用失败或选择结果准备失败时抛出。

#### `ERR_DOCUMENT_PICKER_DESTROYED`

模块运行环境已销毁时抛出。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
