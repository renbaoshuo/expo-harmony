# @expo-harmony/expo-image

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-image) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/image/)

为 HarmonyOS 上的 React Native 应用提供 Expo Image 的原生实现，与官方 `expo-image` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-image expo-image@~57.0.5
```

## API 对照表

### Components

#### `Image`

显示图片的组件，支持图片占位、内容适配、过渡、缓存和动画播放。

##### `source`

类型：`ImageSource | string | number | ImageRef | ImageSource[] | string[] | null`

图片来源支持 HTTP(S)、`data:`（base64 或百分号转义）、应用沙箱绝对路径、`file://`、`asset://`、`resource://RAWFILE/`、`rawfile://`、`rawfile:` 和无协议的打包资源地址。带 provider authority 的文件地址需要应用已获得读取授权。`asset://path` 对应 `rawfile/assets/path`；`resource://RAWFILE/path`、`rawfile://path`、`rawfile:path` 和相对资源名对应 `rawfile/path`。资源路径支持 URL 编码。

传入来源数组时，按图片像素尺寸（包括 `scale`）与视图尺寸选择最接近的来源。`ImageRef` 使用内存中的图片。支持的格式由系统解码能力决定，SVG 支持的语法范围以系统 Image Kit 为准。

单个来源最大为 100 MiB，解码后的图片帧总大小最大为 256 MiB。来源使用不支持的协议时会以 `ERR_IMAGE_UNSUPPORTED_SOURCE` 失败。`sf:` 前缀不受支持。

`blurhash` 占位图解码后每边最多 512 像素；未提供尺寸时按 16 × 16 处理。

###### `ImageSource.uri`

类型：`string`

图片地址。支持的地址形式见 `source`。

###### `ImageSource.headers`

类型：`Record<string, string>`

随远程图片请求发送的请求头。

###### `ImageSource.width`

类型：`number | null`

已知图片宽度，用于来源数组选择和 BlurHash 占位图尺寸。

###### `ImageSource.height`

类型：`number | null`

已知图片高度，用于来源数组选择和 BlurHash 占位图尺寸。

###### `ImageSource.scale`

类型：`number`，默认 `1`

图片的逻辑尺寸与像素尺寸比例，也参与来源数组选择。

###### `ImageSource.cacheKey`

类型：`string`

缓存键，默认使用 `uri`。

###### `ImageSource.blurhash`

类型：`string`

将 BlurHash 作为占位图。与 `uri` 同时提供时忽略哈希。

###### `ImageSource.thumbhash`

类型：`string`

将 ThumbHash 作为占位图。与 `uri` 同时提供时忽略哈希。

###### `ImageSource.isAnimated`

- HarmonyOS 根据图片数据判断动画状态，不读取此属性。

###### `ImageSource.webMaxViewportWidth`

- HarmonyOS 不读取此属性。

##### `placeholder`

类型：与 `source` 相同，但不接受 `ImageRef`

图片加载前显示的占位图。占位图始终居中，不应用 `blurRadius` 和 `tintColor`；占位图加载失败不会触发 `onError`。

##### `defaultSource`

已废弃的兼容属性，用作占位图。`placeholder` 同时提供时优先使用 `placeholder`。

##### `loadingIndicatorSource`

已废弃的兼容属性，用作占位图。`placeholder` 同时提供时优先使用 `placeholder`。

##### `contentFit`

类型：`ImageContentFit`，默认 `'cover'`

图片在容器中的适配方式：`cover` 保持比例铺满并裁剪，`contain` 保持比例完整显示，`fill` 拉伸填满，`none` 不缩放，`scale-down` 选择 `none` 与 `contain` 中显示尺寸较小的一种。

##### `resizeMode`

已废弃的 React Native `Image` 兼容属性，等价于 `contentFit`。`stretch` 映射为 `fill`，`center` 映射为 `scale-down`，`repeat` 按 `cover` 处理。与 `contentFit` 同时提供时优先使用 `contentFit`。

##### `placeholderContentFit`

类型：`ImageContentFit`，默认 `'scale-down'`

占位图的适配方式。哈希占位图使用 `contentFit`。

##### `contentPosition`

类型：`ImageContentPosition`，默认 `'center'`

设置图片在容器中的位置。可以传对象，或传 `'top right'`、`'bottom'` 等字符串简写。对象中的数字表示距对应边缘的逻辑像素，字符串表示百分比；`'center'` 等价于 `'50%'`。

