# @expo-harmony/expo-camera

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-camera) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/camera/)

为 HarmonyOS 上的 React Native 应用提供 Expo Camera 的原生实现，与官方同版本的 `expo-camera` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-camera expo-camera
```

## API 对照表

### Hooks

#### `useCameraPermissions(options)`

查询和请求相机权限，返回 `[permission, requestPermission, getPermission]`。`permission` 为 `PermissionResponse | null`；两个方法分别请求和查询权限。`options.get` 默认 `true`，会自动查询；`options.request` 默认 `false`，设为 `true` 时自动请求。

#### `useMicrophonePermissions(options)`

查询和请求麦克风权限，返回 `[permission, requestPermission, getPermission]`。`options.get` 默认 `true`，会自动查询；`options.request` 默认 `false`，设为 `true` 时自动请求。录制带声音的视频前需要麦克风权限。

### Constants

#### `CameraView.isModernBarcodeScannerAvailable`

只读 `boolean`，表示设备是否提供系统条码扫码能力。该值为 `false` 时，系统扫码界面、图片扫码和实时预览扫码不可用。

### Methods

#### `CameraView.isAvailableAsync()`

返回 `Promise<boolean>`，表示设备是否有可用摄像头；此查询不代表应用已获得相机权限。

#### `CameraView.getAvailableVideoCodecsAsync()`

返回 `Promise<VideoCodec[]>`，列出设备可用的视频编码，结果只包含设备支持的 `'avc1'`、`'hvc1'`。

#### `CameraView.getSupportedFeatures()`

返回 `{ isModernBarcodeScannerAvailable, toggleRecordingAsyncAvailable }`。`isModernBarcodeScannerAvailable` 表示设备是否提供系统扫码能力；`toggleRecordingAsyncAvailable` 在 HarmonyOS 上始终为 `true`。

#### `CameraView.getAvailablePictureSizesAsync()`

返回 `Promise<string[]>`，列出当前摄像头可拍摄的 JPEG 分辨率，格式为 `宽x高`，按尺寸从大到小排列。设备只支持预览而不支持拍照时返回空数组。

#### `CameraView.getAvailableLensesAsync()`

返回 `Promise<string[]>`，列出当前 `facing` 方向摄像头的 ID，可用于 `selectedLens`。

#### `CameraView.takePictureAsync(options)`

等待 `onCameraReady` 后调用。返回 `Promise<CameraCapturedPicture | PictureRef | null>`；普通照片写入应用缓存目录。设置 `pictureRef: true` 时返回可交给 `Image` 或通过 `savePictureAsync()` 保存的 `PictureRef`。提供 `onPictureSaved` 时结果通过回调接收，Promise 返回 `null`。

`options` 支持：

- `quality`：JPEG 压缩质量，范围 `0` 到 `1`，默认 `1`。
- `base64`：是否在结果中附带 Base64 图片数据。
- `exif`：是否在结果中附带系统提供的 EXIF 信息。
- `additionalExif`：要写入的 EXIF 字段，仅在 `exif: true` 时生效。不支持写入的字段会被忽略；`MakerNote` 需 HarmonyOS API 20 及以上。
- `skipProcessing`：跳过方向校正和压缩，保留相机原始方向及尺寸；此时 `quality` 不生效。
- `imageType`：处理照片时选择 `'jpg'` 或 `'png'`；跳过处理时不生效。
- `mirror`：镜像前摄照片。
- `pictureRef`：设为 `true` 时返回 `PictureRef`。
- `maxDownsampling`：解码照片时允许的最大降采样倍数，必须为正整数。
- `onPictureSaved`：拍照完成时通过回调传递照片结果；设置后 Promise 返回 `null`。
- `shutterSound`：设为 `false` 不会关闭系统快门声，并会给出警告。

默认处理会校正照片方向，返回宽高与处理后的图片一致。录像模式、录像中、预览暂停或照片尚未就绪时调用会拒绝。无可用拍照分辨率的设备仍可预览，但拍照会失败。

HarmonyOS 上不支持的拍照选项：

- `scale`、`isImageMirror`：不生效。

#### `CameraView.recordAsync(options)`

仅在 `mode="video"` 时调用，返回 `Promise<{ uri: string }>`；录像以 MP4 格式写入应用缓存目录，停止录像或达到限制后返回文件地址。录制带声音的视频需要麦克风权限；未授权时调用会拒绝。

`options` 支持：

- `maxDuration`：最长录制时长，单位秒，到达限制后自动停止。
- `maxFileSize`：最大文件大小，单位字节，到达限制后自动停止。
- `mirror`：镜像前摄录像；需要 HarmonyOS SDK API 15 及以上，较低版本不生效。
- `codec`：`'avc1'` 或 `'hvc1'`。指定的编码不受设备支持时会拒绝；未指定时优先使用 H.264，不支持时使用 H.265。

#### `CameraView.stopRecording()`

停止正在进行的录像。方法不返回结果；`recordAsync()` 的 Promise 随后返回视频文件地址。切换摄像头、录像模式或停用相机也会停止录像。

#### `CameraView.toggleRecordingAsync()`

暂停或恢复正在进行的录像，返回 `Promise<void>`。没有正在进行的录像时不执行操作。

#### `CameraView.pausePreview()`

暂停相机预览，返回 `Promise<void>`。录像期间调用会拒绝；暂停时不能拍照或开始录像。

#### `CameraView.resumePreview()`

恢复相机预览，返回 `Promise<void>`。

#### `CameraView.launchScanner(options)`

打开系统扫码界面，返回 `Promise<void>`；扫描结果通过 `CameraView.onModernBarcodeScanned()` 订阅投递。`options.barcodeTypes` 指定要识别的条码类型，省略或传空列表时识别设备支持的类型。用户取消时 Promise 会拒绝。此系统扫码界面不需要应用相机权限。

#### `CameraView.dismissScanner()`

HarmonyOS Scan Kit 不提供关闭系统扫码界面的接口。调用此方法会以 `ERR_CAMERA_SCANNER_DISMISS_UNSUPPORTED` 拒绝。

#### `scanFromURLAsync(url, barcodeTypes)` / `Camera.scanFromURLAsync(url, barcodeTypes)`

从图片识别条码，返回 `Promise<BarcodeScanningResult[]>`。`url` 可为 `http(s)://`、Base64 编码的 `data:image/*` 或本地 `file://` 地址；`barcodeTypes` 省略时默认只识别 QR 码，传入空数组时返回空结果。设备没有扫码能力或图片无法读取时会拒绝。

