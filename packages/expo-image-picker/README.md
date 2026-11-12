# @expo-harmony/expo-image-picker

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-image-picker) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/imagepicker/)

为 HarmonyOS 上的 React Native 应用提供 Expo ImagePicker 的原生实现，与官方同版本的 `expo-image-picker` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-image-picker expo-image-picker
```

## 使用

```ts
import * as ImagePicker from 'expo-image-picker';

const result = await ImagePicker.launchImageLibraryAsync({
  mediaTypes: ['images', 'videos'],
  allowsMultipleSelection: true,
  selectionLimit: 10,
});
```

## API 对照表

### Hooks

#### `useCameraPermissions(options)`

返回 `[PermissionResponse | null, request, get]`，依次为权限状态、请求权限的方法和查询权限的方法。默认自动查询；`options.request` 为 `true` 时自动调用请求方法，`options.get` 为 `false` 时不自动查询。

#### `useMediaLibraryPermissions(options)`

返回 `[MediaLibraryPermissionResponse | null, request, get]`。`options.writeOnly` 会传给图库权限方法，但在 HarmonyOS 上不影响结果；`get` 和 `request` 的行为与 `useCameraPermissions` 相同。

### Methods

#### `ImagePicker.getCameraPermissionsAsync()`

返回 `Promise<CameraPermissionResponse>`。HarmonyOS 上的 `status` 和 `granted` 表示系统相机选择器是否可用：可用时为 `'granted'` 和 `true`，否则为 `'denied'` 和 `false`。`canAskAgain` 与选择器是否可用相同，`expires` 为 `'never'`。这不是应用对相机硬件的权限状态。

#### `ImagePicker.getMediaLibraryPermissionsAsync(writeOnly)`

返回 `Promise<MediaLibraryPermissionResponse>`。图库选择器可用时为已授权，`accessPrivileges` 为 `'all'`；不可用时为拒绝，`accessPrivileges` 为 `'none'`。这里的授权状态只表示系统图库选择器可用，不表示应用可以浏览或写入整个图库。`writeOnly` 不影响结果。

#### `ImagePicker.getPendingResultAsync()`

返回 `Promise<null>`。HarmonyOS 上始终返回 `null`，不会返回待处理结果或错误结果。

#### `ImagePicker.launchCameraAsync(options)`

返回 `Promise<ImagePickerResult>`，打开系统相机拍照或录像。系统相机负责拍摄，无需应用申请相机权限。只有 `mediaTypes` 只包含 `'videos'` 时录像；包含图片和视频时按拍照处理。`cameraType` 可指定前置或后置摄像头，`videoMaxDuration` 设置录像时长上限。

拍摄结果的 `uri` 指向应用缓存中的文件，需要长期保存时请复制到其他位置。视频按系统返回的元数据提供尺寸、时长和旋转角。用户取消时返回 `{ canceled: true, assets: null }`；系统可能无法区分取消和拍摄失败。系统相机或图库选择界面已打开时再次调用，也会返回取消结果。

系统相机不可用时抛出 `ERR_IMAGE_PICKER_UNAVAILABLE`；拍摄结果不可用时抛出 `ERR_IMAGE_PICKER_CAMERA`。应用不在前台或没有可显示界面时抛出 `ERR_IMAGE_PICKER_CONTEXT`。系统界面打开后，即使应用暂时进入后台，仍会返回结果。

#### `ImagePicker.launchImageLibraryAsync(options)`

返回 `Promise<ImagePickerResult>`，打开系统图库选择界面。用户选中的文件不需要整库访问权限。照片中的位置信息可能被系统移除；若需读取照片 EXIF 中的 GPS 信息，还需声明并申请 `ohos.permission.MEDIA_LOCATION`。

`allowsMultipleSelection` 为 `false` 时最多选择一项；为 `true` 时由 `selectionLimit` 限制，`selectionLimit` 为 `0` 或大于 `500` 时按 `500` 处理。单选图片时可通过 `allowsEditing` 请求系统编辑入口，是否显示由系统决定；多选或仅选视频时忽略编辑选项。

图库结果的 `uri` 指向应用缓存中的文件，需要长期保存时请复制到其他位置。取消时返回 `{ canceled: true, assets: null }`。系统相机或图库选择界面已打开时再次调用，也会返回取消结果。

在 `mediaTypes` 中指定 `'livePhotos'` 可选择动态照片。返回的资源 `type` 为 `'livePhoto'`，`uri` 指向封面，`pairedVideoAsset.uri` 指向配对视频；两份文件按图库提供的原始质量返回。开启编辑时不选择动态照片。HarmonyOS API 22 及以上，用户可在系统选择器中关闭动态效果；若未允许普通图片，关闭动态效果后不会返回该照片。API 13 至 API 21 在同时请求视频和动态照片时，选择器也可能显示普通图片，这些图片不会作为结果返回。

系统图库选择器不可用，或设备缺少读取视频信息的能力时，抛出 `ERR_IMAGE_PICKER_UNAVAILABLE`。应用不在前台或没有可显示界面时抛出 `ERR_IMAGE_PICKER_CONTEXT`。系统界面打开后，即使应用暂时进入后台，仍会返回结果。

#### `ImagePicker.requestCameraPermissionsAsync()`

返回 `Promise<CameraPermissionResponse>`，结果与 `getCameraPermissionsAsync()` 相同，不会弹出权限对话框。

#### `ImagePicker.requestMediaLibraryPermissionsAsync(writeOnly)`

返回 `Promise<MediaLibraryPermissionResponse>`，结果与 `getMediaLibraryPermissionsAsync(writeOnly)` 相同，不会弹出权限对话框。

### Types

#### `CameraPermissionResponse`

`PermissionResponse` 的别名。HarmonyOS 上的相机权限响应表示系统相机选择器是否可用。

#### `CropShape`

裁剪区域形状：`'rectangle' | 'oval'`。HarmonyOS 编辑不支持椭圆裁剪；与 `allowsEditing: true` 一起传入 `'oval'` 会抛出 `ERR_IMAGE_PICKER_UNSUPPORTED_EDITING`。

#### `DefaultTab`

- HarmonyOS 系统图库选择器没有可设置默认标签页的选项。

#### `ImagePickerAsset`

| 属性 | 类型 | HarmonyOS 返回值 |
| --- | --- | --- |
| `uri` | `string` | 应用缓存文件的 URI。 |
| `assetId` | `string \| null` | 图库资源标识；拍摄结果为 `null`。 |
| `width`、`height` | `number` | 媒体尺寸；图片按 EXIF 方向校正，视频按旋转角校正。 |
| `type` | `'image' \| 'video' \| 'livePhoto' \| 'pairedVideo'` | 资源类型；`'pairedVideo'` 仅用于动态照片的配对视频。 |
| `fileName` | `string` | 系统提供的文件名；重新编码图片时扩展名与输出格式一致。 |
| `fileSize` | `number` | 返回文件的字节数。 |
| `mimeType` | `string` | 输出文件的 MIME 类型；系统未提供视频类型时省略。 |
| `base64` | `string` | 请求后返回图片的 JPEG Base64 数据。 |
| `exif` | `Record<string, any>` | 请求后返回图片 EXIF；读不到时为空对象。 |
| `duration` | `number \| null` | 视频时长，单位为毫秒。 |
| `rotation` | `number \| null` | 视频旋转角。 |
| `pairedVideoAsset` | `ImagePickerAsset` | 动态照片的配对视频资源。 |

图片不返回 `duration` 和 `rotation`；未请求时不返回 `base64` 和 `exif`。EXIF 中的 GPS 经纬度以十进制度表示，图像方向为 1 到 8 的整数。JPEG、PNG、HEIF 和 HEIC 支持读取 EXIF；WebP 和 DNG 需要 HarmonyOS API 23 及以上，其他格式或读取失败时返回空对象。

- `file`：系统选择器不会返回文件对象。

#### `ImagePickerCanceledResult`

取消结果，`canceled` 为 `true`，`assets` 为 `null`。

#### `ImagePickerErrorResult`

错误结果包含 `code`、`message` 和可选的 `exception`。

- HarmonyOS 的选择器错误通过 Promise rejection 抛出；`getPendingResultAsync()` 不会返回此类型。

#### `ImagePickerOptions`

| 选项 | 默认值 | HarmonyOS 行为 |
| --- | --- | --- |
| `allowsEditing` | `false` | 单选图片时请求系统编辑入口；是否显示由系统决定。多选或仅选视频时忽略。 |
| `allowsMultipleSelection` | `false` | 是否允许图库多选。 |
| `aspect` | — | 固定裁剪比例。必须是两个正的有限数。 |
| `base64` | `false` | 是否返回图片 JPEG Base64 数据；按 `quality` 编码，不改变缓存文件格式。 |
| `cameraType` | `'back'` | 拍摄时选择前置或后置摄像头。 |
| `exif` | `false` | 是否返回图片 EXIF 数据。 |
| `mediaTypes` | `'images'` | 选择图片、视频或动态照片。可传 `MediaType`、其数组或 `MediaTypeOptions`；省略或传空数组时默认图片。 |
| `quality` | `1` | 图片压缩质量，范围为 0 到 1。为 1 时保留原格式和 GIF 动画；小于 1 时重新编码，PNG、GIF、BMP 和 WebP 输出 PNG，GIF 只保留首帧，其他图片输出 JPEG。动态照片按原始质量返回。 |
| `selectionLimit` | `0` | 多选上限，必须是有限的非负安全整数；`0` 或大于 `500` 时按 `500` 处理。 |
| `shape` | `'rectangle'` | 裁剪形状。 |
| `videoMaxDuration` | `0` | 拍摄视频的时长上限，单位为秒；`0` 表示不限，非整数向下取整。录像时正数小于 1 或取整后超过 `2147483647` 会抛出 `ERR_INVALID_ARGUMENT`。 |

- `aspect`：系统编辑入口不支持固定比例；单独传入时忽略，与开启编辑一起使用时抛出 `ERR_IMAGE_PICKER_UNSUPPORTED_EDITING`。
- `shape: 'oval'`：系统选择器不支持椭圆裁剪；开启编辑时抛出 `ERR_IMAGE_PICKER_UNSUPPORTED_EDITING`。
- `defaultTab`：系统选择器不提供默认标签页设置。
- `legacy`：系统选择器不提供旧版选择模式。
- `orderedSelection`：系统选择器不提供选择顺序设置。
- `preferredAssetRepresentationMode`：资源表示方式由系统选择器决定。
- `presentationStyle`：选择器界面样式由系统决定。
- `shouldDownloadFromNetwork`：系统选择器不提供网络下载设置。
- `videoExportPreset`、`videoQuality`：系统相机和图库选择器不提供视频导出或录像质量设置。

#### `ImagePickerResult`

`ImagePickerSuccessResult | ImagePickerCanceledResult`。

#### `ImagePickerSuccessResult`

成功结果，`canceled` 为 `false`，`assets` 为所选资源数组。

#### `MediaLibraryPermissionResponse`

`PermissionResponse` 加上 `accessPrivileges`。HarmonyOS 上该值为 `'all'` 或 `'none'`，不会是 `'limited'`；它表示图库选择器是否可用，不代表应用获得了整个图库的访问权限。

#### `MediaType`

可选媒体类型：`'images' | 'videos' | 'livePhotos'`。仅请求动态照片且未开启编辑时，图库结果可包含封面和配对视频。系统相机返回普通图片或视频。

#### `PermissionExpiration`

类型为 `'never' | number`。HarmonyOS 权限响应中的值为 `'never'`。

#### `PermissionHookOptions`

权限 Hook 选项包含 `get` 和 `request` 布尔值：`get` 默认 `true`，`request` 默认 `false`。`useMediaLibraryPermissions` 另外接受 `writeOnly`，但该参数不影响 HarmonyOS 返回值。

#### `PermissionResponse`

| 属性 | 类型 | HarmonyOS 返回值 |
| --- | --- | --- |
| `status` | `PermissionStatus` | `'granted'` 或 `'denied'`，表示相应系统选择器是否可用。 |
| `granted` | `boolean` | 选择器可用时为 `true`。 |
| `canAskAgain` | `boolean` | 与选择器是否可用相同。 |
| `expires` | `PermissionExpiration` | `'never'`。 |

### Enums

#### `CameraType`

- `back`：后置摄像头。
- `front`：前置摄像头。

#### `MediaTypeOptions`

已弃用的媒体类型枚举，传入时会转换为对应的媒体类型数组：`All` 为 `['images', 'videos']`，`Images` 为 `['images']`，`Videos` 为 `['videos']`。

#### `PermissionStatus`

- `GRANTED` (`'granted'`)：系统选择器可用。
- `DENIED` (`'denied'`)：系统选择器不可用。
- `UNDETERMINED` (`'undetermined'`)：枚举保留该值，HarmonyOS 查询不会返回该状态。

#### `VideoExportPreset`

- HarmonyOS 系统选择器不提供视频导出预设。

#### `UIImagePickerControllerQualityType`

- HarmonyOS 系统相机不提供该录像质量设置。

#### `UIImagePickerPreferredAssetRepresentationMode`

- HarmonyOS 系统图库选择器自行决定资源表示方式。

#### `UIImagePickerPresentationStyle`

- HarmonyOS 系统决定选择器界面的显示样式。

### Error codes

#### `ERR_INVALID_ARGUMENT`

选项类型或取值不符合要求时抛出，例如质量超出 0 到 1、选择数量不是非负整数、媒体类型无效，或视频时长超出支持范围。

#### `ERR_IMAGE_PICKER_UNAVAILABLE`

系统相机或图库选择器不可用，或设备缺少读取视频信息的能力时抛出。

#### `ERR_IMAGE_PICKER_CONTEXT`

应用不在前台、没有可显示界面，或选择器运行所需的应用上下文不可用时抛出。

#### `ERR_IMAGE_PICKER_UNSUPPORTED_EDITING`

单选图片开启编辑后，又请求拍照、固定比例裁剪或椭圆裁剪时抛出。

#### `ERR_IMAGE_PICKER_CAMERA`

系统相机没有返回可用的拍摄结果时抛出。

#### `ERR_IMAGE_PICKER_CAPTURE_FILE`

无法准备相机拍摄文件时抛出。

#### `ERR_IMAGE_PICKER_MEDIA_PROCESSING`

图片或视频无法读取、编码或处理时抛出。

#### `ERR_IMAGE_PICKER_FILE_READ`

媒体文件大小无效或文件读取不完整时抛出。

#### `ERR_IMAGE_PICKER_CACHE`

应用缓存路径不可用时抛出。

#### `ERR_IMAGE_PICKER_MEDIA_TYPE`

所选资源既不是图片也不是视频时抛出。

#### `ERR_IMAGE_PICKER`

其他未归类的选择或拍摄错误时抛出。

### Permissions

#### `ohos.permission.MEDIA_LOCATION`

系统图库选择器只向应用提供用户选中的资源，不需要申请整个图库的读写权限。若需读取所选照片 EXIF 中的 GPS 信息，需要声明并申请 `ohos.permission.MEDIA_LOCATION`。详见[HarmonyOS 受限权限说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions)。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