##### `transition`

类型：`number | ImageTransition | null`

切换图片来源时的过渡。传数字表示淡入淡出时长，单位为毫秒。对象的 `duration` 默认 `0`，`timing` 可为 `'ease-in-out'`、`'ease-in'`、`'ease-out'` 或 `'linear'`，默认 `'ease-in-out'`；`effect` 默认 `'cross-dissolve'`，设为 `'none'` 可关闭过渡。HarmonyOS 上其他 `effect` 值也按淡入淡出处理。

##### `fadeDuration`

已废弃的 React Native `Image` 兼容属性，作为淡入淡出时长（毫秒）传给 `transition`。与 `transition` 同时提供时优先使用 `transition`。

##### `cachePolicy`

类型：`'none' | 'disk' | 'memory' | 'memory-disk' | null`，默认 `'disk'`

设置图片缓存策略。`disk` 使用磁盘缓存，`memory` 使用内存缓存，`memory-disk` 使用两者，`none` 不缓存。默认缓存键为 `uri`，可用 `cacheKey` 区分同一地址的不同授权身份。远程图片解码成功后才写入缓存；无法解码的远程缓存会重新下载。自动写入缓存失败时，已解码图片仍可显示。

##### `blurRadius`

类型：`number`，默认 `0`

图片模糊半径，必须为非负数；`0` 表示不模糊。占位图不应用模糊。

##### `tintColor`

类型：`ColorValue | number | null`，默认 `null`

将颜色应用于图片的非透明像素。对 `ImageRef` 来源，建议在 `useImage` 或 `Image.loadAsync` 的选项中设置着色。

##### `allowDownscaling`

类型：`boolean`，默认 `true`

是否按视图尺寸下采样。设为 `false` 时按原始尺寸解码；`contentFit` 为 `none` 或 `fill` 时不下采样。

##### `priority`

类型：`'low' | 'normal' | 'high' | null`，默认 `'normal'`

远程图片下载优先级。排队时高优先级请求先开始，不保证完成顺序。

##### `recyclingKey`

类型：`string | null`，默认 `null`

值变化时先清除当前内容，再加载新图片，适用于列表项复用。

##### `autoplay`

类型：`boolean`，默认 `true`

控制动画图片是否自动播放。应用进入后台时暂停，回到前台后恢复。

GIF 循环次数取自文件；没有循环扩展时播放一次。API 24 及以上可读取 WebP 循环次数；更早的系统版本会循环播放。

##### `decodeFormat`

类型：`ImageDecodeFormat`，默认 `'argb'`

设置静态图片的解码格式。`'argb'` 使用带透明通道的 32 位色；`'rgb'` 使用不带透明通道的 16 位色，内存占用较小。动画图片和同时设置了 `tintColor` 的图片不使用 `'rgb'` 格式。

##### `accessible`

类型：`boolean`，默认 `false`

设为 `true` 后将图片作为一个无障碍元素聚焦和朗读。

##### `accessibilityLabel`

类型：`string`，默认空字符串

读屏朗读的文本。

##### `focusable`

类型：`boolean`，默认 `false`

是否允许使用非触摸输入设备聚焦。

##### `style`

图片视图样式。`borderRadius` 和各角圆角属性会裁剪图片。

##### `onLoadStart`

类型：`() => void`

开始加载图片时调用。

##### `onProgress`

类型：`(event: ImageProgressEventData) => void`

远程图片下载过程中调用，可能触发多次。`loaded` 为已下载字节数，`total` 为总字节数；长度未知时 `total` 为 `0`。

##### `onLoad`

类型：`(event: ImageLoadEventData) => void`

图片加载成功时调用，返回图片信息和缓存来源。

##### `onError`

类型：`(event: ImageErrorEventData) => void`

图片加载失败时调用；`error` 为包含错误码的文本。

##### `onDisplay`

类型：`() => void`

图片完成渲染时调用。

##### `onLoadEnd`

- HarmonyOS 没有对应的加载结束回调，此属性不会触发。

##### `alt`

- HarmonyOS 不会将此属性作为无障碍朗读文本；请使用 `accessibilityLabel`。

##### `draggable`

- HarmonyOS 不提供此属性对应的图片行为。

##### `loading`

- HarmonyOS 不提供此属性对应的图片行为。

##### `responsivePolicy`

