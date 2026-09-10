# @expo-harmony/expo-font

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-font) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/font/)

为 HarmonyOS 上的 React Native 应用提供 Expo Font 的原生实现，与官方同版本的 `expo-font` 配套使用。支持运行时加载和注册自定义字体、将文字渲染为图片，以及通过配置插件预先打包字体资源。

## 安装

```bash
npm install @expo-harmony/expo-font expo-font@55.0.8
```

鸿蒙适配会通过 Autolinking 自动接入，无需额外配置。最低支持 HarmonyOS 5.0.1（API 13），宿主的 `compatibleSdkVersion` 也需满足此要求。

字体可以在运行时用 `Font.loadAsync` 加载，也可以在预构建时打包进应用。运行时加载不用改 `app.json`。

预构建打包要在 `app.json` 的 `plugins` 中注册 `@expo-harmony/expo-font`，并启用 `@expo-harmony/prebuild-config`：

```json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-font",
        {
          "fonts": ["./assets/fonts/Inter-Regular.ttf"]
        }
      ],
      "@expo-harmony/prebuild-config"
    ]
  }
}
```

打包的字体在 JavaScript 运行前完成注册，`Font.getLoadedFonts()` 会列出它们。

`fonts` 参数接受字体文件路径、目录，或 `{ fontFamily, fontDefinitions: [{ path }] }`。传入目录时，目录下的 `.ttf`、`.otf` 文件按文件名推导系列名，`_bold`、`_italic`、`_bold_italic` 后缀会去掉。同一系列只能对应一个字体文件，不支持 `weight`、`style`，权重和斜体变体要用不同的系列名区分，否则预构建报错。

字体路径也可以写在官方 `expo-font` 插件的 `fonts` 参数里。注册 `@expo-harmony/expo-font` 后，插件会读取这些路径并打包到 HarmonyOS，无需重复配置：

```json
{
  "expo": {
    "plugins": [
      ["expo-font", { "fonts": ["./assets/fonts/Inter-Regular.ttf"] }],
      "@expo-harmony/expo-font",
      "@expo-harmony/prebuild-config"
    ]
  }
}
```

## API 对照表

### Hooks

#### `useFonts(map)`

返回 `[boolean, Error | null]`。字体加载完成后第一项为 `true`，失败时第二项为错误。`map` 是单个系列名，或名称到字体资源的映射。运行时改变传入的映射不会重新加载。

### Methods

#### `Font.loadAsync(fontFamilyOrFontMap, source?)`

返回 `Promise<void>`，注册字体系列。第一个参数是名称到字体资源的映射，也可以是单个名称，此时由第二个参数给出资源。

字体源可以是 `require('...')` 返回的资源模块 ID、远程 `http`、`https` 地址，或应用沙箱内的本地 `file://` 地址。打包资源以 `asset://` 地址传入时按应用内资源处理。远程地址会先下载到缓存目录再注册。本地 `file://` 地址须指向应用沙箱内的文件，沙箱之外的路径会被拒绝。字体文件须在 1 字节到 32 MB 之间。

系列已注册时再次调用直接返回，不比较资源。配置插件打包的系列在启动时已经注册，运行时用同名加载会被跳过。

加载方式随 HarmonyOS SDK 版本变化：

- API 23 及以上异步加载，并校验字体文件，文件缺失、损坏、为空等情况会给出具体错误。
- API 18 到 22 异步加载，不校验字体文件内容。
- API 13 到 17 没有异步加载接口，注册在调用时同步完成。

#### `Font.getLoadedFonts()`

返回 `string[]`，已注册的字体系列名称，按字母顺序排列。包含配置插件在启动时打包的字体和运行时加载的字体。

#### `Font.isLoaded(fontFamily)`

返回 `boolean`，字体系列是否已完成加载。

#### `Font.isLoading(fontFamily)`

返回 `boolean`，字体系列是否正在加载。一次 `loadAsync` 尚未完成时返回 `true`。

