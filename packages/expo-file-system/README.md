# @expo-harmony/expo-file-system

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-file-system) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/filesystem/)

为 HarmonyOS 上的 React Native 应用提供 Expo FileSystem 的原生实现，与官方同版本的 `expo-file-system` 配套使用。

## 安装

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 21（HarmonyOS 6.0.1）。

```bash
npm install @expo-harmony/expo-file-system expo-file-system
```

## API 对照表

现代 API 从 `expo-file-system` 导入；Legacy API 从 `expo-file-system/legacy` 导入。

### Constants

#### `documentDirectory`

Legacy 常量，类型为 `string`，返回以 `file://` 开头、以 `/` 结尾的应用文档目录地址。

#### `cacheDirectory`

Legacy 常量，类型为 `string`，返回以 `file://` 开头、以 `/` 结尾的应用缓存目录地址。

#### `bundleDirectory`

Legacy 常量，类型为 `string`，返回 `rawfile:///` 打包资源目录地址。

#### `DEFAULT_DEBOUNCE_MS`

值为 `100`，单位毫秒，是文件变更订阅的默认防抖间隔。

### Methods

#### `new Directory(...uris)`

接受路径字符串、`File` 或 `Directory`，返回目录引用。路径可以尚不存在；打包资源目录可读，不可写。

#### `Directory.create(options?)`

创建目录，返回 `void`。`intermediates` 默认 `false`，为 `true` 时创建缺失的父目录。目标已存在时，`idempotent` 为 `true` 可静默返回；否则 `overwrite` 为 `true` 时保留目录内容并返回；两者都不是 `true` 时抛错。

#### `Directory.createDirectory(name)`

在目录下创建子目录并返回 `Directory`。`name` 不能是空字符串、`.` 或 `..`，也不能含路径分隔符或空字符；目标已存在时抛错。

#### `Directory.createFile(name, mimeType)`

在目录下创建空文件并返回 `File`。`mimeType` 不影响创建结果；目标已存在时抛错。

#### `Directory.copy(destination, options?)`

复制目录，返回 `Promise<void>`。`destination` 为目录时复制为其中的同名子目录，否则复制到该路径；目标为 `File`、源目标重叠或目标位于源目录内部时抛错。`options.overwrite` 默认为 `false`，为 `true` 时替换已有目标。

#### `Directory.copySync(destination, options?)`

同步复制目录，参数和目标处理规则与 `Directory.copy()` 相同。

#### `Directory.move(destination, options?)`

移动目录，返回 `Promise<void>`，成功后更新 `uri`。`destination` 为已存在目录时移入并保留原目录名，否则移至指定路径。目标为 `File` 或在未开启覆盖时目标已存在时抛错。`options.overwrite` 默认为 `false`。

#### `Directory.moveSync(destination, options?)`

同步移动目录，参数和目标处理规则与 `Directory.move()` 相同，成功后更新 `uri`。

#### `Directory.rename(newName)`

在当前父目录内重命名目录，成功后更新 `uri`。目标名称已存在时抛错。

#### `Directory.delete()`

删除目录及其全部内容。目录不存在或无法删除时抛错。

#### `Directory.info()`

返回 `DirectoryInfo`。`files` 为直接子项名称数组，`size` 为目录内文件大小总和，`modificationTime` 单位为毫秒。HarmonyOS 不提供目录创建时间，`creationTime` 为 `null`。

#### `Directory.list()`

返回目录中的 `File` 和 `Directory` 实例数组。目录不存在或不可读取时抛错。

#### `Directory.pickDirectoryAsync(initialUri?)`

打开系统目录选择器，返回 `Promise<Directory>`。`initialUri` 指定初始目录。默认使用临时授权；需要在应用重启后继续访问时见 `ohos.permission.FILE_ACCESS_PERSIST`。用户取消时 Promise 拒绝；设备不支持系统目录选择能力时抛错。

#### `new File(...uris)`

接受路径字符串、`File` 或 `Directory`，返回文件引用。路径可以尚不存在。支持应用沙箱路径、系统选择器授权的文件地址和打包资源地址；打包资源只读。

#### `File.create(options?)`

创建空文件，返回 `void`。`intermediates` 默认 `false`，为 `true` 时创建缺失的父目录。`overwrite` 默认为 `false`；为 `true` 时替换已有文件。路径指向目录时抛错。

#### `File.write(content, options?)`

写入字符串或 `Uint8Array`，返回 `void`。字符串默认按 UTF-8 编码，也可用 `encoding: 'base64'`；`append: true` 时追加。`Uint8Array` 按字节写入。

#### `File.text()`

按 UTF-8 读取文件，返回 `Promise<string>`。

#### `File.textSync()`

按 UTF-8 同步读取文件，返回 `string`。

#### `File.base64()`

读取全部文件内容并编码为 Base64，返回 `Promise<string>`。

#### `File.base64Sync()`

