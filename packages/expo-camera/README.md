# @expo-harmony/expo-camera

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-camera) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/camera/)

为 HarmonyOS 上的 React Native 应用提供 Expo Camera 的原生实现，与官方同版本的 `expo-camera` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-camera expo-camera@55.0.19
```

## API 对照表

### Static properties

#### `CameraView.isModernBarcodeScannerAvailable`

类型：`boolean`，只读

设备是否具备系统扫码能力。没有该能力的设备、模拟器返回 `false`。

### Component

#### `CameraView`

相机预览组件。

#### `facing`

类型：`CameraType`，默认 `'back'`

选择前摄或后摄。该方向没有可用摄像头时预览初始化失败并触发 `onMountError`。

#### `flash`

类型：`FlashMode`，默认 `'off'`

拍照闪光灯模式。`screen` 在前摄时用屏幕白光补光，后摄时按闪光灯打开处理。设备不支持所设模式时忽略。

#### `enableTorch`

类型：`boolean`，默认 `false`

常亮手电筒。系统不支持时忽略。

#### `zoom`

类型：`number`，默认 `0`

按设备最大变焦比例取值，`0` 表示不变焦，`1` 表示最大变焦。超出 `0` 到 `1` 的值拒绝。

#### `mode`

类型：`CameraMode`，默认 `'picture'`

拍照或录像模式。切换会重建相机管线，进行中的录像先停止。

#### `mute`

类型：`boolean`，默认 `false`

录像时不录声音。为 `false` 时开始录像前需要麦克风权限，未授权则拒绝。

#### `autofocus`

类型：`FocusMode`，默认 `'off'`

`'on'` 表示对焦一次后锁定，`'off'` 表示持续自动对焦。设备不支持时忽略。官方标记为 iOS 专属属性，在 HarmonyOS 上可用。

#### `pictureSize`

类型：`string`

拍照分辨率，格式为 `宽x高`。优先精确匹配，没有时取不超过该尺寸的最大分辨率，全都超过时取最小分辨率。设置后照片尺寸由该值决定，`ratio` 不再生效。

#### `ratio`

类型：`CameraRatio`

按宽高比筛选拍照分辨率，取值 `'4:3'`、`'16:9'`、`'1:1'`。没有匹配的分辨率时回退到全部可用值。`pictureSize` 优先。官方标记为 Android 专属属性，在 HarmonyOS 上可用。

#### `videoQuality`

类型：`VideoQuality`，默认 `'1080p'`

录像分辨率，取值 `'2160p'`、`'1080p'`、`'720p'`、`'480p'`、`'4:3'`。没有对应档位时取最接近的可用值。

#### `videoBitrate`

类型：`number`

录像码率，单位比特每秒，默认 8000000。

#### `videoStabilizationMode`

类型：`VideoStabilization`，默认 `'auto'`

视频防抖模式。`off` 关闭，`standard` 对应低档，`cinematic` 对应高档，`auto` 交给系统。所设模式不支持时降级到低档。

#### `mirror`

类型：`boolean`，默认 `false`

前摄镜像。拍照优先用系统镜像能力，不支持时软件翻转。录像镜像需要 API 15 及以上，低版本上不生效并给出警告。

#### `active`

类型：`boolean`，默认 `true`

为 `false` 时停止相机预览，改回 `true` 时重新启动。官方标记为 iOS 专属属性，在 HarmonyOS 上可用。

#### `animateShutter`

类型：`boolean`，默认 `true`

拍照时显示一次白色快门动画。

#### `responsiveOrientationWhenOrientationLocked`

类型：`boolean`，默认 `false`

屏幕方向锁定时是否跟随设备重力方向，开启后通过 `onResponsiveOrientationChanged` 上报方向。官方标记为 iOS 专属属性，在 HarmonyOS 上可用。

#### `selectedLens`

类型：`string | null`

按摄像头 ID 指定镜头，ID 取自 `getAvailableLensesAsync()`。ID 与当前 `facing` 不匹配或不存在时回退到该方向的默认摄像头。官方标记为 iOS 专属属性，在 HarmonyOS 上可用。

#### `barcodeScannerSettings`

类型：`BarcodeSettings | null`

接收条码类型设置。实时条码扫描不可用，该设置没有实际效果。

#### `onCameraReady`

预览启动完成后触发，无参数。

#### `onMountError`

预览无法启动时触发，回调参数含 `message`。

#### `onAvailableLensesChanged`

当前方向的可用摄像头增减时触发，回调参数含 `lenses`。预览就绪时也会触发一次。官方标记为 iOS 专属属性，在 HarmonyOS 上可用。

#### `onResponsiveOrientationChanged`

`responsiveOrientationWhenOrientationLocked` 为 `true` 时，设备方向变化触发，回调参数含 `orientation`。官方标记为 iOS 专属属性，在 HarmonyOS 上可用。

> **未实现的内容**
>
> - `onBarcodeScanned`：实时条码扫描不可用，设置后预览会触发一次 `onMountError` 并给出警告，回调不会收到扫描数据。
> - `poster`：仅在 Web 上加载预览占位图，HarmonyOS 上无对应能力。

### Static methods

#### `CameraView.isAvailableAsync()`

返回 `Promise<boolean>`，设备是否有可用摄像头。官方标记为 Web 专属接口，在 HarmonyOS 上可用。

#### `CameraView.getAvailableVideoCodecsAsync()`

返回 `Promise<VideoCodec[]>`，设备支持的录像编码，取值为 `'avc1'` 和 `'hvc1'` 中实际可用的项。该方法是官方标记的 iOS 专属接口，在 HarmonyOS 上可用。

#### `CameraView.launchScanner(options)`

打开系统扫码界面，返回 `Promise<void>`。扫描结果通过 `onModernBarcodeScanned` 投递。用户取消时拒绝。设备不具备系统扫码能力时不执行任何操作。

#### `CameraView.onModernBarcodeScanned(listener)`

订阅 `launchScanner` 的扫描结果，返回 `Subscription`。

> **未实现的内容**
>
> - `dismissScanner()`：HarmonyOS Scan Kit 不提供关闭系统扫码界面的接口，设备具备系统扫码能力时调用会抛出错误。

### Component methods

#### `getAvailablePictureSizesAsync()`

返回 `Promise<string[]>`，当前设备支持的 JPEG 拍照分辨率，从大到小排列。

#### `getAvailableLensesAsync()`

返回 `Promise<string[]>`，当前 `facing` 方向可用摄像头的 ID。该方法是官方标记的 iOS 专属接口，在 HarmonyOS 上可用。

#### `getSupportedFeatures()`

返回 `{ isModernBarcodeScannerAvailable, toggleRecordingAsyncAvailable }`。前者取决于设备是否具备系统扫码能力，后者恒为 `true`。

#### `takePictureAsync(options)`

返回 `Promise<CameraCapturedPicture | PictureRef | null>`，照片写入应用缓存目录。

| 选项              | 说明                                                    |
| ----------------- | ------------------------------------------------------- |
| `quality`         | JPEG 压缩质量，`0` 到 `1`，默认 `1`                     |
| `base64`          | 结果是否包含 Base64 数据                                |
| `exif`            | 结果是否包含 EXIF 数据                                  |
| `additionalExif`  | 写入照片的额外 EXIF 字段，仅在 `exif` 为 `true` 时生效  |
| `skipProcessing`  | 跳过旋转和压缩，直接返回相机原始图像                    |
| `imageType`       | `'jpg'` 或 `'png'`，仅在未跳过处理时生效                |
| `mirror`          | 前摄镜像，已弃用，建议改用 `mirror` 属性                |
| `pictureRef`      | 返回 `PictureRef` 而不是普通结果对象                    |
| `maxDownsampling` | 解码时的最大降采样倍数                                  |
| `fastMode`        | 立即返回 `null`，结果通过 `onPictureSaved` 投递         |
| `onPictureSaved`  | 拍照完成后的回调，传入后方法立即返回                    |
| `shutterSound`    | 设为 `false` 不会关闭系统快门声，只给出警告             |

录像模式、正在录像或预览已暂停时调用会拒绝。相机 5 秒内未就绪、拍照请求 15 秒内没有返回照片时也会拒绝。

#### `recordAsync(options)`

返回 `Promise<{ uri: string }>`，视频写入应用缓存目录，格式为 MP4。

| 选项          | 说明                                                   |
| ------------- | ------------------------------------------------------ |
| `maxDuration` | 最长录制时长，单位秒，到点自动停止                     |
| `maxFileSize` | 最大文件大小，单位字节，到点自动停止                   |
| `mirror`      | 前摄镜像，已弃用，建议改用 `mirror` 属性               |
| `codec`       | `'avc1'` 或 `'hvc1'`，不支持所设编码时拒绝；不传时优先 H.264，没有则用 H.265 |

只在录像模式可用，否则拒绝。录制中切换摄像头或模式会停止录制，已写入的文件正常返回。

#### `stopRecording()`

停止正在进行的录像，无返回值。`recordAsync` 的 Promise 随之返回文件地址。

#### `toggleRecordingAsync()`

暂停或恢复正在进行的录像，返回 `Promise<void>`。没有录像时为无操作。

#### `pausePreview()`

暂停预览，返回 `Promise<void>`。录像期间调用会拒绝。

#### `resumePreview()`

恢复预览，返回 `Promise<void>`。

> **未实现的内容**
>
> - `takePictureAsync` 的 `scale`、`isImageMirror` 选项：仅 Web 有效，HarmonyOS 上忽略。

### Hooks

#### `useCameraPermissions(options)`

返回 `[PermissionResponse | null, request, get]`，分别对应权限状态和请求、查询方法。

#### `useMicrophonePermissions(options)`

返回 `[PermissionResponse | null, request, get]`，分别对应权限状态和请求、查询方法。

API 20 起用系统权限状态区分未决定和拒绝；API 13–19 的查询只能判断是否授权，未决定按 `denied` 返回。`expires` 恒为 `'never'`。

### Classes

#### `PictureRef`

原生图像引用，继承 `SharedRef<'image'>`。

#### `PictureRef.width`

类型：`number`，只读

图像宽度。

#### `PictureRef.height`

类型：`number`，只读

图像高度。

#### `PictureRef.nativeRefType`

类型：`string`，只读

原生引用类型，恒为 `'image'`。

#### `PictureRef.savePictureAsync(options)`

返回 `Promise<PhotoResult>`，把引用指向的图像写入缓存目录。

| 选项       | 说明                          |
| ---------- | ----------------------------- |
| `quality`  | JPEG 压缩质量，`0` 到 `1`     |
| `base64`   | 结果是否包含 Base64 数据      |
| `metadata` | 写入图像的额外 EXIF 字段      |

### Methods

#### `Camera.getCameraPermissionsAsync()`

返回 `Promise<PermissionResponse>`，查询相机权限，不弹出授权弹窗。

#### `Camera.requestCameraPermissionsAsync()`

返回 `Promise<PermissionResponse>`，请求相机权限，未决定时弹出授权弹窗。

#### `Camera.getMicrophonePermissionsAsync()`

返回 `Promise<PermissionResponse>`，查询麦克风权限，不弹出授权弹窗。

#### `Camera.requestMicrophonePermissionsAsync()`

返回 `Promise<PermissionResponse>`，请求麦克风权限，未决定时弹出授权弹窗。

#### `Camera.scanFromURLAsync(url, barcodeTypes)`

返回 `Promise<BarcodeScanningResult[]>`，从图片识别条码。支持 `http(s)://`、`data:` 和本地 `file://` 地址，图片超过 10 MB 时拒绝。`barcodeTypes` 省略时只识别 QR 码，传空数组返回空结果。设备不支持扫码能力时拒绝。