#### `Font.renderToImageAsync(glyphs, options?)`

返回 `Promise<RenderToImageResult>`，把文本渲染成 PNG 图片并写入应用缓存目录，`uri` 指向该文件。官方标记为 Android 和 iOS 专属接口，在 HarmonyOS 上可用。

文本不超过 10 万个 UTF-16 码元，图片单边不超过 8192 像素。`size` 或 `lineHeight` 不是正数、文本渲染结果为空时拒绝。

> **未实现的内容**
>
> - `Font.unloadAsync()`、`Font.unloadAllAsync()`：注册后的字体在应用运行期间保持可用，模块不提供注销接口，调用抛出 `UnavailabilityError`。

### Interfaces

#### `RenderToImageOptions`

| 属性         | 类型     | 说明                                    |
| ------------ | -------- | --------------------------------------- |
| `fontFamily` | `string` | 字体系列，默认系统字体                  |
| `size`       | `number` | 字号，单位 dp，默认 24                  |
| `color`      | `string` | 文字颜色，默认黑色                      |
| `lineHeight` | `number` | 行高，单位 dp，不设置时使用字体默认行高 |

#### `RenderToImageResult`

| 属性     | 类型     | 说明                                |
| -------- | -------- | ----------------------------------- |
| `uri`    | `string` | 图片的 `file://` 地址               |
| `width`  | `number` | 图片宽度，单位 dp                   |
| `height` | `number` | 图片高度，单位 dp                   |
| `scale`  | `number` | 缩放系数，dp 尺寸乘以它得到像素尺寸 |

### Types

#### `FontSource`

`string | number | Asset | FontResource`。字符串按字体地址解析，数字按 `require` 的资源模块 ID 解析。

#### `FontResource`

| 属性         | 类型               | 说明                                              |
| ------------ | ------------------ | ------------------------------------------------- |
| `uri`        | `string \| number` | 字体资源                                          |
| `default`    | `string`           | 仅在 Web 上作为地址的备用来源，HarmonyOS 上不生效 |
| `display`    | `FontDisplay`      | 官方标记为 Web 专属，HarmonyOS 上不生效           |
| `testString` | `string`           | 官方标记为 Web 专属，HarmonyOS 上不生效           |

> **未实现的内容**
>
> - `UnloadFontOptions`：配合 `unloadAsync()` 使用，HarmonyOS 上没有对应的注销接口。

### Enums

#### `FontDisplay`

| 成员       | 值           |
| ---------- | ------------ |
| `AUTO`     | `'auto'`     |
| `BLOCK`    | `'block'`    |
| `FALLBACK` | `'fallback'` |
| `OPTIONAL` | `'optional'` |
| `SWAP`     | `'swap'`     |

控制 Web 上的 `font-display` 策略。HarmonyOS 上设置后没有效果，字体加载策略由系统决定。

### Error codes

| 错误码                      | 说明                                               |
| --------------------------- | -------------------------------------------------- |
| `ERR_FONT_API`              | `loadAsync` 参数组合不合法                         |
| `ERR_FONT_SOURCE`           | 字体资源类型不正确，或地址无效、文件不存在、为空   |
| `ERR_FONT_SOURCE_TOO_LARGE` | 字体文件超过 32 MB                                 |
| `ERR_DOWNLOAD`              | 远程字体资源下载失败                               |
| `ERR_FONT_FAMILY`           | 字体系列名称不合法                                 |
| `ERR_FONT_RENDER_OPTIONS`   | `renderToImageAsync` 参数取值不合法                |
| `ERR_FONT_RENDER_TOO_LARGE` | 文本或图片超出渲染上限                             |
| `ERR_FONT_RENDER_EMPTY`     | 文本渲染结果为空                                   |

> **未实现的内容**
>
> - `ERR_WEB_ENVIRONMENT`、`ERR_UNLOAD`：分别只在 Web 和字体注销场景下出现，HarmonyOS 上没有对应的功能。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