同步读取全部文件内容并编码为 Base64，返回 `string`。

#### `File.bytes()`

读取全部文件内容，返回 `Promise<Uint8Array>`。

#### `File.bytesSync()`

同步读取全部文件内容，返回 `Uint8Array`。

#### `File.arrayBuffer()`

读取全部文件内容，返回 `Promise<ArrayBuffer>`。

#### `File.json()`

将文件按 UTF-8 读取并解析为 JSON，返回 `Promise<any>`。内容不是有效 JSON 时拒绝。

#### `File.formData()`

按文件的 MIME 类型解析表单内容，返回 `Promise<FormData>`。

#### `File.info(options?)`

返回 `FileInfo`。`options.md5` 为 `true` 时包含 MD5。`modificationTime` 单位为毫秒；HarmonyOS 不提供文件创建时间，`creationTime` 为 `null`。路径指向目录时抛错。

#### `File.copy(destination, options?)`

复制文件，返回 `Promise<void>`。`destination` 为目录时复制为其中的同名文件，否则复制到该路径。`options.overwrite` 默认为 `false`，为 `true` 时替换已有目标。

#### `File.copySync(destination, options?)`

同步复制文件，参数和目标处理规则与 `File.copy()` 相同。

#### `File.move(destination, options?)`

移动文件，返回 `Promise<void>`。`destination` 为目录时移入并保留文件名，否则移至指定路径；成功后更新 `uri`。`options.overwrite` 默认为 `false`，为 `true` 时替换已有目标。

#### `File.moveSync(destination, options?)`

同步移动文件，参数和目标处理规则与 `File.move()` 相同，成功后更新 `uri`。

#### `File.rename(newName)`

在当前父目录内重命名文件，成功后更新 `uri`。目标名称已存在时抛错。

#### `File.delete()`

删除文件。文件不存在或无法删除时抛错。

#### `File.open(mode?)`

打开已存在的文件并返回 `FileHandle`。本地文件默认 `FileMode.ReadWrite`；系统选择器返回的文件地址默认 `FileMode.ReadOnly`。

#### `File.readableStream()`

返回 `ReadableStream<Uint8Array>`，供分块读取文件内容。

#### `File.stream()`

返回与 `File.readableStream()` 相同的可读流。

#### `File.writableStream()`

返回 `WritableStream<Uint8Array>`，从文件开头写入。

#### `File.slice(start?, end?, contentType?)`

返回包含所选字节区间的 `Blob`。

#### `File.downloadFileAsync(url, destination, options?)`

静态方法，下载文件并返回 `Promise<File>`。`destination` 为目录时，文件名由响应头或 URL 确定。目标已存在时默认拒绝；`options.idempotent: true` 时覆盖。HTTP 非 2xx 状态时拒绝。`options.onProgress` 接收 `{ bytesWritten, totalBytes }`；`options.signal` 可取消下载，取消时以 `AbortError` 拒绝。`url` 也可指向打包资源。

#### `File.pickFileAsync(options?)`

静态方法，打开系统文件选择器。`initialUri` 指定初始位置；`mimeTypes` 接受 MIME 字符串或字符串数组，`'*/*'` 表示不筛选；`multipleFiles` 默认为 `false`。默认使用临时授权；需要在应用重启后继续访问时见 `ohos.permission.FILE_ACCESS_PERSIST`。成功时返回 `{ result: File | File[], canceled: false }`；取消时返回 `{ result: null, canceled: true }`。系统无法识别的 MIME 类型可能导致选择失败。

#### `File.pickFileAsync(initialUri?, mimeType?)`

兼容旧签名，返回所选 `File` 或 `File[]`；取消时 Promise 拒绝。

#### `File.upload(url, options?)`

立即上传文件，返回 `Promise<UploadResult>`。支持 `POST`、`PUT`、`PATCH`、请求头、二进制或 multipart、文件字段名、MIME 类型、额外表单字段、进度回调和取消信号；上传类型默认二进制。HTTP 非 2xx 响应仍返回响应正文、状态码和响应头；传输失败、文件不可读或取消时拒绝。取消信号触发时以 `AbortError` 拒绝。

#### `File.createUploadTask(url, options?)`

创建尚未启动的 `UploadTask`。

#### `File.createDownloadTask(url, destination, options?)`

静态方法，创建尚未启动的 `DownloadTask`。`destination` 可为文件或目录。

#### `new UploadTask(file, url, options?)`

创建尚未启动的上传任务。

#### `UploadTask.uploadAsync()`

启动上传并返回 `Promise<UploadResult>`。HTTP 非 2xx 响应也会作为结果返回。

#### `UploadTask.cancel()`

取消尚未完成的上传；进行中的 `uploadAsync()` 会因取消而拒绝。

#### `UploadTask.release()`

释放上传任务句柄。

#### `new DownloadTask(url, destination, options?)`

创建尚未启动的下载任务。`destination` 可为文件或目录。