### Types

#### `CameraCapturedPicture`

| 属性     | 类型             | 说明                 |
| -------- | ---------------- | -------------------- |
| `uri`    | `string`         | 本地文件地址         |
| `width`  | `number`         | 图像宽度             |
| `height` | `number`         | 图像高度             |
| `format` | `'jpg' \| 'png'` | 图像格式             |
| `base64` | `string`         | 开启 `base64` 时包含 |
| `exif`   | `object`         | 开启 `exif` 时包含   |

#### `CameraPictureOptions`

字段含义见 `takePictureAsync(options)`。

#### `CameraRecordingOptions`

字段含义见 `recordAsync(options)`。

#### `SavePictureOptions`

| 属性       | 类型                  | 说明                     |
| ---------- | --------------------- | ------------------------ |
| `quality`  | `number`              | JPEG 压缩质量，`0` 到 `1` |
| `base64`   | `boolean`             | 结果是否包含 Base64 数据 |
| `metadata` | `Record<string, any>` | 写入图像的额外 EXIF 字段  |

#### `PhotoResult`

| 属性     | 类型     | 说明                 |
| -------- | -------- | -------------------- |
| `uri`    | `string` | 本地文件地址         |
| `width`  | `number` | 图像宽度             |
| `height` | `number` | 图像高度             |
| `base64` | `string` | 开启 `base64` 时包含 |