#### `PictureRef.savePictureAsync(options)`

将 `PictureRef` 指向的图片写入应用缓存目录，返回 `Promise<PhotoResult>`。`options.quality` 指定 JPEG 压缩质量（`0` 到 `1`），`options.base64` 控制是否附带 Base64 数据，`options.metadata` 指定要写入的 EXIF 字段；不支持写入的字段会被忽略。

### Event subscriptions

#### `CameraView.onModernBarcodeScanned(listener)`

订阅 `launchScanner()` 的扫码结果，返回可通过 `remove()` 取消的 `Subscription`。事件参数类型为 `ScanningResult`，包含 `type`、`data` 和 `raw`。

### Types

#### `CameraViewProps`

`CameraView` 是相机预览组件，需在获得相机权限后使用。支持以下相机属性：

##### `facing`

`CameraType`，默认 `'back'`。选择 `'front'` 或 `'back'`；设备没有所选方向的摄像头时预览启动失败并触发 `onMountError`。

##### `flash`

`FlashMode`，默认 `'off'`。`'screen'` 在前摄拍照时使用屏幕白光补光，在后摄时按闪光灯打开处理。设备不支持所选模式时忽略该设置。

##### `enableTorch`

`boolean`，默认 `false`。开启常亮手电筒；设备不支持时忽略。

##### `zoom`

`number`，默认 `0`，范围 `0` 到 `1`；`0` 表示不变焦，`1` 表示设备最大变焦。超出范围会报错。

##### `mode`

`CameraMode`，默认 `'picture'`。可设为 `'picture'` 或 `'video'`；切换模式会停止当前录像。

##### `mute`

`boolean`，默认 `false`。设为 `true` 时录像不录制声音；设为 `false` 时需先获麦克风权限。

