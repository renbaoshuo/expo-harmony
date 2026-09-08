# @expo-harmony/expo-file-system

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-file-system) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/filesystem/)

为 HarmonyOS 上的 React Native 应用提供 Expo FileSystem 的原生实现，与官方同版本的 `expo-file-system` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-file-system expo-file-system@55.0.24
```

HAR 已声明 `ohos.permission.INTERNET` 和 `ohos.permission.FILE_ACCESS_PERSIST`，应用不需要在 `app.json` 中额外配置。

文件操作限定在应用沙箱内：文档目录、缓存目录，以及通过系统选择器授权的路径。路径中出现符号链接时拒绝。

## API 对照表

### Classes

#### `Directory`

目录引用，路径可以不存在。构造时接受若干路径片段，首段可以是 `Directory` 或 `File`。

#### `Directory.uri`

类型：`string`，只读

目录地址，`move()` 或 `rename()` 后会变化。

#### `Directory.exists`

类型：`boolean`，只读

目录是否存在。

#### `Directory.size`

类型：`number | null`，只读

目录大小，为内部所有文件大小之和。目录不存在、无法读取或内部有符号链接时返回 `null`。

#### `Directory.name`

类型：`string`，只读

目录名称。

#### `Directory.parentDirectory`

类型：`Directory`，只读

上级目录。

#### `Directory.create(options?)`

创建当前地址指向的目录。`options` 默认 `{}`。

| 选项            | 默认值  | 说明                               |
| --------------- | ------- | ---------------------------------- |
| `intermediates` | `false` | 创建缺失的父目录                   |
| `overwrite`     | `false` | 目录已存在时视为成功，保留原有内容 |
| `idempotent`    | `false` | 目录已存在时静默返回               |

目录已存在时，`idempotent` 为 `true` 直接返回，否则 `overwrite` 为 `true` 也返回且保留内容，两者都不满足时抛出错误。路径上是同名文件时抛出错误。

#### `Directory.createDirectory(name)`

在目录下新建子目录，返回 `Directory`。`name` 不能为空、不能是 `.` 或 `..`，也不能含 `/`、`\` 或空字符。子目录已存在时抛出错误。

#### `Directory.createFile(name, mimeType)`

在目录下新建空文件，返回 `File`。`mimeType` 不生效，文件已存在时抛出错误。

#### `Directory.copy(destination)`

复制目录。`destination` 是目录时复制到该目录下的同名子目录，否则复制到该路径。目标已存在、源和目标重叠、目标在源内部或 `destination` 为 `File` 时抛出错误。

#### `Directory.move(destination)`

移动目录，成功后更新 `uri`。目标已存在或 `destination` 为 `File` 时抛出错误。跨卷移动时先复制再删除源。

#### `Directory.rename(newName)`

重命名目录，成功后更新 `uri`。新名称已被占用时抛出错误。

#### `Directory.delete()`

删除目录及其全部内容。目录不存在时抛出错误。

#### `Directory.info()`

返回 `DirectoryInfo`。`files` 为目录内条目名称，`size` 为内部文件大小之和，`modificationTime` 单位为毫秒。`creationTime` 恒为 `null`。

#### `Directory.list()`

返回目录内的 `File` 和 `Directory` 实例。目录不存在时抛出错误。

#### `Directory.pickDirectoryAsync(initialUri?)`

静态方法。打开系统目录选择器，返回 `Promise<Directory>`。`initialUri` 指定选择器的起始位置。用户取消时拒绝。选择后模块会尽量持久化授权，应用下次启动时自动恢复。

#### `File`

文件引用，路径可以不存在。构造时接受若干路径片段，首段可以是 `Directory` 或 `File`。实现 `Blob` 接口。打包资源只读，写入、删除、移动等操作会抛出错误。

#### `File.uri`

类型：`string`，只读

文件地址，`move()` 或 `rename()` 后会变化。

#### `File.exists`

类型：`boolean`，只读

文件是否存在。打包资源（`asset://`、`rawfile://`）也可以查询。

