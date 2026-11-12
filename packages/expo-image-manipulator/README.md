# @expo-harmony/expo-image-manipulator

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-image-manipulator) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/imagemanipulator/)

为 HarmonyOS 上的 React Native 应用提供 Expo ImageManipulator 的原生实现，与官方同版本的 `expo-image-manipulator` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-image-manipulator expo-image-manipulator
```

## API 对照表

### Hooks

#### `useImageManipulator(source)`

返回 `ImageManipulatorContext`。`source` 支持的输入与 `ImageManipulator.manipulate()` 相同。来源变化或组件卸载时，Hook 会释放对应的 Context。

### Methods

#### `ImageManipulator.manipulate(source)`

返回新的 `ImageManipulatorContext`。`source` 可为本地文件路径、`file://` 地址、Base64 图片 data URI、HTTP(S) 地址或兼容的 `SharedRef<'image'>`，例如 `expo-image` 的 `ImageRef`。打包资源可使用 `asset://`、`rawfile://`、`resource://RAWFILE/` 或资源相对路径。

动画图片只处理第一帧。读取到 EXIF 方向信息时，图片会先按该方向调整。通过系统文件选择器取得的文件沿用系统授予应用的访问权限。传入的 `SharedRef` 可在创建 Context 后单独释放。

```tsx
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';

const context = ImageManipulator.manipulate(uri);
try {
  context.resize({ width: 320 }).rotate(90);
  const image = await context.renderAsync();
  try {
    const result = await image.saveAsync({ format: SaveFormat.PNG });
    console.log(result.uri, result.width, result.height);
  } finally {
    image.release();
  }
} finally {
  context.release();
}
```

#### `ImageManipulatorContext.crop({ originX, originY, width, height })`

返回当前 Context。裁剪区域须完整位于图片内，宽高至少为一个像素。坐标和尺寸会截断为整数；裁剪区域越界或尺寸不足一个像素时，渲染会报错。

#### `ImageManipulatorContext.extent(options)`

- HarmonyOS 不支持扩展图片画布或设置扩展区域的背景色。

#### `ImageManipulatorContext.flip(flipType)`

返回当前 Context。`flipType` 接受 `FlipType.Horizontal` 或 `FlipType.Vertical`。需要同时翻转两个方向时，分别调用两次。

#### `ImageManipulatorContext.renderAsync()`

返回 `Promise<ImageRef>`，等待当前已排入的变换完成，并生成图片快照。后续修改、重置或释放 Context 不会改变已返回的快照。`ImageRef.width` 和 `ImageRef.height` 为像素尺寸，可传给接受图片共享引用的模块。

若要按顺序依赖渲染结果，应先等待 `renderAsync()` 完成，再继续变换或调用 `reset()`。

#### `ImageManipulatorContext.reset()`

返回当前 Context，清除已排入的变换并从原图重新开始。重置或释放 Context 时尚未完成的渲染会失败。

#### `ImageManipulatorContext.resize({ width, height })`

返回当前 Context。`width` 和 `height` 至少提供一个正数；只提供一个时，另一边按原图比例计算。两者都提供时，缩放到指定尺寸。尺寸会截断为整数；结果尺寸不足一个像素或系统无法生成指定尺寸时，渲染会报错。

#### `ImageManipulatorContext.rotate(degrees)`

返回当前 Context。`degrees` 须为有限数值；正数顺时针旋转，负数逆时针旋转。

#### `ImageRef.saveAsync(options)`

返回 `Promise<ImageResult>`。默认保存为 JPEG，`compress` 默认 `1`，取值范围为 `0` 到 `1`。`format` 可设为 `SaveFormat.JPEG`、`SaveFormat.PNG` 或 `SaveFormat.WEBP`；PNG 为无损格式。可用编码格式取决于系统支持，不支持时会报错。

文件以新的 `file://` 地址保存到应用缓存目录，不会覆盖来源图片。系统可能清理缓存文件，需要长期保留时请将结果转存。请求 `base64: true` 时，结果中会包含不带 data URI 前缀的 Base64 字符串。保存开始后释放 `ImageRef` 不会取消该次保存。