#### `DownloadTask.downloadAsync()`

启动下载并返回 `Promise<File | null>`。下载完成时返回 `File`；暂停时返回 `null`。

#### `DownloadTask.pause()`

请求暂停进行中的下载。

#### `DownloadTask.pauseAsync()`

请求暂停并等待任务进入暂停状态，返回 `Promise<void>`。

#### `DownloadTask.resumeAsync()`

从暂停位置继续下载，返回 `Promise<File | null>`；再次暂停时返回 `null`。

#### `DownloadTask.cancel()`

取消尚未完成的下载；进行中的下载 Promise 会因取消而拒绝。

#### `DownloadTask.savable()`

任务暂停时返回可保存的 `DownloadPauseState`。

#### `DownloadTask.fromSavable(state, options?)`

根据保存状态创建处于暂停状态的 `DownloadTask`。没有有效续传数据时抛错。

#### `DownloadTask.release()`

释放下载任务句柄。

#### `Paths.info(...uris)`

返回 `PathInfo`，指出路径是否存在及是否为目录。路径不存在或超出可访问范围时，`exists` 为 `false`，`isDirectory` 为 `null`。

#### `Paths.join(...paths)`

拼接路径，参数可为字符串、`File` 或 `Directory`，返回 `string`。

#### `Paths.relative(from, to)`

返回 `to` 相对 `from` 的路径字符串。参数可为字符串、`File` 或 `Directory`。

#### `Paths.isAbsolute(path)`

判断路径是否为绝对路径，返回 `boolean`。

#### `Paths.normalize(path)`

规范化路径，返回 `string`。

#### `Paths.dirname(path)`

返回路径的父目录字符串。

#### `Paths.basename(path, ext?)`

返回路径的末级名称；提供 `ext` 时移除匹配的后缀。

#### `Paths.extname(path)`

返回路径的扩展名。

#### `Paths.parse(path)`

将路径拆分为 `root`、`dir`、`base`、`ext` 和 `name`。

#### `FileHandle.readBytes(length)`

从当前偏移读取最多 `length` 个字节，返回 `Uint8Array`；到达文件末尾时返回实际读取长度。

#### `FileHandle.writeBytes(bytes)`

从当前偏移写入 `Uint8Array`。

#### `FileHandle.close()`

关闭文件句柄；关闭后再次读写会抛错。

#### `getInfoAsync(fileUri, options?)`

Legacy 方法，返回 `Promise<FileInfo>`。`options.md5` 为 `true` 时包含 MD5；`modificationTime` 单位为秒。

#### `readAsStringAsync(fileUri, options?)`

Legacy 方法，按 `encoding` 读取文件，默认 UTF-8，也可指定 Base64。`position` 和 `length` 按字节计。

#### `writeAsStringAsync(fileUri, contents, options?)`

Legacy 方法，按 `encoding` 写入字符串，默认 UTF-8，也可指定 Base64；`append: true` 时追加。

#### `deleteAsync(fileUri, options?)`

Legacy 方法，删除文件或目录。`idempotent: true` 时，路径不存在也不报错。

#### `moveAsync({ from, to })`

Legacy 方法，移动文件或目录。打包资源不可移动。

#### `copyAsync({ from, to })`

Legacy 方法，复制文件或目录；目标存在时覆盖。可将打包资源或系统选择器授权的文件复制到应用沙箱。系统授权 URI 指向的目录不支持复制。

#### `makeDirectoryAsync(fileUri, options?)`

Legacy 方法，新建目录。`intermediates: true` 时创建缺失的父目录；目标已存在且为目录时不报错。

#### `readDirectoryAsync(fileUri)`

Legacy 方法，返回 `Promise<string[]>`，内容为目录中的条目名称。

#### `getTotalDiskCapacityAsync()`

Legacy 方法，返回设备存储总容量，单位为字节。

#### `getFreeDiskStorageAsync()`

Legacy 方法，返回设备存储可用容量，单位为字节。

#### `getContentUriAsync(fileUri)`

Legacy 方法，返回对应的 `file://` 地址；系统选择器授权的文件 URI 会保留其系统地址。HarmonyOS 不生成 `content://` 地址。

#### `downloadAsync(uri, fileUri, options?)`

Legacy 方法，将资源下载到指定文件，返回 `Promise<FileSystemDownloadResult>`。`options.headers` 设置请求头；目标已存在时覆盖；`options.md5: true` 时结果包含 MD5。HTTP 非 2xx 响应仍以 `status` 返回，不拒绝 Promise。

#### `uploadAsync(url, fileUri, options?)`

Legacy 方法，上传文件并返回 `Promise<FileSystemUploadResult>`。`uploadType` 可为 `BINARY_CONTENT`（`0`）或 `MULTIPART`（`1`）；`httpMethod` 可为 `POST`、`PUT`、`PATCH`，默认 `POST`。HTTP 非 2xx 响应仍返回结果。