#### `File.size`

类型：`number`，只读

文件大小，单位字节。文件不存在或不可读时为 0。

#### `File.md5`

类型：`string | null`，只读

文件的 MD5。文件不存在或不可读时为 `null`。

#### `File.modificationTime`

类型：`number | null`，只读

最后修改时间，单位毫秒。文件不存在或不可读时为 `null`。

#### `File.creationTime`

类型：`number | null`，只读

恒为 `null`，HarmonyOS 没有提供文件的创建时间。

#### `File.type`

类型：`string`，只读

按扩展名推断的 MIME 类型，无法识别时为空字符串。

#### `File.contentUri`

类型：`string`，只读

文件的 `file://` 地址。打包资源会先复制到缓存目录再返回。官方标记为 Android 专属属性，在 HarmonyOS 上可用；HarmonyOS 没有 content URI 概念。

#### `File.name`

类型：`string`，只读

文件名称，含扩展名。

#### `File.extension`

类型：`string`，只读

文件扩展名，如 `.png`。

#### `File.parentDirectory`

类型：`Directory`，只读

上级目录。

#### `File.create(options?)`

创建空文件。`intermediates` 默认 `false`，创建缺失的父目录；`overwrite` 默认 `false`，文件已存在时抛出错误，为 `true` 时删除原文件后重建。路径上是目录时抛出错误。

#### `File.write(content, options?)`

写入内容。`content` 为字符串时按 `encoding` 编码，默认 `utf8`，可取 `base64`；为 `Uint8Array` 时按字节写入。`append` 默认 `false`，为 `true` 时追加到文件末尾。

#### `File.text()`

返回 `Promise<string>`，按 UTF-8 读取全部内容。

#### `File.textSync()`

返回 `string`，按 UTF-8 读取全部内容。

#### `File.base64()`

返回 `Promise<string>`，读取全部内容并编码为 base64。

#### `File.base64Sync()`

返回 `string`，读取全部内容并编码为 base64。

#### `File.bytes()`

返回 `Promise<Uint8Array>`，读取全部内容。

#### `File.bytesSync()`

返回 `Uint8Array`，读取全部内容。

#### `File.arrayBuffer()`

返回 `Promise<ArrayBuffer>`，读取全部内容。

#### `File.info(options?)`

返回 `FileInfo`。`options.md5` 为 `true` 时结果包含 `md5`，默认 `false`。`modificationTime` 单位为毫秒，`creationTime` 恒为 `null`。路径上是目录时抛出错误。

#### `File.copy(destination)`

复制文件。`destination` 是目录时复制到该目录下的同名文件，否则复制到该路径。目标已存在时抛出错误。

#### `File.move(destination)`

移动文件，成功后更新 `uri`。目标已存在时抛出错误。

#### `File.rename(newName)`

重命名文件，成功后更新 `uri`。目标已存在时抛出错误。

#### `File.delete()`

删除文件。文件不存在时抛出错误。

#### `File.open()`

以读写方式打开文件，返回 `FileHandle`。文件不存在时抛出错误。

#### `File.readableStream()`

返回 `ReadableStream<Uint8Array>`，按 1 KB 分块读取。

#### `File.stream()`

返回 `ReadableStream<Uint8Array>`，与 `readableStream()` 相同。

#### `File.writableStream()`

返回 `WritableStream<Uint8Array>`，从文件开头写入。

#### `File.slice(start?, end?, contentType?)`

返回 `Blob`，内容为文件字节的切片。会先把整个文件读入内存。

#### `File.downloadFileAsync(url, destination, options?)`

静态方法。下载文件，返回 `Promise<File>`。`destination` 是目录时文件名取自 `Content-Disposition` 或地址末段，没有扩展名时按 `Content-Type` 补全。目标已存在且 `idempotent` 不为 `true` 时拒绝，`idempotent` 为 `true` 时覆盖。响应状态码不在 2xx 范围内时拒绝。`url` 也可以是打包资源地址，此时直接从应用资源复制。