- HarmonyOS 不提供此属性对应的图片行为。

##### `enableLiveTextInteraction`

- HarmonyOS 不提供此属性对应的效果。

##### `enforceEarlyResizing`

- HarmonyOS 不提供此属性对应的效果。

##### `preferHighDynamicRange`

- HarmonyOS 不提供此属性对应的效果。

##### `sfEffect`

- HarmonyOS 不提供此属性对应的符号效果。

##### `useAppleWebpCodec`

- HarmonyOS 不提供此属性对应的效果。

#### `ImageBackground`

以图片作为背景并在其上显示子组件。图片相关属性与 `Image` 相同。

##### `style`

容器样式。

##### `imageStyle`

背景图片样式。

### Hooks

#### `useImage(source, options, dependencies)`

返回 `ImageRef | null`；图片加载成功前为 `null`。`source` 可以是 `ImageSource`、字符串或资源模块 ID；来源 URI 变化时重新加载，也可通过 `dependencies` 指定其他重新加载时机。`options` 见 `ImageLoadOptions`。未使用的大图应设置 `maxWidth` 或 `maxHeight` 限制解码尺寸；不再使用返回的引用时调用 `release()`。

### Methods

#### `Image.loadAsync(source, options)`

返回 `Promise<ImageRef>`，将图片加载到内存。`source` 可为 `ImageSource`、字符串或资源模块 ID；`options` 见 `ImageLoadOptions`。成功加载的图片按 `memory-disk` 策略缓存。

未提供 `maxWidth`、`maxHeight` 时，SVG 按系统解码器给出的自然尺寸栅格化。提供任一尺寸时按比例缩放；SVG 可放大，普通位图只缩小。`ImageRef.width` 和 `ImageRef.height` 为解码后的逻辑尺寸。SVG 在视图中显示时按视图所需尺寸解码；预取到内存的位图不会用于该 SVG 视图。

#### `Image.prefetch(urls, options)`

返回 `Promise<boolean>`，预取一个或多个图片地址。第二个参数可为缓存策略或 `ImagePrefetchOptions`，默认缓存策略为 `'memory-disk'`。全部成功时返回 `true`；有图片失败时返回 `false`。选项中的 `headers` 会随远程请求发送。

#### `Image.getCachePathAsync(cacheKey)`

返回 `Promise<string | null>`，获取磁盘缓存文件路径；缓存未命中时为 `null`。默认缓存键为图片地址。

#### `Image.writeToCacheAsync(source, cacheKey)`

返回 `Promise<void>`，将应用可读取的本地 `file://` 图片或 `ImageRef` 写入指定键名的磁盘缓存，不发起网络请求。之后可用 `{ uri, cacheKey }` 显示图片，或调用 `Image.readFromCacheAsync(cacheKey)` 读取。

本地文件保留原始格式和动画；`ImageRef` 保存为静态 PNG。写入失败时不会替换该键已有缓存。此方法不需要图库权限。

#### `Image.readFromCacheAsync(cacheKey)`

返回 `Promise<ImageRef | null>`，只从内存或磁盘缓存读取，不发起网络请求。缓存未命中时返回 `null`。磁盘读取的图片 `scale` 为 `1`，宽高按像素计算；需要按逻辑尺寸显示时，可在来源中指定 `scale`。不再使用返回的引用时调用 `release()`。

#### `Image.clearMemoryCache()`

返回 `Promise<boolean>`，清理内存缓存。仍被引用的图片会保留并可继续显示；系统内存告警时也会清理内存缓存。

#### `Image.clearDiskCache()`

返回 `Promise<boolean>`，清理磁盘缓存。正在读取的图片会在读取结束后删除；清理开始前已发起的下载不会重新写入磁盘缓存。删除失败时返回 `false`。

#### `Image.configureCache(config)`

同步设置缓存上限。`maxDiskSize`、`maxMemoryCost` 分别为磁盘和内存缓存上限（字节），`maxMemoryCount` 为内存缓存条目数；均默认为 `0`（不限制），必须为非负整数。参数无效时抛出 `ERR_IMAGE_INVALID_CACHE_CONFIG`。

#### `Image.generateBlurhashAsync(source, numberOfComponents)`

返回 `Promise<string>`，从图片地址或 `ImageRef` 生成 BlurHash。`numberOfComponents` 可为 `[width, height]` 或 `{ width, height }`，每项为 1 到 9 的整数，默认 `[4, 3]`。参数无效时抛出 `ERR_IMAGE_INVALID_HASH_COMPONENTS`。