#### `createDownloadResumable(uri, fileUri, options?, callback?, resumeData?)`

创建 `DownloadResumable`。调用 `downloadAsync()` 开始下载；`pauseAsync()` 暂停并返回可保存状态；`resumeAsync()` 从状态续传；`cancelAsync()` 取消。进度回调接收 `DownloadProgressData`。

#### `createUploadTask(url, fileUri, options?, callback?)`

创建 `UploadTask`。调用 `uploadAsync()` 开始上传，`cancelAsync()` 取消。进度回调接收 `UploadProgressData`。

#### `UploadTask.uploadAsync()`（Legacy）

开始 Legacy 上传任务，返回 `Promise<FileSystemUploadResult | null | undefined>`。

#### `DownloadResumable.downloadAsync()`

开始或继续 Legacy 下载任务，返回 `Promise<FileSystemDownloadResult | null | undefined>`。

#### `DownloadResumable.pauseAsync()`

暂停 Legacy 下载任务，返回可保存的 `DownloadPauseState`。

#### `DownloadResumable.resumeAsync()`

从暂停状态继续 Legacy 下载任务，返回 `Promise<FileSystemDownloadResult | null | undefined>`。

#### `DownloadResumable.savable()`

返回包含下载地址、目标地址、选项及续传数据的状态对象。

#### `FileSystemCancellableNetworkTask.cancelAsync()`

取消 Legacy 上传或下载任务，返回 `Promise<void>`。

#### `StorageAccessFramework.requestDirectoryPermissionsAsync(initialUri?)`

打开系统目录选择器并返回 `Promise<FileSystemRequestDirectoryPermissionsResult>`。默认使用临时授权；需要在应用重启后继续访问时见 `ohos.permission.FILE_ACCESS_PERSIST`。成功时结果包含 `directoryUri`；用户取消时 `granted` 为 `false`。

#### `StorageAccessFramework.readAsStringAsync(fileUri, options?)`

Legacy `readAsStringAsync()` 的别名，参数和返回行为相同。

#### `StorageAccessFramework.writeAsStringAsync(fileUri, contents, options?)`

Legacy `writeAsStringAsync()` 的别名，参数和返回行为相同。

#### `StorageAccessFramework.deleteAsync(fileUri, options?)`

Legacy `deleteAsync()` 的别名，参数和返回行为相同。

#### `StorageAccessFramework.moveAsync({ from, to })`

Legacy `moveAsync()` 的别名，参数和返回行为相同。

#### `StorageAccessFramework.copyAsync({ from, to })`

Legacy `copyAsync()` 的别名，参数和返回行为相同。

#### `StorageAccessFramework.readDirectoryAsync(dirUri)`

返回 `Promise<string[]>`，内容为目录子项的 `file://` 地址；目录地址以 `/` 结尾。

#### `StorageAccessFramework.makeDirectoryAsync(parentUri, dirName)`

在指定目录下创建子目录，返回其 `file://` 地址。

#### `StorageAccessFramework.createFileAsync(parentUri, fileName, mimeType)`

在指定目录下创建空文件并返回其 `file://` 地址。`fileName` 不含扩展名时，按 MIME 类型补充扩展名。

#### `StorageAccessFramework.getUriForDirectoryInRoot(folderName)`

- HarmonyOS 不提供根目录访问接口；该方法返回的 `content://` 地址不能用于本包的文件访问。

#### `deleteLegacyDocumentDirectoryAndroid()`

- HarmonyOS 上不执行操作。

### Event subscriptions

#### `File.watch(callback, options?)`

订阅文件变更，返回带 `remove()` 的 `WatchSubscription`。回调收到 `created`、`modified`、`deleted` 或 `renamed` 事件。`options.debounce` 默认 100 毫秒；`options.events` 可筛选事件。监听范围限于应用可访问且系统允许监听的路径；文件被删除或重命名时订阅自动停止。

#### `Directory.watch(callback, options?)`

订阅目录及其直接子项变更，返回带 `remove()` 的 `WatchSubscription`。事件类型和筛选选项与 `File.watch()` 相同；目录被删除或移动时订阅自动停止。重命名事件在可关联时包含 `newTarget`。

#### `UploadTask.addListener('progress', listener)`

订阅上传进度，回调参数为 `UploadProgress`，返回可调用 `remove()` 的订阅。

#### `DownloadTask.addListener('progress', listener)`

订阅下载进度，回调参数为 `DownloadProgress`，返回可调用 `remove()` 的订阅。

### Types

#### `Directory`

目录引用类型。构造时接受路径片段，首段可为 `File` 或 `Directory`；`uri` 指向目录地址。

#### `Directory.uri`

只读 `string`。目录移动或重命名成功后更新。

#### `Directory.exists`

只读 `boolean`，表示目录是否存在且可访问。

#### `Directory.size`