#### `File.pickFileAsync(initialUri?, mimeType?)`

静态方法。打开系统文件选择器，返回 `Promise<File>`。`mimeType` 用于过滤可选文件，省略或传 `*/*` 时不过滤，无法映射到扩展名时抛出错误。用户取消时拒绝。每次只允许选择一个文件。

#### `Paths`

内置目录和路径工具。

#### `Paths.document`

类型：`Directory`，只读

文档目录，不会被系统清理。

#### `Paths.cache`

类型：`Directory`，只读

缓存目录，系统在存储空间不足时可能清理。

#### `Paths.bundle`

类型：`Directory`，只读

打包资源目录，地址为 `asset:///`，只读。

#### `Paths.appleSharedContainers`

类型：`Record<string, Directory>`，只读

恒为空对象。

#### `Paths.totalDiskSpace`

类型：`number`，只读

设备存储总容量，单位字节。

#### `Paths.availableDiskSpace`

类型：`number`，只读

设备存储可用容量，单位字节。

#### `Paths.info(...uris)`

返回 `PathInfo`，表示路径是否存在、是否为目录。路径不存在或在沙箱外时 `exists` 为 `false`，`isDirectory` 为 `null`。

#### `Paths.join(...paths)`

拼接路径片段，参数可以是字符串、`File` 或 `Directory`。

#### `Paths.relative(from, to)`

计算 `to` 相对 `from` 的路径。

#### `Paths.isAbsolute(path)`

判断是否为绝对路径。

#### `Paths.normalize(path)`

规范化路径。

#### `Paths.dirname(path)`

返回上级目录。

#### `Paths.basename(path, ext?)`

返回文件名，`ext` 指定时去掉该后缀。

#### `Paths.extname(path)`

返回扩展名。

#### `Paths.parse(path)`

拆分为 `root`、`dir`、`base`、`ext`、`name`。

#### `FileHandle`

文件句柄，由 `File.open()` 返回，可读写。

#### `FileHandle.offset`

类型：`number | null`，可读写

当前读写位置，单位字节，读写后自动前进。赋值为 `null` 会抛出错误。句柄关闭后为 `null`。

#### `FileHandle.size`

类型：`number | null`，只读

文件大小，单位字节。句柄关闭后为 `null`。

#### `FileHandle.readBytes(length)`

从当前位置读取指定字节数，返回 `Uint8Array`，位置随之前进。读到文件末尾时返回实际读到的字节，可能为空。

#### `FileHandle.writeBytes(bytes)`

从当前位置写入字节，位置随之前进。

#### `FileHandle.close()`

关闭句柄。关闭后再读写会抛出错误。

### Constants

以下常量从 `expo-file-system/legacy` 导入。

#### `documentDirectory`

类型：`string`

文档目录的 `file://` 地址，末尾带 `/`。

#### `cacheDirectory`

类型：`string`

缓存目录的 `file://` 地址，末尾带 `/`。

#### `bundleDirectory`

类型：`string`

打包资源目录的 `file://` 地址，末尾带 `/`。

### Methods

以下方法从 `expo-file-system/legacy` 导入。从 `expo-file-system` 顶层导入的 `getInfoAsync`、`readAsStringAsync` 等同名方法已废弃，调用时抛出错误。

#### `getInfoAsync(fileUri, options?)`

返回 `Promise<FileInfo>`。`modificationTime` 单位为秒，`options.md5` 为 `true` 时包含 `md5`。

#### `readAsStringAsync(fileUri, options?)`

按 `encoding` 读取，默认 `utf8`，可取 `base64`。`position` 和 `length` 只在 `base64` 下生效。支持打包资源地址。

#### `writeAsStringAsync(fileUri, contents, options?)`