##### `autofocus`

`FocusMode`，默认 `'off'`。`'on'` 表示对焦一次后锁定，`'off'` 表示持续自动对焦；设备不支持时忽略。

##### `pictureSize`

`string`，格式为 `宽x高`。可通过 `getAvailablePictureSizesAsync()` 查询可用尺寸；优先精确匹配，否则选择不超过目标尺寸的最大分辨率，若都超过目标则选择最小分辨率。设置后照片尺寸由此属性决定，`ratio` 不再影响照片尺寸。

##### `ratio`

`CameraRatio`，可选 `'4:3'`、`'16:9'`、`'1:1'`。用于选择拍照分辨率和预览比例；没有匹配的拍照分辨率时回退到可用尺寸。`pictureSize` 设置后优先使用该尺寸。

##### `videoQuality`

`VideoQuality`，默认 `'1080p'`，支持 `'2160p'`、`'1080p'`、`'720p'`、`'480p'`、`'4:3'`。设备没有对应档位时优先选择更接近的较高档位，否则选择较低档位。

##### `videoBitrate`

`number`，录像码率，单位为比特每秒，默认 `8000000`。必须为正数。

##### `videoStabilizationMode`

`VideoStabilization`，默认 `'auto'`。`'off'` 关闭防抖，`'standard'` 使用低档，`'cinematic'` 使用高档，`'auto'` 由系统选择；请求档位不支持时尝试使用低档。

##### `mirror`

`boolean`，默认 `false`。镜像前摄拍照或录像；录像镜像需要 HarmonyOS SDK API 15 及以上，较低版本不生效并给出警告。

##### `active`

`boolean`，默认 `true`。设为 `false` 时停止预览；重新设为 `true` 后重新启动预览。停用相机会停止正在进行的录像。

##### `animateShutter`

`boolean`，默认 `true`。控制拍照时是否显示白色快门动画。

##### `responsiveOrientationWhenOrientationLocked`

`boolean`，默认 `false`。屏幕方向锁定时是否根据设备重力方向调整照片或视频方向。设为 `true` 时，方向变化通过 `onResponsiveOrientationChanged` 回调上报；录像方向在开始录制时确定。

##### `selectedLens`

`string | null`。指定 `getAvailableLensesAsync()` 返回的摄像头 ID。ID 不存在或与 `facing` 方向不匹配时，使用该方向的默认摄像头。

##### `barcodeScannerSettings`

`BarcodeSettings | null`。`barcodeTypes` 指定预览扫码类型；未设置或传空列表时识别设备支持的类型。需同时提供 `onBarcodeScanned` 回调以启用预览扫码。

##### `onBarcodeScanned`

预览中识别到条码时调用，参数为 `BarcodeScanningResult`。仅设备提供实时扫码能力时触发；结果包含 `type`、`data`、`raw`，实时预览结果的 `cornerPoints` 为空、`bounds` 为零。录像开始后暂停扫码，停止录像后恢复。

##### `onCameraReady`

相机预览启动完成时调用，无参数。

##### `onMountError`

预览无法启动时调用，参数包含 `message`。

##### `onAvailableLensesChanged`

当前方向的可用摄像头列表变化时调用，参数包含 `lenses`；预览就绪时也会调用一次。

##### `onResponsiveOrientationChanged`

`responsiveOrientationWhenOrientationLocked` 为 `true` 且设备方向变化时调用，参数包含 `orientation`。

HarmonyOS 上不支持的属性：

- `poster`：不支持预览占位图。

#### `CameraCapturedPicture`

照片结果类型包含：

- `uri`：应用缓存目录中的文件地址。
- `width`、`height`：处理后照片的宽和高。
- `format`：`'jpg'` 或 `'png'`。
- `base64`：仅在拍照选项 `base64: true` 时提供。
- `exif`：仅在拍照选项 `exif: true` 时提供，内容取决于系统返回的拍摄信息。

#### `PictureRef`

原生图片引用，包含只读 `width`、`height` 属性，并可调用 `savePictureAsync(options)` 将图片保存到缓存目录。

#### `CameraPictureOptions`