#### `manipulateAsync(uri, actions, saveOptions)`

返回 `Promise<ImageResult>`。`actions` 按数组顺序执行，支持 `resize`、`rotate`、`flip` 和 `crop`；保存选项与 `ImageRef.saveAsync()` 相同。

### Types

#### `Action`

旧式变换操作的联合类型，由 `ActionResize`、`ActionRotate`、`ActionFlip`、`ActionCrop` 和 `ActionExtent` 组成。`manipulateAsync()` 按数组顺序执行其中受支持的操作。

#### `ActionCrop`

裁剪操作，包含 `crop: { originX, originY, width, height }`。坐标和尺寸规则见 `ImageManipulatorContext.crop()`。

#### `ActionExtent`

- HarmonyOS 不支持扩展图片画布，因此此操作不受支持。

#### `ActionFlip`

翻转操作，包含 `flip: FlipType`。

#### `ActionResize`

缩放操作，包含 `resize: { width?, height? }`。宽高规则见 `ImageManipulatorContext.resize()`。

#### `ActionRotate`

旋转操作，包含 `rotate: number`，角度规则见 `ImageManipulatorContext.rotate()`。

#### `ImageManipulatorContext`

由 `ImageManipulator.manipulate()` 或 `useImageManipulator()` 返回的图片变换上下文。支持 `crop()`、`flip()`、`renderAsync()`、`reset()`、`resize()` 和 `rotate()`。

#### `ImageRef`

由 `renderAsync()` 返回的图片引用，具有像素尺寸 `width`、`height` 和保存方法 `saveAsync()`。使用完成后可调用 `release()` 释放引用。

#### `ImageResult`

保存结果包含 `uri`、`width`、`height` 和 `base64`。`uri` 指向缓存文件；宽高以像素计；请求 Base64 时 `base64` 为不带前缀的字符串，否则为 `null`。图片按 SDR 色彩范围解码，输出不保留原图 EXIF、HDR 辅助图或完整色彩信息。

#### `SaveOptions`

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `base64` | `boolean` | `false` | 是否在 `ImageResult` 中返回 Base64 字符串。 |
| `compress` | `number` | `1` | 压缩质量，范围为 `0` 到 `1`。超出范围或不是有限数值时会报错。 |
| `format` | `SaveFormat` | `SaveFormat.JPEG` | 输出格式。可用格式及支持情况见 `ImageRef.saveAsync()`。 |

### Enums

#### `FlipType`

`Horizontal` 和 `Vertical` 分别表示水平和垂直翻转。

#### `SaveFormat`

`JPEG`、`PNG` 和 `WEBP` 分别表示 JPEG、PNG 和 WebP 输出格式。系统不支持所选编码格式时，保存会报错。

### Error codes

#### `ERR_IMAGE_INVALID_ARGUMENT`

变换角度不是有限数值、缩放尺寸无效，或 `compress` 不在 `0` 到 `1` 范围内时抛出。

#### `ERR_IMAGE_INVALID_CROP`

裁剪区域越界或宽高不足一个像素时抛出。

#### `ERR_IMAGE_LOADING_FAILED`

无法读取或解码输入图片时抛出。

#### `ERR_IMAGE_MANIPULATOR`

图片变换或生成渲染快照失败时抛出。

#### `ERR_IMAGE_MANIPULATOR_CANCELLED`

Context 被重置或释放时，尚未完成的渲染会以此错误结束。

#### `ERR_IMAGE_UNSUPPORTED_FORMAT`

系统不支持所请求的图片编码格式时抛出。

#### `ERR_IMAGE_WRITE_FAILED`

创建或写入输出文件失败时抛出。

### Permissions

#### `ohos.permission.INTERNET`

加载 HTTP(S) 图片需要网络权限；本包依赖的图片加载模块已声明该权限。单个 HTTP 响应体不能超过 100 MiB；每次处理远程地址都会重新请求图片。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