按 `encoding` 写入，默认 `utf8`，可取 `base64`。`append` 为 `true` 时追加到末尾。

#### `deleteAsync(fileUri, options?)`

删除文件或目录。`idempotent` 为 `true` 时路径不存在也不报错。

#### `moveAsync({ from, to })`

移动文件或目录。源是打包资源时拒绝。

#### `copyAsync({ from, to })`

复制文件或目录，目标已存在时覆盖。源是打包资源时从应用资源复制。

#### `makeDirectoryAsync(fileUri, options?)`

新建目录。`intermediates` 为 `true` 时创建缺失的父目录，且目标已存在时不报错。

#### `readDirectoryAsync(fileUri)`

返回 `Promise<string[]>`，目录内条目的名称。

#### `getTotalDiskCapacityAsync()`

返回 `Promise<number>`，设备存储总容量，单位字节。

#### `getFreeDiskStorageAsync()`

返回 `Promise<number>`，设备存储可用容量，单位字节。

#### `getContentUriAsync(fileUri)`

HarmonyOS 上直接返回传入的地址。

#### `downloadAsync(uri, fileUri, options?)`

下载到 `fileUri`，返回 `FileSystemDownloadResult`。目标已存在时覆盖，`options.md5` 为 `true` 时结果包含 `md5`。非 2xx 响应不拒绝，状态码在结果的 `status` 中。

#### `uploadAsync(url, fileUri, options?)`

上传文件，返回 `FileSystemUploadResult`。`uploadType` 取 `BINARY_CONTENT`（0）或 `MULTIPART`（1），默认 `BINARY_CONTENT`；`httpMethod` 取 `POST`、`PUT`、`PATCH`，默认 `POST`。

#### `createDownloadResumable(uri, fileUri, options?, callback?, resumeData?)`

返回 `DownloadResumable`。`downloadAsync()` 开始下载，`pauseAsync()` 暂停并返回含 `resumeData` 的状态，`resumeAsync()` 从 `resumeData` 续传，`cancelAsync()` 取消。进度通过 `callback` 上报。

#### `createUploadTask(url, fileUri, options?, callback?)`

返回 `UploadTask`。`uploadAsync()` 开始上传，`cancelAsync()` 取消。进度通过 `callback` 上报。

#### `StorageAccessFramework.requestDirectoryPermissionsAsync(initialUri?)`

打开系统目录选择器，返回 `Promise<FileSystemRequestDirectoryPermissionsResult>`。授权后返回目录地址并尽量持久化。

#### `StorageAccessFramework.readDirectoryAsync(dirUri)`

返回目录内条目的 `file://` 地址，目录条目以 `/` 结尾。

#### `StorageAccessFramework.makeDirectoryAsync(parentUri, dirName)`

新建子目录，返回其地址。

#### `StorageAccessFramework.createFileAsync(parentUri, fileName, mimeType)`

新建空文件，返回其地址。`fileName` 不含扩展名时按 `mimeType` 补全。

> **未实现的内容**
>
> - `deleteLegacyDocumentDirectoryAndroid()`：Android 专属接口，HarmonyOS 上不执行任何操作。
> - `StorageAccessFramework.getUriForDirectoryInRoot(folderName)`：Android 专属接口，返回的地址在 HarmonyOS 上无法使用。

### Types

#### `DirectoryCreateOptions`

| 属性            | 类型      | 说明                               |
| --------------- | --------- | ---------------------------------- |
| `idempotent`    | `boolean` | 目录已存在时静默返回，默认 `false` |
| `intermediates` | `boolean` | 创建缺失的父目录，默认 `false`     |
| `overwrite`     | `boolean` | 目录已存在时视为成功，默认 `false` |

#### `FileCreateOptions`

| 属性            | 类型      | 说明                           |
| --------------- | --------- | ------------------------------ |
| `intermediates` | `boolean` | 创建缺失的父目录，默认 `false` |
| `overwrite`     | `boolean` | 文件已存在时覆盖，默认 `false` |