`takePictureAsync(options)` 的参数类型；支持的字段及 HarmonyOS 上不生效的字段见该方法说明。

#### `CameraRecordingOptions`

`recordAsync(options)` 的参数类型，包含 `maxDuration`、`maxFileSize`、`mirror` 和 `codec`。

#### `SavePictureOptions`

`PictureRef.savePictureAsync(options)` 的参数类型，包含 `quality`、`base64` 和 `metadata`。

#### `PhotoResult`

保存 `PictureRef` 后返回的结果类型，包含缓存文件 `uri`、图像 `width`、`height`，并可包含 `base64`。

#### `BarcodeScanningResult`

预览扫码和图片扫码的结果类型，包含条码类型 `type`、内容 `data`、原始内容 `raw`、角点 `cornerPoints` 和外接框 `bounds`。HarmonyOS 不返回 `extra`；实时预览扫码结果的几何字段为空值。

#### `ScanningResult`

系统扫码事件使用的结果类型，包含 `type`、`data`、`raw`，不包含 `bounds` 和 `cornerPoints`。

#### `BarcodeSettings`

预览扫码设置，包含 `barcodeTypes: BarcodeType[]`。

#### `ScanningOptions`

系统扫码界面的选项，包含 `barcodeTypes: BarcodeType[]`。

HarmonyOS 上不生效的选项：

- `isGuidanceEnabled`、`isHighlightingEnabled`、`isPinchToZoomEnabled`：不支持这些界面提示、标记和手势选项。

#### `BarcodeBounds`

条码外接框，包含左上角 `origin: BarcodePoint` 和尺寸 `size: BarcodeSize`。

#### `BarcodePoint`

条码坐标点，包含数值属性 `x` 和 `y`。

#### `BarcodeSize`

条码尺寸，包含数值属性 `width` 和 `height`。

#### `AvailableLenses`

可用摄像头列表事件的数据类型，包含 `lenses: string[]`。

#### `CameraMountError`

预览启动失败事件的数据类型，包含 `message: string`。

#### `ResponsiveOrientationChanged`

方向变化事件的数据类型，包含 `orientation: CameraOrientation`。

#### `CameraEvents`

模块事件映射，包含 `onModernBarcodeScanned: (event: ScanningResult) => void`。

#### `Subscription`

事件订阅句柄。调用 `remove()` 取消订阅，返回 `void`。

#### `PermissionResponse`

权限响应类型，包含 `status: PermissionStatus`、`granted: boolean`、`canAskAgain: boolean` 和 `expires: PermissionExpiration`。HarmonyOS 上 `expires` 始终为 `'never'`。

#### `PermissionExpiration`

权限过期值类型。HarmonyOS 上固定为 `'never'`。

#### `PermissionHookOptions`

权限 Hook 的选项类型；可用 `get`、`request` 控制自动查询或请求，默认仅自动查询权限状态。

#### `CameraType`

`'front' | 'back'`。

#### `FlashMode`

`'off' | 'on' | 'auto' | 'screen'`。

#### `FocusMode`

`'on' | 'off'`。

#### `CameraMode`

`'picture' | 'video'`。

#### `CameraRatio`

`'4:3' | '16:9' | '1:1'`。

#### `VideoQuality`

`'2160p' | '1080p' | '720p' | '480p' | '4:3'`。

#### `VideoStabilization`

`'off' | 'standard' | 'cinematic' | 'auto'`。

#### `VideoCodec`

HarmonyOS 上支持 `'avc1' | 'hvc1'`。设备不支持指定编码时，录像会失败。

#### `ImageType`

`'png' | 'jpg'`。

#### `CameraOrientation`

`'portrait' | 'portraitUpsideDown' | 'landscapeLeft' | 'landscapeRight'`。

#### `BarcodeType`

`'aztec' | 'ean13' | 'ean8' | 'qr' | 'pdf417' | 'upc_e' | 'datamatrix' | 'code39' | 'code93' | 'itf14' | 'codabar' | 'code128' | 'upc_a'`。

### Enums

#### `PermissionStatus`

权限状态枚举：`DENIED`、`GRANTED`、`UNDETERMINED`，对应 `'denied'`、`'granted'`、`'undetermined'`。