只读 `number | null`，为目录内文件大小总和；目录不存在或无法读取时为 `null`。

#### `Directory.name`

只读 `string`，目录名称。

#### `Directory.parentDirectory`

只读 `Directory`，上级目录。

#### `File`

文件引用类型，实现 `Blob` 接口。构造时接受路径片段，首段可为 `File` 或 `Directory`。

#### `File.uri`

只读 `string`。文件移动或重命名成功后更新。

#### `File.exists`

只读 `boolean`。打包资源地址可用于查询是否存在。

#### `File.size`

只读 `number`，单位字节；文件不存在或不可读时为 `0`。

#### `File.md5`

只读 `string | null`；文件不存在或不可读时为 `null`。

#### `File.lastModified`

只读 `number | null`，最后修改时间，单位毫秒；文件不存在或不可读时为 `null`。

#### `File.modificationTime`

只读 `number | null`，最后修改时间，单位毫秒；为 `lastModified` 的废弃别名。

#### `File.creationTime`

只读 `number | null`。HarmonyOS 不提供文件创建时间，始终为 `null`。

#### `File.type`

只读 `string`，按扩展名推断 MIME 类型；无法识别时为空字符串。

#### `File.contentUri`

只读 `string`，返回可访问的 `file://` 地址；系统选择器授权的文件保留系统返回的 URI。HarmonyOS 不使用 `content://`。

#### `File.name`

只读 `string`，文件名称，含扩展名。

#### `File.extension`

只读 `string`，文件扩展名，例如 `.png`。

#### `File.parentDirectory`

只读 `Directory`，文件所在目录。

#### `Paths`

静态路径工具和设备存储信息入口。

#### `Paths.document`

只读 `Directory`，应用文档目录；存储内容不会由系统作为缓存清理。

#### `Paths.cache`

只读 `Directory`，应用缓存目录；存储空间不足时系统可能清理其中内容。

#### `Paths.bundle`

只读 `Directory`，只读打包资源目录，地址为 `rawfile:///`。`asset://path/to/file` 对应打包资源目录下的 `assets/path/to/file`。

#### `Paths.appleSharedContainers`

只读 `Record<string, Directory>`。

- HarmonyOS 不提供共享容器；此属性始终为空对象。

#### `Paths.totalDiskSpace`

只读 `number`，设备存储总容量，单位为字节。

#### `Paths.availableDiskSpace`

只读 `number`，设备存储可用容量，单位为字节。

#### `FileHandle`

由 `File.open()` 返回的文件句柄。

#### `FileHandle.offset`

`number | null`，可读写，单位字节。读写后按实际字节数前进；设为超过文件大小的位置时，后续写入从文件末尾开始。设为 `null` 时保留当前位置；句柄关闭后为 `null`。

#### `FileHandle.size`

只读 `number | null`，文件大小，单位字节；句柄关闭后为 `null`。

#### `UploadTask`

上传任务类型。

#### `UploadTask.state`

只读 `UploadTaskState`。

#### `DownloadTask`

下载任务类型。

#### `DownloadTask.state`

只读 `DownloadTaskState`。

#### `DownloadResumable`

Legacy 可暂停下载任务类型，提供暂停、继续、取消和保存状态的方法。

#### `StorageAccessFramework`

Legacy 文件和目录选择器接口。

#### `DirectoryCreateOptions`

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `intermediates` | `boolean` | `false` | 创建缺失的父目录。 |
| `overwrite` | `boolean` | `false` | 目录已存在时视为成功，保留原内容。 |
| `idempotent` | `boolean` | `false` | 目录已存在时静默返回。 |

#### `FileCreateOptions`

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `intermediates` | `boolean` | `false` | 创建缺失的父目录。 |
| `overwrite` | `boolean` | `false` | 用空文件替换已有文件。 |

#### `FileWriteOptions`

- `encoding`：`EncodingType`、`'utf8'` 或 `'base64'`，默认 `'utf8'`。
- `append`：默认 `false`；为 `true` 时追加到文件末尾。

#### `RelocationOptions`

`{ overwrite?: boolean }`。`overwrite` 默认 `false`；为 `true` 时替换已有目标。

#### `InfoOptions`

`{ md5?: boolean }`。`md5` 默认 `false`。

#### `FileInfo`

现代文件信息对象，包含 `exists`、`uri`、`size`、`modificationTime`、`creationTime` 和可选 `md5`。时间单位为毫秒，`creationTime` 在 HarmonyOS 上为 `null`。

#### `DirectoryInfo`

目录信息对象，包含 `exists`、`uri`、`size`、`modificationTime`、`creationTime` 和 `files`。时间单位为毫秒，`creationTime` 在 HarmonyOS 上为 `null`。

#### `PathInfo`

`{ exists: boolean, isDirectory: boolean | null }`。