#### `DownloadOptions`

| 属性         | 类型                     | 说明                           |
| ------------ | ------------------------ | ------------------------------ |
| `headers`    | `Record<string, string>` | 请求头                         |
| `idempotent` | `boolean`                | 目标已存在时覆盖，默认 `false` |

#### `InfoOptions`

| 属性  | 类型      | 说明                         |
| ----- | --------- | ---------------------------- |
| `md5` | `boolean` | 是否返回 `md5`，默认 `false` |

#### `PathInfo`

| 属性          | 类型              | 说明                             |
| ------------- | ----------------- | -------------------------------- |
| `exists`      | `boolean`         | 路径是否存在                     |
| `isDirectory` | `boolean \| null` | 是否为目录，路径不存在时为 `null` |

#### `FileInfo`

| 属性               | 类型             | 说明                   |
| ------------------ | ---------------- | ---------------------- |
| `exists`           | `boolean`        | 文件是否存在           |
| `uri`              | `string`         | 文件地址               |
| `size`             | `number`         | 文件大小，单位字节     |
| `modificationTime` | `number`         | 最后修改时间，单位毫秒 |
| `creationTime`     | `number \| null` | 恒为 `null`            |
| `md5`              | `string`         | 请求 `md5` 时包含      |

#### `DirectoryInfo`

| 属性               | 类型             | 说明                   |
| ------------------ | ---------------- | ---------------------- |
| `exists`           | `boolean`        | 目录是否存在           |
| `uri`              | `string`         | 目录地址               |
| `size`             | `number`         | 目录大小，单位字节     |
| `modificationTime` | `number`         | 最后修改时间，单位毫秒 |
| `creationTime`     | `number \| null` | 恒为 `null`            |
| `files`            | `string[]`       | 目录内条目名称         |

以下为 Legacy 类型。

#### `FileSystemAcceptedUploadHttpMethod`

`'POST' | 'PUT' | 'PATCH'`，默认 `'POST'`。

#### `FileInfo`（Legacy）

| 属性               | 类型      | 说明                 |
| ------------------ | --------- | -------------------- |
| `exists`           | `boolean` | 文件是否存在         |
| `uri`              | `string`  | 文件地址             |
| `size`             | `number`  | 文件大小，单位字节   |
| `isDirectory`      | `boolean` | 是否为目录           |
| `modificationTime` | `number`  | 最后修改时间，单位秒 |
| `md5`              | `string`  | 请求 `md5` 时包含    |

#### `FileSystemDownloadResult`

| 属性      | 类型                     | 说明              |
| --------- | ------------------------ | ----------------- |
| `uri`     | `string`                 | 本地文件地址      |
| `status`  | `number`                 | HTTP 状态码       |
| `headers` | `Record<string, string>` | 响应头            |
| `md5`     | `string`                 | 请求 `md5` 时包含 |

#### `FileSystemUploadResult`

| 属性      | 类型                     | 说明        |
| --------- | ------------------------ | ----------- |
| `body`    | `string`                 | 响应正文    |
| `status`  | `number`                 | HTTP 状态码 |
| `headers` | `Record<string, string>` | 响应头      |

#### `FileSystemUploadOptions`

| 属性         | 类型                                 | 说明                            |
| ------------ | ------------------------------------ | ------------------------------- |
| `headers`    | `Record<string, string>`             | 请求头                          |
| `httpMethod` | `FileSystemAcceptedUploadHttpMethod` | 请求方法，默认 `POST`           |
| `uploadType` | `FileSystemUploadType`               | 上传类型，默认 `BINARY_CONTENT` |
| `fieldName`  | `string`                             | multipart 中文件字段名          |
| `mimeType`   | `string`                             | 文件类型                        |
| `parameters` | `Record<string, string>`             | multipart 中的额外字段          |

