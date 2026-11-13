# @expo-harmony/expo-media-library

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-media-library) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/media-library/)

为 HarmonyOS 上的 React Native 应用提供 Expo Media Library 的原生实现，与官方 `expo-media-library` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-media-library expo-media-library@~57.0.5
```

## API 对照表

### Hooks

#### `usePermissions(options?)`

返回 `[PermissionResponse | null, request, get]`：当前权限状态、申请权限的方法和查询权限的方法。可通过 `options.writeOnly` 仅查询或申请图库写权限；HarmonyOS 不提供部分图库授权，`granularPermissions` 不改变申请范围。

### Constants

#### `MediaType`（旧版 API）

从 `expo-media-library/legacy` 导入。HarmonyOS 的运行时取值为 `audio`、`photo`、`video`、`unknown` 和 `all`。图库只包含图片和视频；`audio` 与 `unknown` 不会匹配到资源。

#### `SortBy`（旧版 API）

从 `expo-media-library/legacy` 导入。排序键为 `default`、`mediaType`、`width`、`height`、`creationTime`、`modificationTime` 和 `duration`。

### Methods

#### `isAvailableAsync()`

返回 `Promise<boolean>`。设备提供系统图库能力时返回 `true`，否则返回 `false`。

#### `getPermissionsAsync(writeOnly?)`

返回 `Promise<PermissionResponse>`。省略或传入 `false` 时查询图库读权限及已声明的写权限；传入 `true` 时只查询写权限。

#### `requestPermissionsAsync(writeOnly?, granularPermissions?)`

返回 `Promise<PermissionResponse>` 并请求相应权限。传入 `writeOnly: true` 时只申请写权限；`granularPermissions` 在 HarmonyOS 上不生效。权限未在应用中声明时以 `ERR_MEDIA_LIBRARY_PERMISSION_REQUEST` 拒绝。

#### `presentPermissionsPicker(mediaTypes?)`

返回 `Promise<void>`。HarmonyOS 不提供部分图库授权；调用会完成，但不会更改当前授权。

#### `presentPermissionsPickerAsync(mediaTypes?)`（旧版 API）

- HarmonyOS 不提供部分图库授权选择器，此旧版入口不可用。

#### `Asset(id)`

用系统图库资源 URI 创建资源对象。返回的 `Asset.id` 和 `Asset.getUri()` 均为系统媒体 URI。

#### `Asset.getCreationTime()`

返回 `Promise<number | null>`，单位为 Unix 纪元以来的毫秒。系统没有拍摄时间时返回 `null`。

#### `Asset.getModificationTime()`

返回 `Promise<number | null>`，单位为 Unix 纪元以来的毫秒。系统没有修改时间时返回 `null`。

#### `Asset.getDuration()`

返回 `Promise<number | null>`，视频时长单位为毫秒；图片或时长不可用时返回 `null`。

#### `Asset.getFilename()`

返回 `Promise<string>`，即图库显示的文件名。

#### `Asset.getMediaType()`

返回 `Promise<MediaType>`。HarmonyOS 返回 `image`、`video` 或 `unknown`。

#### `Asset.getUri()`

返回 `Promise<string>`，即系统媒体 URI。

#### `Asset.getWidth()`

返回 `Promise<number>`，单位为像素，按图片方向校正。尺寸无法读取时以 `ERR_MEDIA_LIBRARY_ASSET_PROPERTY` 拒绝。

#### `Asset.getHeight()`

返回 `Promise<number>`，单位为像素，按图片方向校正。尺寸无法读取时以 `ERR_MEDIA_LIBRARY_ASSET_PROPERTY` 拒绝。

#### `Asset.getShape()`

返回 `Promise<Shape | null>`。宽或高不可用时返回 `null`；可用时返回按图片方向校正后的尺寸。

#### `Asset.getInfo()`

返回 `Promise<AssetInfo>`，包含资源标识、文件名、媒体类型、尺寸、时长、创建和修改时间及收藏状态。尺寸不可读取时以 `ERR_MEDIA_LIBRARY_ASSET_PROPERTY` 拒绝；没有系统时间值时，相应字段为 `null`。

#### `Asset.getExif()`

返回 `Promise<object>`。图片可读取的 EXIF 字段由 HarmonyOS 图像框架提供；没有可读 EXIF 时返回空对象。未获 GPS 位置权限时，返回内容不包含 GPS 字段。

#### `Asset.getLocation()`

返回 `Promise<Location | null>`。读取 GPS 位置需授予 `ohos.permission.MEDIA_LOCATION`；未授权、资源没有 GPS 数据或位置不可读时返回 `null`。

#### `Asset.getFavorite()`

返回 `Promise<boolean>`，读取图库中的收藏状态。

#### `Asset.setFavorite(isFavorite)`

返回 `Promise<void>`，设置或取消收藏，需要读写图库权限。仅 HarmonyOS SDK API 26 及以上支持；较低版本以 `ERR_MEDIA_LIBRARY_UNAVAILABLE` 拒绝。

#### `Asset.getAlbums()`

返回 `Promise<Album[]>`，列出该资源所属的用户相册。需要图库读权限。

#### `Asset.create(uri, album?)`

返回 `Promise<Asset>`，将本地图片或视频保存到图库。文件须存在、可读且带有图片或视频扩展名。未指定相册且没有写权限时，系统会在应用前台显示保存确认；用户取消时以 `ERR_MEDIA_LIBRARY_SAVE_CANCELED` 拒绝。指定相册时需要读写权限，且相册必须是用户相册。

#### `Asset.delete()`

删除单项资源，返回 `Promise<void>`，需要写权限并由系统确认。

#### `Asset.delete(assets)`

删除多项资源，返回 `Promise<void>`，需要写权限并由系统确认。每次确认最多处理 300 项；分批删除时，已完成的删除不会回滚。

#### `Asset.getMediaSubtypes()`

- HarmonyOS 不提供媒体子类型信息，此方法不可用。

#### `Asset.getLivePhotoVideoUri()`

- HarmonyOS 不提供 Live Photo 配对视频，此方法不可用。

#### `Asset.getIsInCloud()`

- HarmonyOS 不提供云端资源状态，此方法不可用。

#### `Asset.getOrientation()`

- HarmonyOS 不提供该方向元数据；读取尺寸时已按方向校正，此方法不可用。

#### `Album(id)`

用系统相册 URI 创建相册对象。返回的 `Album.id` 是系统相册 URI。

#### `Album.getTitle()`

返回 `Promise<string>`，即相册名称。

#### `Album.getAssets()`

返回 `Promise<Asset[]>`，列出相册内资源。

#### `Album.add(assets)`

将一个或多个资源加入用户相册，返回 `Promise<void>`，需要读写权限。系统相册为只读。

#### `Album.removeAssets(assets)`

将资源移出用户相册但保留在图库，返回 `Promise<void>`，需要读写权限。系统相册为只读。

#### `Album.get(title)`

按名称查询用户相册，返回 `Promise<Album | null>`。找不到时返回 `null`；系统相册不参与匹配。

#### `Album.getAll()`

返回 `Promise<Album[]>`，列出用户相册，不包含系统相册。

#### `Album.create(name, assetsRefs, moveAssets?)`

- HarmonyOS 不向第三方应用开放创建相册的能力；调用以 `ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION` 拒绝。

#### `Album.delete(albums, deleteAssets?)`

- HarmonyOS 不向第三方应用开放删除相册的能力；调用以 `ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION` 拒绝。

#### `album.delete()`

- HarmonyOS 不向第三方应用开放删除相册的能力；调用以 `ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION` 拒绝。

#### `Query()`

创建资源查询对象。筛选条件按 AND 组合；多次调用 `orderBy()` 时，排序按调用顺序应用。

#### `Query.eq(field, value)`

筛选字段等于指定值，返回当前查询对象。媒体类型使用 `MediaType` 的 `image`、`video`、`audio` 或 `unknown` 值；收藏字段使用布尔值，其他字段使用安全整数。

#### `Query.within(field, values)`

筛选字段值属于指定数组，返回当前查询对象。媒体类型为 `audio` 或 `unknown` 时不会匹配资源。

#### `Query.gt(field, value)`

按大于筛选数值字段，返回当前查询对象。时间字段的值为毫秒；数值参数须为安全整数。

#### `Query.gte(field, value)`

按大于等于筛选数值字段，返回当前查询对象。时间字段的值为毫秒；数值参数须为安全整数。

#### `Query.lt(field, value)`

按小于筛选数值字段，返回当前查询对象。时间字段的值为毫秒；数值参数须为安全整数。

#### `Query.lte(field, value)`

按小于等于筛选数值字段，返回当前查询对象。时间字段的值为毫秒；数值参数须为安全整数。

#### `Query.limit(limit)`

设置最多返回的资源数并返回当前查询对象。参数须为非负整数；`limit(0)` 返回空数组。

#### `Query.offset(offset)`

设置跳过的资源数并返回当前查询对象。参数须为非负整数。

#### `Query.orderBy(sort)`

按 `AssetField` 或 `{ key, ascending }` 排序并返回当前查询对象。方向默认为升序。

#### `Query.album(album)`

将查询限定到指定相册并返回当前查询对象。参数为 `Album` 对象。

#### `Query.exe()`

返回 `Promise<Asset[]>`，执行查询并需要图库读权限。

#### `Query.exeForMetadata()`

返回 `Promise<AssetMetadata[]>`，查询轻量资源信息，不读取 EXIF。系统没有记录的尺寸、时长或时间返回 `null`。

#### `getAssetsAsync(assetsOptions?)`（旧版 API）

从 `expo-media-library/legacy` 导入。返回 `Promise<PagedInfo<Asset>>`，默认每页 20 项，需要图库读权限。通过 `after` 传入上一页的 `endCursor`；该标识不属于当前查询结果时以 `ERR_MEDIA_LIBRARY_INVALID_CURSOR` 拒绝。无结果且未传 `after` 时，`endCursor` 为 `null`。

`mediaType` 默认查询图片；可传 `photo`、`video` 或 `all` 查询图库内容。只传 `audio` 或 `unknown` 时返回空页；与图片或视频一起传入时忽略。其他无效取值以 `ERR_MEDIA_LIBRARY_INVALID_MEDIA_TYPE` 拒绝。显式排序键默认降序；`SortBy.default` 使用系统顺序，忽略方向。

`createdAfter`、`createdBefore` 接受日期或毫秒时间戳。API 13 至 22 上的创建时间范围筛选在大型图库中可能较慢。设为 `resolveWithFullInfo: true` 时会读取图片 EXIF；返回的宽高已按方向校正。

#### `getAssetInfoAsync(asset, options?)`（旧版 API）

返回 `Promise<AssetInfo | null>`，读取资源详细信息，需要图库读权限。资源不存在时返回 `null`。`localUri` 为系统媒体 URI；`location` 为 GPS 坐标，需获准 `ohos.permission.MEDIA_LOCATION`，否则为 `null`。`exif` 由 HarmonyOS 图像框架提供，`isFavorite` 表示图库收藏状态。参数 `shouldDownloadFromNetwork` 不生效。

#### `getAlbumsAsync(options?)`（旧版 API）

返回 `Promise<Album[]>`，查询用户相册，需要图库读权限。设置 `includeSmartAlbums: true` 时也返回系统相册，其 `type` 为 `smartAlbum`。

#### `getAlbumAsync(title)`（旧版 API）

返回 `Promise<Album | null>`，按名称查询用户相册，需要图库读权限。系统相册不参与匹配。

#### `createAssetAsync(localUri, album?)`（旧版 API）

返回 `Promise<Asset>`，从本地文件创建资源，需要读写权限。传入相册时，文件须加入已存在的用户相册。文件须可读取且带图片或视频扩展名，否则以 `ERR_MEDIA_LIBRARY_MISSING_EXTENSION`、`ERR_MEDIA_LIBRARY_UNSUPPORTED_MEDIA_TYPE` 或 `ERR_MEDIA_LIBRARY_INVALID_URI` 拒绝。

资源已保存但后续读取信息或加入相册失败时，调用会以 `ERR_MEDIA_LIBRARY_OPERATION` 拒绝，已保存资源不会回滚。

#### `saveToLibraryAsync(localUri)`（旧版 API）

返回 `Promise<void>`，将单个本地图片或视频保存到图库。无写权限时无需预先取得图库写权限，系统会在应用前台显示保存确认；已有写权限时直接保存。文件须带有图片或视频扩展名。

#### `addAssetsToAlbumAsync(assets, album, copy?)`（旧版 API）

返回 `Promise<boolean>`，把资源加入用户相册，需要读写权限。HarmonyOS 不复制资源，`copy` 参数不改变行为。资源或相册不存在时分别以 `ERR_MEDIA_LIBRARY_ASSET_NOT_FOUND` 或 `ERR_MEDIA_LIBRARY_ALBUM_NOT_FOUND` 拒绝；系统相册为只读。传入空资源数组时返回 `true`。

#### `removeAssetsFromAlbumAsync(assets, album)`（旧版 API）

返回 `Promise<boolean>`，把资源移出用户相册但保留在图库，需要读写权限。系统相册为只读；资源或相册不存在时以对应的资源或相册错误拒绝。

#### `deleteAssetsAsync(assets)`（旧版 API）

返回 `Promise<boolean>`，删除图库资源，需要写权限并由系统确认。每次确认最多处理 300 项；分批删除时，已完成的删除不会回滚。

#### `createAlbumAsync(name, asset?, copyAsset?, initialAssetLocalUri?)`（旧版 API）

- HarmonyOS 不向第三方应用开放创建相册的能力；调用以 `ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION` 拒绝。

#### `deleteAlbumsAsync(albums, assetRemove?)`（旧版 API）

- HarmonyOS 不向第三方应用开放删除相册的能力；调用以 `ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION` 拒绝。

#### `getMomentsAsync()`（旧版 API）

- HarmonyOS 不提供 Moments 查询，此方法不可用。

#### `albumNeedsMigrationAsync(album)`（旧版 API）

HarmonyOS 不需要相册迁移；此方法返回 `false`。

#### `migrateAlbumIfNeededAsync(album)`（旧版 API）

HarmonyOS 不需要相册迁移；此方法完成时不做更改。

#### `getAssetContentUriAsync(asset)`（旧版 API）

- HarmonyOS 不提供内容 URI 转换；资源 ID 本身就是系统媒体 URI，此方法不可用。

#### `setAssetFavoriteAsync(asset, isFavorite)`（旧版 API）

- HarmonyOS 不提供此旧版入口；收藏状态可通过 `Asset.setFavorite()` 设置，需 HarmonyOS SDK API 26 及以上。

### Event subscriptions

#### `addListener(listener)`

订阅图库变更，返回 `EventSubscription`，调用返回对象的 `remove()` 取消订阅。没有图库读权限时不会订阅系统变更；事件只在应用前台且存在监听器时触发。事件的 `hasIncrementalChanges` 始终为 `false`，不包含新增、删除或修改资源列表；收到事件后应重新查询图库。

#### `removeSubscription(subscription)`

取消指定的监听器。此旧版方法已废弃，可调用 `subscription.remove()`。

#### `removeAllListeners()`

移除所有图库变更监听器。

### Types

#### `Asset`（旧版 API）

资源包含 `id`、`filename`、`uri`、`mediaType`、`width`、`height`、`creationTime`、`modificationTime` 和 `duration`。HarmonyOS 上的媒体类型为 `photo`、`video` 或 `unknown`；创建时间在缺少拍摄时间时使用入库时间，时长单位为秒，图片时长为 0，宽高按方向校正。

- HarmonyOS 不提供 `mediaSubtypes` 或 `albumId` 字段。

#### `AssetInfo`（旧版 API）

在旧版 `Asset` 字段上增加 `localUri`、`location`、`exif` 和 `isFavorite`。GPS 权限和位置数据缺失时，`location` 为 `null`。

- HarmonyOS 不提供 `isNetworkAsset`、`orientation` 或 `pairedVideoAsset` 字段。

#### `Album`（旧版 API）

包含相册 `id`、`title`、`assetCount` 和 `type`。HarmonyOS 返回的 `type` 为 `album` 或 `smartAlbum`。

- HarmonyOS 不提供 `startTime`、`endTime`、`approximateLocation` 或 `locationNames` 字段。

#### `AssetRef`

类型为 `Asset | string`，可传入资源对象或其标识。

#### `AlbumRef`

类型为 `Album | string`，可传入相册对象或其标识。

#### `AssetsOptions`

旧版资源查询的参数：

- `first`：单页最多返回数量，默认 20。
- `after`：上一页的 `endCursor`。
- `album`：限定查询相册。
- `mediaType`：筛选媒体类型，默认 `photo`。
- `sortBy`：排序键或 `[key, ascending]`；单独传排序键时按降序。
- `createdAfter`、`createdBefore`：创建时间范围，接受日期或毫秒时间戳。
- `resolveWithFullInfo`：是否读取图片 EXIF，默认 `false`。

- HarmonyOS 不提供媒体子类型筛选，`mediaSubtypes` 参数不生效。

#### `AlbumsOptions`

包含 `includeSmartAlbums`，默认 `false`，用于查询时一并返回系统相册。

#### `PagedInfo<T>`

包含当前页 `assets`、`endCursor`、`hasNextPage` 和匹配资源总数 `totalCount`。HarmonyOS 的 `endCursor` 为资源标识。

#### `AssetInfo`（对象 API）

包含 `id`、`filename`、`uri`、`mediaType`、`width`、`height`、`duration`、`creationTime`、`modificationTime` 和 `isFavorite`。没有系统时间或视频时长值时，相应字段为 `null`。

#### `AssetMetadata`

`Query.exeForMetadata()` 的返回类型，包含 `id`、`filename`、`mediaType`、`width`、`height`、`duration`、`creationTime`、`modificationTime` 和 `isFavorite`。无法从系统媒体信息读取的数值字段为 `null`。

#### `Shape`

包含以像素为单位、已按方向校正的 `width` 和 `height`。

#### `Location`

包含以度为单位的 `latitude` 和 `longitude`。

#### `MediaLibraryAssetsChangeEvent`

包含 `hasIncrementalChanges`，HarmonyOS 上始终为 `false`；事件不提供增量资源列表。

#### `MediaLibraryAssetInfoQueryOptions`

包含 `shouldDownloadFromNetwork`，在 HarmonyOS 上不生效。

#### `PermissionResponse`

包含 `status`、`granted`、`canAskAgain`、`expires` 和 `accessPrivileges`。`status` 可为 `granted`、`denied` 或 `undetermined`；`expires` 始终为 `never`，`accessPrivileges` 只能为 `all` 或 `none`。

#### `PermissionStatus`

取值为 `granted | denied | undetermined`。

#### `PermissionExpiration`

取值为 `never | number`，HarmonyOS 上始终为 `never`。

#### `PermissionHookOptions`

权限 Hook 的选项类型。HarmonyOS 支持 `writeOnly`；部分图库授权相关的 `granularPermissions` 不生效。

#### `GranularPermission`

- HarmonyOS 不提供细分图库授权；此参数不会改变权限范围。

#### `MediaTypeFilter`

- HarmonyOS 不提供部分资源授权选择；此参数不会改变权限范围。

#### `MediaTypeValue`

旧版资源媒体类型的联合类型为 `audio | photo | video | unknown | pairedVideo`。HarmonyOS 只返回 `photo`、`video` 和 `unknown`。

#### `MediaTypeObject`

旧版 `MediaType` 常量对象的类型，包含 `audio`、`photo`、`video` 和 `unknown`。

#### `SortByKey`

旧版资源查询可使用的排序键。

#### `SortByObject`

旧版排序常量对象。

#### `SortByValue`

类型为排序键或 `[SortByKey, boolean]` 组合。

#### `AssetFieldValueMap`

定义对象查询字段对应的值类型：时间、尺寸、时长为数值，媒体类型为 `MediaType`，收藏状态为布尔值。

#### `SortDescriptor`

包含排序字段 `key` 和可选方向 `ascending`；省略方向时按升序。

#### `EventSubscription`

监听器订阅对象，可调用 `remove()` 取消。

#### `Subscription`

旧版订阅类型，是 `EventSubscription` 的别名。

### Enums

#### `AssetField`

对象查询可使用的字段：`CREATION_TIME`、`MODIFICATION_TIME`、`MEDIA_TYPE`、`WIDTH`、`HEIGHT`、`DURATION` 和 `IS_FAVORITE`。

#### `MediaType`（对象 API）

枚举值为 `IMAGE`、`VIDEO`、`AUDIO` 和 `UNKNOWN`，对应字符串 `image`、`video`、`audio` 和 `unknown`。HarmonyOS 不提供音频资源，因此音频筛选不会命中资源。

#### `MediaSubtype`

- HarmonyOS 不提供媒体子类型，此枚举对应的筛选或读取能力不可用。

### Error codes

#### `ERR_MEDIA_LIBRARY_PERMISSION_REQUEST`

申请的图库权限未在应用中声明、系统无法发起授权，或签名未获所需受限权限。

#### `ERR_MEDIA_LIBRARY_PERMISSION`

调用需要图库读写权限的 API 时，相应权限尚未获准。

#### `ERR_MEDIA_LIBRARY_UNAVAILABLE`

系统图库能力不可用，或在 HarmonyOS SDK API 26 以下尝试设置收藏状态。

#### `ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION`

尝试创建或删除 HarmonyOS 用户相册，或修改系统只读相册。

#### `ERR_MEDIA_LIBRARY_ALBUM_NOT_FOUND`

指定的相册标识在图库中不存在。

#### `ERR_MEDIA_LIBRARY_ASSET_NOT_FOUND`

指定的资源标识在图库中不存在。

#### `ERR_MEDIA_LIBRARY_INVALID_CURSOR`

分页游标不属于当前查询结果。

#### `ERR_MEDIA_LIBRARY_INVALID_ARGUMENT`

参数类型或取值无效，例如空标识或格式错误的选项。

#### `ERR_MEDIA_LIBRARY_INVALID_QUERY`

对象查询的字段、筛选值、排序方式或分页参数不符合要求。

#### `ERR_MEDIA_LIBRARY_INVALID_MEDIA_TYPE`

旧版查询的媒体类型不受支持。

#### `ERR_MEDIA_LIBRARY_INVALID_SORT`

旧版查询的排序表达式不受支持。

#### `ERR_MEDIA_LIBRARY_ASSET_PROPERTY`

资源没有可读取的宽度或高度。

#### `ERR_MEDIA_LIBRARY_MISSING_EXTENSION`

导入文件没有扩展名。

#### `ERR_MEDIA_LIBRARY_UNSUPPORTED_MEDIA_TYPE`

导入文件不是图片或视频。

#### `ERR_MEDIA_LIBRARY_INVALID_URI`

URI 未指向有效的本地文件。

#### `ERR_MEDIA_LIBRARY_SAVE_CONTEXT`

没有图库写权限时，应用不在前台，无法显示系统保存确认。

#### `ERR_MEDIA_LIBRARY_SAVE_CANCELED`

用户取消系统保存确认。

#### `ERR_MEDIA_LIBRARY_SAVE_IN_PROGRESS`

已有保存确认窗口尚未结束。

#### `ERR_MEDIA_LIBRARY_OPERATION`

HarmonyOS 图库操作失败，或资源保存后无法完成后续读取或相册操作。已提交的资源变更不会自动回滚。

### Permissions

查询或读取图库资源需要受限读权限 `ohos.permission.READ_IMAGEVIDEO`。删除、修改资源及在不使用逐次系统确认时保存媒体需要受限写权限 `ohos.permission.WRITE_IMAGEVIDEO`。这两项受限权限须获得华为审批，并使用包含获批权限的应用签名；应用还须声明相应权限。请求未声明的权限会以 `ERR_MEDIA_LIBRARY_PERMISSION_REQUEST` 拒绝，调用未获准的读写操作会以 `ERR_MEDIA_LIBRARY_PERMISSION` 拒绝。

未指定相册时，保存单个文件可由系统逐次确认，无需预先获准写权限；此确认需要应用处于前台。

读取图片 GPS 位置还需要开放权限 `ohos.permission.MEDIA_LOCATION`。未获授权时，`Asset.getLocation()` 和旧版 `AssetInfo.location` 返回 `null)，其他 EXIF 字段仍可读取。详情见华为的[受限权限说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions#ohospermissionread_imagevideo)、[ImageSource 权限说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-image-imagesource/)和[开放权限说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/permissions-for-all-user/`。

HarmonyOS SDK API 20 及以上可区分尚未申请和已拒绝；API 13 至 19 无法直接区分，首次未授权查询返回 `undetermined`，请求被拒绝后返回 `denied`。系统不允许再次询问时 `canAskAgain` 为 `false`。HarmonyOS 不提供部分图库授权，因此不会返回 `limited`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