#### `PickFileGeneralOptions`

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `initialUri` | `string` | — | 选择器初始位置。 |
| `mimeTypes` | 字符串或字符串数组 | — | MIME 类型筛选；`'*/*'` 不筛选。 |
| `multipleFiles` | `boolean` | `false` | 是否允许多选。 |

#### `PickSingleFileOptions`

`PickFileGeneralOptions` 的单选选项，`multipleFiles` 只能省略或设为 `false`。

#### `PickMultipleFilesOptions`

`PickFileGeneralOptions` 的多选选项，`multipleFiles` 必须为 `true`。

#### `PickSingleFileResult`

成功时为 `{ result: File, canceled: false }`；取消时为 `{ result: null, canceled: true }`。

#### `PickMultipleFilesResult`

成功时为 `{ result: File[], canceled: false }`；取消时为 `{ result: null, canceled: true }`。

#### `PickFileCanceledResult`

`{ result: null, canceled: true }`。

#### `PickSingleFileSuccessResult`

`{ result: File, canceled: false }`。

#### `PickMultipleFilesSuccessResult`

`{ result: File[], canceled: false }`。

#### `DownloadOptions`

现代下载选项，包括 `headers?: Record<string, string>`、`idempotent?: boolean`、`onProgress?: (progress: DownloadProgress) => void` 和 `signal?: AbortSignal`。

#### `DownloadProgress`

`{ bytesWritten: number, totalBytes: number }`。未知总量时 `totalBytes` 为 `-1`。

#### `UploadOptions`

现代上传选项包括 `httpMethod`（`POST`、`PUT`、`PATCH`，默认 `POST`）、`uploadType`（默认 `BINARY_CONTENT`）、`headers`、`fieldName`、`mimeType`、`parameters`、`onProgress`、`signal` 和 `sessionType`。`sessionType` 在 HarmonyOS 上不改变任务行为。

#### `UploadProgress`

`{ bytesSent: number, totalBytes: number }`。未知总量时 `totalBytes` 为 `-1`。

#### `UploadResult`

`{ body: string, status: number, headers: Record<string, string> }`。

#### `DownloadTaskOptions`

包含 `headers`、`onProgress`、`signal` 和 `sessionType`。`sessionType` 在 HarmonyOS 上不改变任务行为。

#### `NetworkTaskSessionType`

现代网络任务会话类型：`'background' | 'foreground'`。

- HarmonyOS 上传入该选项不改变文件传输行为。

#### `DownloadPauseState`

现代下载任务的可保存状态，包含 `url`、`fileUri`、`isDirectory`、可选 `headers` 和 `resumeData`。

#### `UploadTaskState`

`'idle' | 'active' | 'completed' | 'cancelled' | 'error'`。

#### `DownloadTaskState`

`'idle' | 'active' | 'paused' | 'completed' | 'cancelled' | 'error'`。

#### `WatchEventType`

`'created' | 'modified' | 'deleted' | 'renamed'`。

#### `WatchEvent<T>`

变更事件，包含 `type`、`target`、可选 `newTarget` 和可选 `nativeEventFlags`。

#### `WatchOptions`

`{ debounce?: number, events?: WatchEventType[] }`。`debounce` 默认 100 毫秒；`events` 用于筛选事件类型。

#### `WatchSubscription`

订阅对象提供 `remove(): void`，用于停止监听。

#### `Legacy FileInfo`

Legacy 文件信息对象。文件存在时包含 `exists`、`uri`、`size`、`isDirectory` 和 `modificationTime`；`modificationTime` 单位为秒，`options.md5` 为 `true` 时包含 `md5`。

#### `FileSystemHttpResult`

Legacy HTTP 响应字段包含 `headers` 和 `status`。

- HarmonyOS 不返回 `mimeType`。

#### `FileSystemDownloadResult`

包含 `uri`、`status`、`headers`，以及请求 MD5 时的 `md5`。

- HarmonyOS 不返回 `mimeType`。

#### `FileSystemUploadResult`

包含 `body`、`status` 和 `headers`。

- HarmonyOS 不返回 `mimeType`。

#### `FileSystemAcceptedUploadHttpMethod`

`'POST' | 'PUT' | 'PATCH'`。

#### `DownloadResult`

Legacy 下载结果类型别名，与 `FileSystemDownloadResult` 相同。

#### `DownloadProgressCallback`

Legacy 下载进度回调类型别名，参数为 `DownloadProgressData`。

#### `FileSystemNetworkTaskProgressCallback<T>`

Legacy 网络任务进度回调，参数为下载或上传进度数据。

#### `FileSystemCancellableNetworkTask<T>`

Legacy 上传和下载任务的基类，提供 `cancelAsync()`。

#### `UploadOptionsBinary`

Legacy 二进制上传选项；`uploadType` 为 `FileSystemUploadType.BINARY_CONTENT` 时使用。

#### `UploadOptionsMultipart`

Legacy multipart 上传选项；`uploadType` 为 `FileSystemUploadType.MULTIPART` 时可包含 `fieldName`、`mimeType` 和 `parameters`。