#### `BarcodeScanningResult`

| 属性           | 类型             | 说明               |
| -------------- | ---------------- | ------------------ |
| `type`         | `string`         | 条码类型           |
| `data`         | `string`         | 条码内容           |
| `raw`          | `string`         | 与 `data` 相同     |
| `cornerPoints` | `BarcodePoint[]` | 条码角点，可能为空 |
| `bounds`       | `BarcodeBounds`  | 条码外接矩形       |

> **未实现的内容**
>
> - `extra`：Android 专属字段，HarmonyOS 上不返回。
> - `AndroidBarcode`：Android 专属类型，HarmonyOS 上没有取值来源。

#### `ScanningResult`

`BarcodeScanningResult` 去掉 `bounds` 和 `cornerPoints`。

#### `BarcodeBounds`

| 属性     | 类型           |
| -------- | -------------- |
| `origin` | `BarcodePoint` |
| `size`   | `BarcodeSize`  |

#### `BarcodePoint`

| 属性 | 类型     |
| ---- | -------- |
| `x`  | `number` |
| `y`  | `number` |

#### `BarcodeSize`

| 属性     | 类型     |
| -------- | -------- |
| `width`  | `number` |
| `height` | `number` |

#### `BarcodeSettings`

| 属性           | 类型            |
| -------------- | --------------- |
| `barcodeTypes` | `BarcodeType[]` |

