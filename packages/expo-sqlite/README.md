# @expo-harmony/expo-sqlite

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-sqlite) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/sqlite/)

为 HarmonyOS 上的 React Native 应用提供 Expo SQLite 数据库 API，与对应版本的 `expo-sqlite` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-sqlite expo-sqlite
```

## API 对照表

### Hooks

#### `<SQLiteProvider />`

参数见 `SQLiteProviderProps`。打开指定数据库后，通过 React Context 向子组件提供 `SQLiteDatabase`。`onInit` 在子组件渲染前运行；初始化失败时调用 `onError`，默认重新抛出错误。设置 `useSuspense` 后，初始化期间由 Suspense 处理等待，且不能同时设置 `onError`。

设置 `assetSource` 可将本地资源中的数据库文件导入到目标数据库；`forceOverwrite` 默认为 `false`，为 `true` 时覆盖目标文件。导入要求资源和目标文件没有 WAL 或回滚日志，且目标数据库未打开。

#### `useSQLiteContext()`

返回最近的 `<SQLiteProvider />` 提供的 `SQLiteDatabase`。在 Provider 外调用会抛出错误。

### Constants

#### `defaultDatabaseDirectory`

类型：`string`。

应用沙箱中的默认 SQLite 数据库目录。`openDatabaseAsync()` 和 `openDatabaseSync()` 未传入 `directory` 时使用此目录。

#### `bundledExtensions`

类型：`Record<string, { libPath: string; entryPoint: string } | undefined>`。

列出随应用提供的 SQLite 扩展。启用配置插件选项 `withSQLiteVecExtension` 后，可通过 `bundledExtensions['sqlite-vec']` 取得 sqlite-vec 的库路径和入口名；未启用时没有该条目。

### Methods

#### `SQLite.openDatabaseAsync()` / `SQLite.openDatabaseSync()`

参数：`databaseName: string`、可选的 `options: SQLiteOpenOptions` 和 `directory: string`。

返回：分别为 `Promise<SQLiteDatabase>` 和 `SQLiteDatabase`。

数据库默认保存在应用沙箱中，不需要存储权限。数据库文件不存在时会创建，所需父目录也会创建。`databaseName` 为数据库目录下的名称；传入 `:memory:` 可打开内存数据库。相同路径和打开选项会复用连接，设置 `useNewConnection: true` 会建立独立连接。

#### `SQLite.deleteDatabaseAsync()` / `SQLite.deleteDatabaseSync()`

参数：`databaseName: string` 和可选的 `directory: string`。

返回：异步版本为 `Promise<void>`，同步版本为 `void`。数据库文件不存在、仍有连接打开或删除失败时抛出 `E_SQLITE_DELETE_DATABASE`。对 `:memory:` 调用不删除文件。

#### `SQLite.deserializeDatabaseAsync()` / `SQLite.deserializeDatabaseSync()`

参数：序列化数据库的 `Uint8Array`，以及可选的 `SQLiteOpenOptions`。

返回：分别为 `Promise<SQLiteDatabase>` 和 `SQLiteDatabase`，数据库位于内存中。

- `libSQL` 模式不支持反序列化，会抛出 `ERR_UNSUPPORTED_OPERATION`。

#### `SQLite.backupDatabaseAsync()` / `SQLite.backupDatabaseSync()`

参数对象包含 `sourceDatabase`、`destDatabase`，以及可选的 `sourceDatabaseName` 和 `destDatabaseName`；两个名称默认均为 `main`。

返回：分别为 `Promise<void>` 和 `void`。源数据库和目标数据库都必须已打开。

- `libSQL` 模式不支持数据库备份，会抛出 `ERR_UNSUPPORTED_OPERATION`。

#### `db.databasePath` / `db.options`

`databasePath: string` 为数据库绝对路径；`options: SQLiteOpenOptions` 为打开数据库时使用的选项。

#### `db.closeAsync()` / `db.closeSync()`

关闭数据库，分别返回 `Promise<void>` 和 `void`。关闭后不能继续访问该数据库。打开选项 `finalizeUnusedStatementsBeforeClosing` 默认为 `true`，会在关闭时释放尚未 finalize 的语句；设为 `false` 时，未释放语句可能导致关闭失败。

#### `db.execAsync()` / `db.execSync()`

参数：包含一条或多条 SQL 语句的 `source: string`。

返回：分别为 `Promise<void>` 和 `void`。此方法不绑定或转义参数；传入多个 SQL 语句时会依次执行。`libSQL` 模式遇到第一条出错语句后停止。

#### `db.runAsync()` / `db.runSync()`

参数：SQL `source: string` 和绑定参数；可用数组、命名参数对象或位置参数。

返回：分别为 `Promise<SQLiteRunResult>` 和 `SQLiteRunResult`，包含 `lastInsertRowId` 与受影响的行数 `changes`。

#### `db.getFirstAsync()` / `db.getFirstSync()`

参数：SQL `source: string` 和可选绑定参数。

返回：分别为 `Promise<T | null>` 和 `T | null`；无匹配行时返回 `null`。

#### `db.getAllAsync()` / `db.getAllSync()`

参数：SQL `source: string` 和可选绑定参数。

返回：分别为 `Promise<T[]>` 和 `T[]`。

#### `db.getEachAsync()` / `db.getEachSync()`

参数：SQL `source: string` 和可选绑定参数。

返回：分别为逐行读取的 `AsyncIterableIterator<T>` 和 `IterableIterator<T>`。

#### `db.prepareAsync()` / `db.prepareSync()`

参数：SQL `source: string`。

返回：分别为 `Promise<SQLiteStatement>` 和 `SQLiteStatement`。空 SQL 可以准备，但执行时会以 `ERR_INTERNAL_SQLITE_ERROR` 失败。

#### `stmt.executeAsync()` / `stmt.executeSync()`

参数：可选绑定参数；支持位置参数数组、命名参数对象或位置参数。返回分别为 `Promise<SQLiteExecuteAsyncResult<T>>` 和 `SQLiteExecuteSyncResult<T>`，包含 `lastInsertRowId`、`changes` 和逐行结果读取接口。

结果对象支持 `getFirstAsync()`/`getFirstSync()`、`getAllAsync()`/`getAllSync()`、`resetAsync()`/`resetSync()` 及迭代器。读取过结果后，如需从头读取，先重置游标。同一语句再次执行会让先前结果无法继续读取；游标读完后继续读取会得到空结果。

#### `stmt.getColumnNamesAsync()` / `stmt.getColumnNamesSync()`

返回列名数组，异步版本返回 `Promise<string[]>`。

- `libSQL` 模式下，语句至少执行一次后才能取得列名；否则抛出 `ERR_UNSUPPORTED_OPERATION`。

#### `stmt.finalizeAsync()` / `stmt.finalizeSync()`

释放预编译语句，分别返回 `Promise<void>` 和 `void`。释放后继续访问该语句会抛出 `ERR_ACCESS_CLOSED_RESOURCE`。

#### `db.withTransactionAsync()` / `db.withTransactionSync()`

参数：异步版本接收返回 `Promise<void>` 的任务函数；同步版本接收返回 `void` 的任务函数。返回分别为 `Promise<void>` 和 `void`。

任务成功时提交，抛错时回滚并继续抛出错误。异步事务不排他，事务外的异步查询可能在事务中执行。

#### `db.withExclusiveTransactionAsync()`

参数：接收 `txn: SQLiteDatabase` 的异步任务函数，返回 `Promise<void>`。任务成功时提交，抛错时回滚。事务内查询应通过传入的 `txn` 对象执行。

#### `db.isInTransactionAsync()` / `db.isInTransactionSync()`

返回分别为 `Promise<boolean>` 和 `boolean`。

- `libSQL` 模式不支持查询事务状态，会抛出 `ERR_UNSUPPORTED_OPERATION`。

#### `db.serializeAsync()` / `db.serializeSync()`

参数：可选数据库名称 `databaseName: string`，默认值为 `main`；可指定已附加数据库的名称。

返回：分别为 `Promise<Uint8Array>` 和 `Uint8Array`。

- `libSQL` 模式不支持序列化，会抛出 `ERR_UNSUPPORTED_OPERATION`。

#### `db.createSessionAsync()` / `db.createSessionSync()`

参数：可选数据库名称 `dbName: string`，默认值为 `main`。

返回：分别为 `Promise<SQLiteSession>` 和 `SQLiteSession`。

- `libSQL` 模式不支持创建 Session，会抛出 `ERR_UNSUPPORTED_OPERATION`；因此 Session 的方法也不可用。

#### `session.attachAsync()` / `session.attachSync()`

参数：`table: string | null`。传入 `null` 时记录所有表的变更。返回分别为 `Promise<void>` 和 `void`。

#### `session.enableAsync()` / `session.enableSync()`

参数：`enabled: boolean`，用于启用或暂停会话记录。返回分别为 `Promise<void>` 和 `void`。

#### `session.createChangesetAsync()` / `session.createChangesetSync()`

返回分别为 `Promise<Changeset>` 和 `Changeset`，内容为 `Uint8Array`。

#### `session.createInvertedChangesetAsync()` / `session.createInvertedChangesetSync()`

返回分别为 `Promise<Changeset>` 和 `Changeset`，内容为 `Uint8Array`。

#### `session.applyChangesetAsync()` / `session.applyChangesetSync()`

参数：要应用的 `changeset: Changeset`。返回分别为 `Promise<void>` 和 `void`。

#### `session.invertChangesetAsync()` / `session.invertChangesetSync()`

参数：`changeset: Changeset`。返回分别为 `Promise<Changeset>` 和 `Changeset`。

#### `session.closeAsync()` / `session.closeSync()`

关闭会话，返回分别为 `Promise<void>` 和 `void`。

#### `db.loadExtensionAsync()` / `db.loadExtensionSync()`

参数：扩展库路径 `libPath: string` 和可选入口名 `entryPoint: string`。省略入口名时使用 SQLite 的默认入口查找规则。返回分别为 `Promise<void>` 和 `void`。

启用 `withSQLiteVecExtension` 后，可将 `bundledExtensions['sqlite-vec']` 中的 `libPath` 与 `entryPoint` 传入此方法。SQL 函数 `load_extension()` 默认不可用。

- `libSQL` 模式不支持扩展加载，会抛出 `ERR_UNSUPPORTED_OPERATION`。

#### `db.sql`

SQL 标签模板，可直接 `await` 查询，也可调用下列读取方法。模板插值会作为绑定参数处理；直接 `await` 查询时，读取语句返回行对象数组，写入语句返回 `SQLiteRunResult`。

#### `SQLiteTaggedQuery.first()` / `SQLiteTaggedQuery.firstSync()`

返回查询结果首行，类型分别为 `Promise<T | null>` 和 `T | null`；没有匹配行时返回 `null`。

#### `SQLiteTaggedQuery.values()` / `SQLiteTaggedQuery.valuesSync()`

返回按列顺序排列的二维数组，类型分别为 `Promise<any[][]>` 和 `any[][]`。

#### `SQLiteTaggedQuery.each()` / `SQLiteTaggedQuery.eachSync()`

返回逐行读取的异步或同步迭代器。读取 BLOB 时返回 `Uint8Array`。

#### `db.syncLibSQL()`

同步本地数据库和 libSQL 服务，返回 `Promise<void>`。

- 未启用配置插件选项 `useLibSQL` 时，此接口不可用，调用会抛出 `ERR_UNSUPPORTED_OPERATION`。

#### `SQLite.deepEqual()`

参数：两个对象或 `undefined`。返回 `boolean`，表示两者是否深度相等。

#### `SQLiteStorage`、`Storage` 和 `AsyncStorage`

从 `expo-sqlite/kv-store` 导入。`new SQLiteStorage(databaseName: string)` 创建指定数据库的存储实例；`Storage` 与 `AsyncStorage` 是同一个默认存储实例，数据库名为 `ExpoSQLiteStorage`。

- 启用配置插件选项 `useLibSQL` 时，默认存储实例没有服务地址和认证令牌，无法打开数据库。

#### `storage.getItemAsync()` / `storage.getItemSync()`

参数：字符串键。返回分别为 `Promise<string | null>` 和 `string | null`；键不存在时为 `null`。

#### `storage.setItemAsync()` / `storage.setItemSync()`

参数：字符串键，以及字符串值或 `SQLiteStorageSetItemUpdateFunction`。更新函数会收到原值或 `null`，并返回要保存的新字符串。返回分别为 `Promise<void>` 和 `void`。

#### `storage.removeItemAsync()` / `storage.removeItemSync()`

参数：字符串键。返回分别为 `Promise<boolean>` 和 `boolean`，表示是否删除了现存值。

#### `storage.getAllKeysAsync()` / `storage.getAllKeysSync()`

返回分别为 `Promise<string[]>` 和 `string[]`，包含所有键。

#### `storage.clearAsync()` / `storage.clearSync()`

删除全部键值。返回分别为 `Promise<boolean>` 和 `boolean`，表示是否删除了至少一个值。

#### `storage.getLengthAsync()` / `storage.getLengthSync()`

返回分别为 `Promise<number>` 和 `number`，表示当前键值数量。

#### `storage.getKeyByIndexAsync()` / `storage.getKeyByIndexSync()`

参数：从零开始的索引。返回分别为 `Promise<string | null>` 和 `string | null`；索引无效或没有对应键时返回 `null`。

#### `storage.closeAsync()` / `storage.closeSync()`

关闭存储数据库连接，返回 `Promise<void>` 或 `void`；下次读写时会重新打开。

#### `storage.getItem()`、`storage.setItem()`、`storage.removeItem()`、`storage.getAllKeys()` 和 `storage.clear()`

AsyncStorage 风格的异步方法，分别对应 `getItemAsync()`、`setItemAsync()`、`removeItemAsync()`、`getAllKeysAsync()` 和 `clearAsync()`。`removeItem()` 和 `clear()` 返回 `Promise<void>`。

#### `storage.multiGet()`

参数：键数组。返回 `Promise<[string, string | null][]>`，每项为键及其值。

#### `storage.multiSet()`

参数：键值对数组 `[string, string][]`。写入全部键值对，返回 `Promise<void>`。

#### `storage.multiRemove()`

参数：键数组。删除指定键，返回 `Promise<void>`。

#### `storage.mergeItem()` / `storage.multiMerge()`

参数：一个键和 JSON 字符串，或多组键与 JSON 字符串。对已有 JSON 对象执行递归合并，返回 `Promise<void>`。

#### `localStorage` 安装

导入 `expo-sqlite/localStorage/install` 后，会在 HarmonyOS 应用中安装基于 SQLite 的全局 `localStorage`。

- 启用 `useLibSQL` 时，默认存储实例缺少服务地址和认证令牌，`localStorage` 不可用。

#### SQLite 配置插件

配置插件可通过 `harmony` 字段设置 HarmonyOS 构建选项；省略 `harmony` 时也可在插件选项顶层设置这些选项。

~~~json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-sqlite",
        {
          "enableFTS": true,
          "harmony": {
            "useSQLCipher": true,
            "withSQLiteVecExtension": true
          }
        }
      ]
    ]
  }
}
~~~

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `enableFTS` | `true` | 启用 FTS3、FTS4 和 FTS5。 |
| `customBuildFlags` | `""` | 传递额外的 SQLite 或 SQLCipher 编译选项。 |
| `useSQLCipher` | `false` | 使用 SQLCipher；可通过 `PRAGMA key` 设置数据库密钥。 |
| `useLibSQL` | `false` | 构建 libSQL 模式；打开数据库时需同时传入服务 `url` 和 `authToken`。默认使用本地数据库并由 `db.syncLibSQL()` 同步；`remoteOnly: true` 时直接访问远端。 |
| `withSQLiteVecExtension` | `false` | 将 sqlite-vec 加入应用包，并通过 `bundledExtensions` 获取扩展路径。 |

`useLibSQL` 与 `useSQLCipher` 不能同时启用；libSQL 不支持加载扩展，因此不能与 `withSQLiteVecExtension` 同时启用。`enableFTS` 和 `customBuildFlags` 不影响 libSQL 构建。

### Event subscriptions

#### `SQLite.addDatabaseChangeListener()`

参数：接收 `DatabaseChangeEvent` 的监听函数。

返回：可调用 `remove()` 取消订阅的事件订阅对象。打开数据库时需设置 `enableChangeListener: true` 才会收到事件。HarmonyOS 事件还会包含 `typeId`，取值为 `insert`、`update` 或 `delete`。事务回滚前的写入也可能产生通知。

- `libSQL` 模式不支持数据库变更事件；设置 `enableChangeListener: true` 会以 `ERR_UNSUPPORTED_OPERATION` 拒绝打开数据库。

### Types

#### `SQLiteOpenOptions`

- `enableChangeListener?: boolean`：是否发送数据库变更事件，默认 `false`。
- `useNewConnection?: boolean`：是否为本次打开创建独立连接，默认 `false`。
- `finalizeUnusedStatementsBeforeClosing?: boolean`：关闭数据库时是否释放未 finalize 的语句，默认 `true`。
- `libSQLOptions?: { url: string; authToken: string; remoteOnly?: boolean }`：libSQL 服务地址、认证信息和远端直连设置；仅在启用 `useLibSQL` 的构建中使用。缺少 `url` 或 `authToken` 时抛出 `ERR_INVALID_ARGUMENTS`。

#### `SQLiteBindValue` / `SQLiteBindParams` / `SQLiteVariadicBindParams`

绑定值为 `string`、`number`、`boolean`、`null`、`Uint8Array` 或 `ArrayBuffer`。参数可按位置数组、命名参数对象或位置参数传入。读取的 SQLite 数值以 JavaScript `number` 返回，超过安全整数范围的整数可能失去精度。

- libSQL 模式不支持命名参数绑定，只接受位置参数。

#### `SQLiteRunResult`

包含 `lastInsertRowId: number` 和 `changes: number`。

#### `SQLiteExecuteAsyncResult<T>` / `SQLiteExecuteSyncResult<T>`

异步和同步执行结果，分别实现异步和同步迭代器；包含 `lastInsertRowId`、`changes`、首行读取、全部行读取及游标重置方法。

#### `DatabaseChangeEvent`

变更事件类型包含 `databaseName`、`databaseFilePath`、`tableName` 和 `rowId`。HarmonyOS 事件还会包含类型声明未列出的 `typeId` 字段，取值为 `insert`、`update` 或 `delete`。

#### `SQLiteProviderProps`

Provider 属性包括必填的 `databaseName`、`children`，以及可选的 `directory`、`options`、`assetSource`、`onInit`、`onError` 和 `useSuspense`。

#### `SQLiteProviderAssetSource`

包含本地资源 ID `assetId: number` 和可选的 `forceOverwrite?: boolean`。

#### `Changeset`

类型为 `Uint8Array`，用于 SQLite Session 变更集的创建、应用和反转。

#### `SQLiteStorageSetItemUpdateFunction`

类型为 `(prevValue: string | null) => string`，计算写入的新值；不存在旧值时 `prevValue` 为 `null`。

### Error codes

| 错误码 | 触发条件 |
| --- | --- |
| `E_SQLITE_INVALID_PATH` | 数据库路径无效，或无法创建所需目录。 |
| `E_SQLITE_OPEN_DATABASE` | 数据库无法打开，或导入资源时数据库文件无效、正在打开或无法读取。 |
| `E_SQLITE_DELETE_DATABASE` | 数据库不存在、仍处于打开状态或无法删除。 |
| `ERR_ACCESS_CLOSED_RESOURCE` | 访问已关闭的数据库、已释放的语句或已关闭的 Session。 |
| `ERR_INVALID_ARGUMENTS` | libSQL 缺少服务地址或认证令牌，或传入无效的 SQLite 字符串参数。 |
| `ERR_INVALID_BIND_PARAMETER` | 绑定值或位置参数无效。 |
| `ERR_INVALID_CONVERTIBLE` | libSQL 返回无法转换的列类型。 |
| `ERR_UNSUPPORTED_OPERATION` | 当前 libSQL 构建不支持该接口，或在未启用 libSQL 时调用 `db.syncLibSQL()`。 |
| `ERR_INTERNAL_SQLITE_ERROR` | SQLite 或 libSQL 执行 SQL、访问语句或操作数据库失败。 |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.

Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