#### `DownloadOptions`（Legacy）

| 属性      | 类型                     | 说明               |
| --------- | ------------------------ | ------------------ |
| `md5`     | `boolean`                | 结果是否包含 `md5` |
| `headers` | `Record<string, string>` | 请求头             |

#### `ReadingOptions`

| 属性       | 类型                                  | 说明                              |
| ---------- | ------------------------------------- | --------------------------------- |
| `encoding` | `EncodingType \| 'utf8' \| 'base64'`  | 编码，默认 `utf8`                 |
| `position` | `number`                              | 跳过的字节数，只在 `base64` 下生效 |
| `length`   | `number`                              | 读取的字节数，只在 `base64` 下生效 |

#### `WritingOptions`

| 属性       | 类型                                  | 说明                  |
| ---------- | ------------------------------------- | --------------------- |
| `encoding` | `EncodingType \| 'utf8' \| 'base64'`  | 编码，默认 `utf8`     |
| `append`   | `boolean`                             | 是否追加，默认 `false` |

#### `DeletingOptions`

| 属性         | 类型      | 说明                             |
| ------------ | --------- | -------------------------------- |
| `idempotent` | `boolean` | 路径不存在时不报错，默认 `false` |

#### `RelocatingOptions`

| 属性   | 类型     | 说明     |
| ------ | -------- | -------- |
| `from` | `string` | 源地址   |
| `to`   | `string` | 目标地址 |

#### `MakeDirectoryOptions`

| 属性            | 类型      | 说明                           |
| --------------- | --------- | ------------------------------ |
| `intermediates` | `boolean` | 创建缺失的父目录，默认 `false` |

#### `DownloadPauseState`

| 属性         | 类型              | 说明                 |
| ------------ | ----------------- | -------------------- |
| `url`        | `string`          | 下载地址             |
| `fileUri`    | `string`          | 本地文件地址         |
| `options`    | `DownloadOptions` | 下载选项             |
| `resumeData` | `string`          | 续传数据，暂停后写入 |

#### `DownloadProgressData`

| 属性                        | 类型     | 说明                          |
| --------------------------- | -------- | ----------------------------- |
| `totalBytesWritten`         | `number` | 已写入字节数                  |
| `totalBytesExpectedToWrite` | `number` | 预期写入字节数，未知时为 `-1` |

#### `UploadProgressData`

| 属性                       | 类型     | 说明                          |
| -------------------------- | -------- | ----------------------------- |
| `totalBytesSent`           | `number` | 已发送字节数                  |
| `totalBytesExpectedToSend` | `number` | 预期发送字节数，未知时为 `-1` |

#### `FileSystemRequestDirectoryPermissionsResult`

`{ granted: false }` 或 `{ granted: true, directoryUri: string }`。

#### `ProgressEvent<T>`

| 属性   | 类型     |
| ------ | -------- |
| `uuid` | `string` |
| `data` | `T`      |

> **未实现的内容**
>
> - `DownloadOptions`（Legacy）的 `sessionType`、`cache` 和 `FileSystemUploadOptions.sessionType`：iOS 或 Android 专属选项，HarmonyOS 上不读取。
> - `FileSystemDownloadResult.mimeType`、`FileSystemUploadResult.mimeType`：HarmonyOS 上不返回该字段。

### Enums

以下枚举从 `expo-file-system/legacy` 导入。

#### `EncodingType`

| 成员     | 值       |
| -------- | -------- |
| `UTF8`   | `'utf8'` |
| `Base64` | `'base64'` |

#### `FileSystemUploadType`

| 成员             | 值  | 含义                      |
| ---------------- | --- | ------------------------- |
| `BINARY_CONTENT` | 0   | 文件作为请求体            |
| `MULTIPART`      | 1   | 文件编码为 multipart 表单 |

> **未实现的内容**
>
> - `FileSystemSessionType`：iOS 专属枚举，HarmonyOS 上没有对应取值。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