#### `ScanningOptions`

| 属性           | 类型            | 说明                             |
| -------------- | --------------- | -------------------------------- |
| `barcodeTypes` | `BarcodeType[]` | 要识别的条码类型，省略时识别全部 |

`isGuidanceEnabled`、`isHighlightingEnabled`、`isPinchToZoomEnabled` 是 iOS 专属字段，HarmonyOS 上忽略。

#### `AvailableLenses`

| 属性     | 类型       |
| -------- | ---------- |
| `lenses` | `string[]` |

#### `CameraMountError`

| 属性      | 类型     |
| --------- | -------- |
| `message` | `string` |

#### `ResponsiveOrientationChanged`

| 属性          | 类型                |
| ------------- | ------------------- |
| `orientation` | `CameraOrientation` |

#### `CameraEvents`

| 事件                     | 载荷             |
| ------------------------ | ---------------- |
| `onModernBarcodeScanned` | `ScanningResult` |

#### `PermissionResponse`

| 属性          | 类型                   | 说明           |
| ------------- | ---------------------- | -------------- |
| `status`      | `PermissionStatus`     | 权限状态       |
| `granted`     | `boolean`              | 是否已授权     |
| `canAskAgain` | `boolean`              | 能否再次请求   |
| `expires`     | `PermissionExpiration` | 恒为 `'never'` |

#### `PermissionExpiration`

`'never' | number`。

#### `PermissionHookOptions`

`PermissionHookBehavior | Options`。

#### `CameraType`

`'front' | 'back'`

#### `FlashMode`

`'off' | 'on' | 'auto' | 'screen'`

#### `FocusMode`

`'on' | 'off'`

#### `CameraMode`

`'picture' | 'video'`

#### `CameraRatio`

`'4:3' | '16:9' | '1:1'`

#### `VideoQuality`

`'2160p' | '1080p' | '720p' | '480p' | '4:3'`

#### `VideoStabilization`

`'off' | 'standard' | 'cinematic' | 'auto'`

#### `VideoCodec`

`'avc1' | 'hvc1' | 'jpeg' | 'apcn' | 'ap4h'`。HarmonyOS 上只产出 `'avc1'` 和 `'hvc1'`。

#### `ImageType`

`'png' | 'jpg'`

#### `CameraOrientation`

`'portrait' | 'portraitUpsideDown' | 'landscapeLeft' | 'landscapeRight'`

#### `BarcodeType`

`'aztec' | 'ean13' | 'ean8' | 'qr' | 'pdf417' | 'upc_e' | 'datamatrix' | 'code39' | 'code93' | 'itf14' | 'codabar' | 'code128' | 'upc_a'`

### Interfaces

#### `Subscription`

事件订阅句柄，调用 `remove()` 取消订阅，返回 `void`。

### Enums

#### `PermissionStatus`

| 成员           | 值               |
| -------------- | ---------------- |
| `DENIED`       | `'denied'`       |
| `GRANTED`      | `'granted'`      |
| `UNDETERMINED` | `'undetermined'` |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