#### `Legacy DownloadOptions`

包含 `md5`、`headers`、`sessionType` 和 `cache`。

- `sessionType` 和 `cache` 在 HarmonyOS 上不生效。

#### `FileSystemUploadOptions`

Legacy 上传选项，包括 `headers`、`httpMethod`、`uploadType`、`fieldName`、`mimeType` 和 `parameters`。

- `sessionType` 在 HarmonyOS 上不生效。

#### `DownloadProgressData`

Legacy 下载进度对象，包含 `totalBytesWritten` 和 `totalBytesExpectedToWrite`；未知总量时预期字节数为 `-1`。

#### `UploadProgressData`

Legacy 上传进度对象，包含 `totalBytesSent` 和 `totalBytesExpectedToSend`；未知总量时预期字节数为 `-1`。

#### `DownloadPauseState（Legacy）`

包含 `url`、`fileUri`、`options` 和可选 `resumeData`。

#### `DownloadResumable.fileUri`

只读 `string`，下载目标文件地址。

#### `FileSystemRequestDirectoryPermissionsResult`

`{ granted: false }` 或 `{ granted: true, directoryUri: string }`。

#### `ReadingOptions`

包含 `encoding`、`position` 和 `length`。`encoding` 默认为 UTF-8，也可指定 Base64；`position` 和 `length` 均按字节计。

#### `WritingOptions`

包含 `encoding` 和 `append`。`encoding` 默认为 UTF-8，也可指定 Base64；`append` 默认为 `false`。

#### `DeletingOptions`

`{ idempotent?: boolean }`。`idempotent` 默认为 `false`。

#### `RelocatingOptions`

`{ from: string, to: string }`，分别为源地址和目标地址。

#### `MakeDirectoryOptions`

`{ intermediates?: boolean }`。`intermediates` 默认为 `false`。

### Enums

#### `EncodingType`

现代和 Legacy 文件读写编码枚举：`UTF8 = 'utf8'`，`Base64 = 'base64'`。

#### `FileMode`

| 成员 | 值 | 行为 |
| --- | --- | --- |
| `ReadOnly` | `r` | 只读。 |
| `ReadWrite` | `rw` | 读写，从文件开头开始。 |
| `WriteOnly` | `w` | 只写，保留原内容，从文件开头开始。 |
| `Append` | `wa` | 只写，初始位置在文件末尾。 |
| `Truncate` | `wt` | 只写，先清空文件。 |

#### `UploadType`

| 成员 | 值 | 行为 |
| --- | --- | --- |
| `BINARY_CONTENT` | `0` | 文件作为请求体。 |
| `MULTIPART` | `1` | multipart 表单上传。 |

#### `FileSystemUploadType`

Legacy 上传类型枚举：`BINARY_CONTENT = 0` 表示文件作为请求体；`MULTIPART = 1` 表示 multipart 表单上传。

#### `FileSystemSessionType`

- HarmonyOS 不提供前后台会话类型；`BACKGROUND` 和 `FOREGROUND` 不改变文件传输行为。

### Error codes

#### `ERR_DESTINATION_ALREADY_EXISTS`

现代下载目标文件已存在且未设置 `idempotent: true` 时抛出。

#### `ERR_FILE_SYSTEM_DESTINATION_EXISTS`

复制、移动或重命名时目标已存在且未启用覆盖时抛出。

#### `ERR_UNABLE_TO_CREATE`

创建文件或目录时目标已存在且未启用相应覆盖或幂等选项时抛出。

#### `ERR_FILE_SYSTEM_CANNOT_DELETE`

删除的文件或目录不存在时抛出。

#### `ERR_FILE_SYSTEM_DESTINATION`

将目录复制或移动到文件目标时抛出。

#### `ERR_FILE_SYSTEM_OVERLAPPING_PATHS`

复制或移动时源路径与目标路径重叠时抛出。

#### `ERR_FILE_SYSTEM_RECURSIVE_COPY`

将目录复制或移动到自身内部时抛出。

#### `ERR_FILE_SYSTEM_INVALID_NAME`

目录或文件名称为空、含路径分隔符或不符合名称要求时抛出。

#### `ERR_FILE_SYSTEM_INVALID_RESOURCE`

打包资源 URI 或路径格式无效时抛出。

#### `ERR_FILE_SYSTEM_OUTSIDE_SCOPE`

访问的路径超出应用沙箱或系统选择器授权范围时抛出。

#### `ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME`

URI 使用不支持的协议，或对只读打包资源执行写入操作时抛出。

#### `ERR_FILE_SYSTEM_INVALID_URI`

文件 URI 格式无效时抛出。

#### `ERR_FILE_SYSTEM_INVALID_PATH`

路径不是绝对路径，或经过规范化后超出路径根目录时抛出。

#### `ERR_FILE_SYSTEM_INVALID_PICKED_URI`

