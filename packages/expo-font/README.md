# @expo-harmony/expo-font

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-font) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/font/)

为 HarmonyOS 上的 React Native 应用提供 Expo Font 的原生实现，与官方 `expo-font` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-font expo-font@~57.0.4
```

## API 对照表

### Hooks

#### `useFonts(map)`

`map` 是字体系列名到 `FontSource` 的映射。返回 `[loaded, error]`：字体加载完成后 `loaded` 为 `true`；加载失败时 `error` 为错误，否则为 `null`。组件挂载后修改 `map` 不会触发重新加载。

### Methods

#### `Font.loadAsync(fontFamilyOrFontMap, source?)`

返回 `Promise<void>`，用于加载并注册字体。`fontFamilyOrFontMap` 可以是字体系列名到字体源的映射；也可以是单个字体系列名，此时用 `source` 提供字体源。

字体源可为 `require()` 返回的资源模块 ID、Expo Asset、应用内打包资源，或远程 `http://`、`https://` 与本地 `file://` 地址。`rawfile:` 地址中的特殊字符须使用 URL 转义。远程地址需要 `ohos.permission.INTERNET`。沙箱外的文件需要访问授权，授权提供方的 URI 会先复制到应用缓存。字体文件大小须在 1 字节到 32 MiB 之间。

Expo 会跳过已加载的系列。预打包字体在应用启动时注册。配置插件默认使用去掉扩展名的完整文件名作为系列名，例如 `Example_bold.ttf` 对应 `Example_bold`。需要保留原有短名时，可以使用配置插件的显式 `fontFamily`。HarmonyOS 每个系列使用一个字体文件，显式字体定义可使用 `weight: 400` 和 `style: 'normal'`。动态加载的字体可用于 `Text`，在 `TextInput` 等其他组件上的效果取决于 RNOH。

运行时字体在 API 23 及以上由字体集合接口异步加载并校验。API 18 至 22 先通过 Drawing 接口校验，再异步加载。API 13 至 17 同步校验和注册。

#### `Font.getLoadedFonts()`

返回按字母顺序排列的 `string[]`，包含预打包和运行时加载的字体系列名，不包含系统字体或通过其他接口注册的字体。

#### `Font.isLoaded(fontFamily)`

返回 `boolean`，表示 `fontFamily` 是否已加载。

#### `Font.isLoading(fontFamily)`

返回 `boolean`，表示 `fontFamily` 是否仍在加载。

#### `Font.renderToImageAsync(glyphs, options?)`

将 `glyphs` 渲染为 PNG 图片并写入应用缓存目录，返回 `Promise<RenderToImageResult>`。图片缩放系数取自应用所在显示器，字体与调用方运行时中的注册对应。字号和行高必须为有限正数。设置 `lineHeight` 后，额外行距会均分到文字上下。多行文本的换行由系统处理。

#### `Font.unloadAsync(fontFamilyOrFontMap, options?)`

- Expo 将此操作仅开放给 Web。HarmonyOS 上调用会失败。

#### `Font.unloadAllAsync()`

- Expo 将此操作仅开放给 Web。HarmonyOS 上调用会失败。

### Types

#### `FontSource`

`string | number | Asset | FontResource`。字符串表示字体地址，数字表示资源模块 ID，`Asset` 和 `FontResource` 表示字体资源。

#### `FontResource`

| 属性 | 类型 | HarmonyOS 行为 |
| --- | --- | --- |
| `uri?` | `string \| number` | 字体资源地址或模块 ID |

- `default`、`display`、`testString`：HarmonyOS 不使用这些字段控制字体加载。

#### `UnloadFontOptions`

卸载字体时使用的选项类型，为 `{ display?: FontDisplay }`。

- HarmonyOS 不支持注销已加载字体，因此此类型没有可用的操作。

#### `RenderToImageOptions`

| 属性 | 类型 | HarmonyOS 行为 |
| --- | --- | --- |
| `fontFamily` | `string` | 字体系列名；默认使用系统字体 |
| `size` | `number` | 字号，单位 dp；默认 `24` |
| `color` | `string` | 文字颜色；默认黑色 |
| `lineHeight` | `number` | 行高，单位 dp；不设置时使用字体默认行高 |

#### `RenderToImageResult`

| 属性 | 类型 | HarmonyOS 行为 |
| --- | --- | --- |
| `uri` | `string` | 生成图片的 `file://` 地址 |
| `width` | `number` | 图片宽度，单位 dp |
| `height` | `number` | 图片高度，单位 dp |
| `scale` | `number` | 缩放系数；dp 尺寸乘以该值即为像素尺寸 |

### Enums

#### `FontDisplay`

| 成员 | 值 |
| --- | --- |
| `AUTO` | `'auto'` |
| `BLOCK` | `'block'` |
| `FALLBACK` | `'fallback'` |
| `OPTIONAL` | `'optional'` |
| `SWAP` | `'swap'` |

- HarmonyOS 不提供字体显示策略；这些枚举值不改变字体加载行为。

### Error codes

#### `ERR_FONT_API`

`loadAsync` 的参数组合无效，例如同时提供字体映射和第二个参数。

#### `ERR_FONT_SOURCE`

字体源缺失、类型或地址无效，或字体文件不存在、为空。

#### `ERR_FONT_SOURCE_OUTSIDE_SANDBOX`

本地字体文件位于应用沙箱外，且没有相应的文件访问授权。

#### `ERR_FONT_SOURCE_TOO_LARGE`

字体文件超过 32 MiB。

#### `ERR_DOWNLOAD`

远程字体资源下载失败。

#### `ERR_FONT_FAMILY`

字体系列名为空。

#### `ERR_FONT_RENDER_OPTIONS`

字号、行高或颜色参数无效。

#### `ERR_INVALID_ARGUMENT_TYPE`

渲染参数的类型不符合要求。

#### `ERR_FONT_RENDER`

系统无法完成文字渲染。

#### `ERR_FONT_RENDER_TOO_LARGE`

文本或生成图片超出渲染上限。

#### `ERR_FONT_RENDER_EMPTY`

文本渲染结果为空。

#### `ERR_FONT_RENDER_WRITE`

无法将生成的图片写入应用缓存目录。

### Permissions

#### `ohos.permission.INTERNET`

加载远程 HTTP(S) 字体资源需要此权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