### Error codes

#### 权限和设备

- `ERR_CAMERA_PERMISSION`：未获得相机权限。
- `ERR_CAMERA_MICROPHONE_PERMISSION`：录制带声音的视频时未获得麦克风权限。
- `ERR_CAMERA_PERMISSION_REQUEST`：权限请求无法完成。
- `ERR_CAMERA_UNAVAILABLE`：设备没有可用摄像头，或没有所选方向的摄像头。
- `ERR_CAMERA_UNSUPPORTED`、`ERR_CAMERA_CAPTURE_UNSUPPORTED`、`ERR_CAMERA_VIDEO_UNSUPPORTED`：摄像头不支持所需预览、拍照或录像能力。

#### 拍照

- `ERR_CAMERA_INVALID_OPTION`：拍照选项或相机属性值无效。
- `ERR_CAMERA_WRONG_MODE`、`ERR_CAMERA_CAPTURE_DURING_RECORDING`、`ERR_CAMERA_CAPTURE_IN_PROGRESS`、`ERR_CAMERA_PREVIEW_PAUSED`：当前模式、录像状态、并发拍照或预览状态不允许拍照。
- `ERR_CAMERA_NOT_READY`、`ERR_CAMERA_CAPTURE_TIMEOUT`：相机未能及时就绪或返回照片。
- `ERR_CAMERA_CAPTURE_FAILED`、`ERR_CAMERA_CAPTURE_INTERRUPTED`、`ERR_CAMERA_CAPTURE_PROCESSING`、`ERR_CAMERA_CAPTURE_ROTATION`、`ERR_CAMERA_EXIF_WRITE`：拍照、照片处理、方向校正或 EXIF 写入失败。
- `ERR_CAMERA_INITIALIZATION`、`ERR_CAMERA_INITIALIZATION_CANCELLED`、`ERR_CAMERA_SESSION`、`ERR_CAMERA_VIEW_DESTROYED`：相机预览启动、相机状态切换或预览视图生命周期导致操作无法完成。

#### 录像

- `ERR_CAMERA_RECORDING_IN_PROGRESS`、`ERR_CAMERA_RECORDING_CANCELLED`、`ERR_CAMERA_PREVIEW_DURING_RECORDING`：已有录像进行中、录像启动被取消，或录像期间尝试暂停预览。
- `ERR_CAMERA_CODEC_UNSUPPORTED`：设备不支持指定的视频编码。
- `ERR_CAMERA_RECORDING`、`ERR_CAMERA_RECORDING_START`、`ERR_CAMERA_RECORDING_STOP`、`ERR_CAMERA_RECORDING_FILE`：录像启动、录制、停止或文件写入失败。

#### 扫码

- `ERR_CAMERA_INVALID_URL`、`ERR_CAMERA_BARCODE_SCAN`：图片地址无效或图片扫码失败。
- `ERR_CAMERA_SCANNER_UNAVAILABLE`：设备没有扫码能力。
- `ERR_CAMERA_SCANNER_CANCELLED`：用户取消系统扫码。
- `ERR_CAMERA_SCANNER`：系统扫码未能完成。
- `ERR_CAMERA_SCANNER_DISMISS_UNSUPPORTED`：HarmonyOS 不支持通过 API 关闭系统扫码界面。

### Permissions

#### 相机和麦克风权限

- `Camera.getCameraPermissionsAsync()`：返回 `Promise<PermissionResponse>`，查询相机权限，不弹出授权请求。
- `Camera.requestCameraPermissionsAsync()`：返回 `Promise<PermissionResponse>`，请求相机权限。
- `Camera.getMicrophonePermissionsAsync()`：返回 `Promise<PermissionResponse>`，查询麦克风权限，不弹出授权请求。
- `Camera.requestMicrophonePermissionsAsync()`：返回 `Promise<PermissionResponse>`，请求麦克风权限。

相机预览和拍照需要相机权限；录制带声音的视频需要麦克风权限。HarmonyOS SDK API 20 及以上可区分未决定和拒绝；API 13–19 查询时无法区分两者，未决定状态也会返回 `status: 'denied'`。`expires` 始终为 `'never'`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