系统选择结果不是可识别的文件 URI 或无法对应到本地文件路径时抛出。

#### `ERR_FILE_SYSTEM_SYMLINK`

访问路径中包含符号链接时抛出。

#### `ERR_FILE_SYSTEM_FILE_NOT_FOUND`

要求文件或目录必须存在的操作找不到目标时抛出。

#### `ERR_FILE_SYSTEM_INVALID_FILE_TYPE`

文件操作的路径指向目录，或选择的对象不是普通文件时抛出。

#### `ERR_FILE_SYSTEM_INVALID_DIRECTORY_TYPE`

目录操作的路径指向文件时抛出。

#### `ERR_FILE_SYSTEM_INVALID_ENCODING`

读写编码不是 UTF-8 或 Base64 时抛出。

#### `ERR_FILE_SYSTEM_INVALID_BASE64`

Base64 输入格式无效时抛出。

#### `ERR_FILE_SYSTEM_INVALID_MIME_TYPE`

文件选择器的 MIME 类型格式无效时抛出。

#### `ERR_FILE_SYSTEM_UNSUPPORTED_MIME_TYPE`

系统没有可用于筛选该 MIME 类型的文件扩展名时抛出。

#### `ERR_FILE_SYSTEM_INVALID_UPLOAD_TYPE`

Legacy 上传的 `uploadType` 不是 `0` 或 `1` 时抛出。

#### `ERR_FILE_SYSTEM_HTTP_METHOD`

上传方法不是 `POST`、`PUT` 或 `PATCH` 时抛出。

#### `ERR_INVALID_ARGUMENT_TYPE`

选项值类型不符合参数要求时抛出。

#### `ERR_FILE_SYSTEM_INVALID_URL`

下载重定向目标不是 HTTP 或 HTTPS 地址时抛出。

#### `ERR_FILESYSTEM_NETWORK`

网络请求无法完成时抛出。

#### `ERR_FILE_SYSTEM_UPLOAD_FAILED`

上传请求失败时抛出。

#### `ERR_UNABLE_TO_DOWNLOAD`

文件下载失败或响应状态不满足现代下载要求时抛出。

#### `ERR_FILE_SYSTEM_TOO_MANY_REDIRECTS`

下载重定向次数超过上限时抛出。

#### `ERR_FILE_SYSTEM_CANCELLED`

文件下载或上传被取消时抛出。

#### `ERR_FILE_SYSTEM_PICKER_CANCELLED`

用户取消选择文件或目录时抛出；`File.pickFileAsync()` 的选项对象形式会改为返回取消结果。

#### `ERR_FILE_SYSTEM_PICKER_UNAVAILABLE`

当前运行环境没有可用 UIAbility，或设备不支持目录选择能力时抛出。

#### `ERR_PICKING_IN_PROGRESS`

同一 UIAbility 的文件或目录选择器尚未关闭时再次打开选择器，抛出此错误。

#### `ERR_FILE_SYSTEM_INVALID_RESUME_DATA`

下载续传状态与目标路径或已保存数据不匹配时抛出。

#### `ERR_FILE_SYSTEM_INVALID_RESUME_RESPONSE`

服务器返回的数据范围与续传位置不匹配时抛出。

#### `ERR_FILE_SYSTEM_TASK_ALREADY_RUNNING`

同一任务已启动，或同一任务标识已在使用时抛出。

#### `ERR_FILE_SYSTEM_HANDLE_OPEN_FAILED`

文件句柄无法打开时抛出。

#### `ERR_FILE_SYSTEM_HANDLE_READ_ONLY`

只读句柄执行写入时抛出。

#### `ERR_FILE_SYSTEM_HANDLE_WRITE_ONLY`

只写句柄执行读取时抛出。

#### `ERR_FILE_SYSTEM_HANDLE_CLOSED`

文件句柄关闭后再次读写时抛出。

#### `ERR_FILE_SYSTEM_INVALID_OFFSET`

文件句柄偏移量或 Legacy 读取位置不是有效的非负安全整数时抛出。

#### `ERR_FILE_SYSTEM_INVALID_LENGTH`

文件句柄或 Legacy 读取长度不是有效的非负安全整数时抛出。

#### `ERR_FILE_SYSTEM_WATCHER_SETUP`

无法开始文件变更监听时抛出。

### Permissions

#### `ohos.permission.INTERNET`

本包已声明此权限，用于文件下载和上传。

#### `ohos.permission.FILE_ACCESS_PERSIST`

可选权限，需由宿主应用声明。HarmonyOS SDK API 12 起该权限级别为 normal；应用市场发布仍需按华为的[受限权限流程](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions#ohospermissionfile_access_persist)申请。获授权后可在应用重启后继续访问系统选择器授权的文件或目录；未获授权、设备不支持持久授权或文件提供方只允许临时访问时，重启后可能需要用户重新选择。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