#### `Image.generateThumbhashAsync(source)`

返回 `Promise<string>`，从图片地址或 `ImageRef` 生成 ThumbHash。输入会缩小到不超过 100 × 100 像素。

#### `Image.startAnimating()`

返回 `Promise<void>`，开始播放当前动画图片。

#### `Image.stopAnimating()`

返回 `Promise<void>`，暂停播放当前动画图片。

#### `Image.lockResourceAsync()`

返回 `Promise<void>`，锁定当前图片资源，属性变化时不重新加载。

#### `Image.unlockResourceAsync()`

返回 `Promise<void>`，解除资源锁定，恢复常规重新加载。

#### `Image.reloadAsync()`

返回 `Promise<void>`，忽略锁定并强制重新加载。

#### `Image.getAnimatableRef()`

返回组件自身，可传给动画库。

#### `ImageRef.release()`

释放图片引用。`useImage` 和读取缓存返回的引用不再使用时应调用此方法。

### Event subscriptions

#### `imageLoaded`

图片视图、`Image.loadAsync` 和 `useImage` 成功加载图片后发送 `{ url, width, height }`；宽高为像素尺寸。占位图、预取、缓存读取和直接显示 `ImageRef` 不触发此事件。

### Types

#### `ImageSource`

图片来源类型，包含 `uri`、`headers`、`width`、`height`、`scale`、`cacheKey`、`blurhash`、`thumbhash`、`isAnimated` 和 `webMaxViewportWidth` 字段。字段在 HarmonyOS 上的行为见 `Image.source`。

#### `ImageRef`

已加载图片的引用，可作为 `Image` 的 `source`，也可作为生成 BlurHash 和 ThumbHash 的输入。不再使用时调用 `release()`。

##### `ImageRef.width`

类型：`number`，只读

图片逻辑宽度；乘以 `scale` 得到像素宽度。

##### `ImageRef.height`

类型：`number`，只读

图片逻辑高度；乘以 `scale` 得到像素高度。

##### `ImageRef.scale`

类型：`number`，只读

图片的像素比例，取自来源的 `scale`，默认 `1`。

##### `ImageRef.isAnimated`

类型：`boolean`，只读

是否为动画图片。

##### `ImageRef.mediaType`

类型：`string | null`，只读

图片 MIME 类型；未知时为 `null`。

#### `ImageProps`

`Image` 的属性类型，在 `ViewProps` 基础上增加图片属性。

#### `ImageBackgroundProps`

`ImageBackground` 的属性类型，在 `ImageProps` 基础上增加容器样式 `style` 和图片样式 `imageStyle`。

#### `ImageLoadOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `maxWidth`、`maxHeight` | `number` | 解码后的最大宽高，单位像素，按比例缩放。 |
| `tintColor` | `ColorValue \| number` | 图片着色。 |
| `onError` | `(error, retry) => void` | `useImage` 加载失败回调；`Image.loadAsync` 不调用此选项。 |

#### `ImagePrefetchOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `cachePolicy` | `'disk' \| 'memory-disk' \| 'memory'` | 缓存策略，默认 `'memory-disk'`。 |
| `headers` | `Record<string, string>` | 远程图片请求头。 |

#### `ImageCacheConfig`

`Image.configureCache` 的配置项。

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `maxDiskSize` | `number` | 磁盘缓存上限，单位字节，默认 `0`（不限制）。 |
| `maxMemoryCost` | `number` | 内存缓存上限，单位字节，默认 `0`（不限制）。 |
| `maxMemoryCount` | `number` | 内存缓存条目数上限，默认 `0`（不限制）。 |

#### `ImageTransition`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `duration` | `number` | 过渡时长，单位毫秒，默认 `0`。 |
| `timing` | `'ease-in-out' \| 'ease-in' \| 'ease-out' \| 'linear'` | 速度曲线，默认 `'ease-in-out'`。 |
| `effect` | `string` | 过渡效果，默认 `'cross-dissolve'`；`'none'` 关闭过渡。 |

#### `ImageContentFit`

类型：`'cover' | 'contain' | 'fill' | 'none' | 'scale-down'`，默认 `'cover'`。

#### `ImageDecodeFormat`

类型：`'argb' | 'rgb'`，默认 `'argb'`。

#### `ImageContentPosition`

图片在容器中的位置，可传对象或字符串简写。对象支持 `top`、`bottom`、`left`、`right`，字符串简写支持 `'center'`、`'top right'`、`'bottom'` 等形式。

#### `ImageContentPositionValue`

类型：`number | string`

数字表示距对应边缘的逻辑像素；字符串表示百分比，`'center'` 等价于 `'50%'`。

#### `ImageLoadEventData`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `cacheType` | `'none' \| 'disk' \| 'memory'` | 本次图片来源。 |
| `source` | `{ url, width, height, mediaType, isAnimated }` | 图片地址、逻辑宽高、MIME 类型和动画状态。 |

#### `ImageProgressEventData`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `loaded` | `number` | 已下载字节数。 |
| `total` | `number` | 总字节数；未知时为 `0`。 |

#### `ImageErrorEventData`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `error` | `string` | 含错误码的错误文本。 |

#### `ImageStyle`

React Native `ImageStyle` 的别名。HarmonyOS 图片圆角裁剪可通过此类型中的 `borderRadius` 和各角圆角属性设置。

#### `SFSymbolEffect`

- HarmonyOS 不提供此类型对应的符号效果。

#### `SFSymbolEffectObject`

- HarmonyOS 不提供此类型对应的符号效果。

#### `SFSymbolEffectType`

- HarmonyOS 不提供此类型对应的符号效果。

### Error codes

#### `ERR_IMAGE_CACHE_REMOTE_SOURCE`

`writeToCacheAsync` 收到非本地 `file://` 字符串来源时抛出。

#### `ERR_IMAGE_CACHE_WRITE`

图片无法写入磁盘缓存时抛出。

#### `ERR_IMAGE_DECODE`

系统无法打开或解码图片，或图片帧信息无效时抛出。

#### `ERR_IMAGE_DOWNLOAD`

远程图片无法下载，或响应不包含图片二进制数据时抛出。

#### `ERR_IMAGE_FILE_READ`

本地图片文件未能完整读取时抛出。

#### `ERR_IMAGE_FILE_WRITE`

图片缓存文件未能完整写入时抛出。

#### `ERR_IMAGE_HASH_TOO_LARGE`

ThumbHash 输入尺寸超过 100 × 100 像素时抛出。

#### `ERR_IMAGE_HTTP_STATUS`

远程图片请求返回非成功 HTTP 状态码时抛出。

#### `ERR_IMAGE_INVALID_ARGUMENT`

方法或视图属性的参数类型、数值或取值不符合要求时抛出。

#### `ERR_IMAGE_INVALID_CACHE_CONFIG`

缓存上限不是非负整数时抛出。

#### `ERR_IMAGE_INVALID_COLOR`

颜色值无法解析时抛出。

#### `ERR_IMAGE_INVALID_HASH`

BlurHash 或 ThumbHash 格式无效时抛出。

#### `ERR_IMAGE_INVALID_HASH_COMPONENTS`

BlurHash 组件不是 1 到 9 的整数时抛出。

#### `ERR_IMAGE_INVALID_HEADER`

请求头不是字符串键值对象，或包含无效值时抛出。

#### `ERR_IMAGE_INVALID_REF`

图片引用已释放或无法创建时抛出。

#### `ERR_IMAGE_INVALID_SOURCE`

图片来源为空、格式无效或包含非法 data URI 时抛出。

#### `ERR_IMAGE_LOAD_CANCELLED`

图片加载被取消时抛出。

#### `ERR_IMAGE_PIXEL_FORMAT`

生成哈希所需的图片像素格式不可用时抛出。

#### `ERR_IMAGE_RESOURCE`

无法读取打包资源或打开本地图片时抛出。

#### `ERR_IMAGE_RUNTIME_DESTROYED`

图片运行时已结束时抛出。

#### `ERR_IMAGE_TOO_LARGE`

图片来源超过 100 MiB，或解码后的图片帧总大小超过 256 MiB 时抛出。

#### `ERR_IMAGE_TRANSFORM`

图片着色等图像处理无法完成时抛出。

#### `ERR_IMAGE_UNSUPPORTED_SOURCE`

图片来源使用不支持的协议，包括 `sf:` 地址时抛出。

### Permissions

#### `ohos.permission.INTERNET`

用于下载 HTTP(S) 图片；本包的 HarmonyOS 模块已声明此权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
