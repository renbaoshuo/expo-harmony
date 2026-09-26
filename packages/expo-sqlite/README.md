# @expo-harmony/expo-sqlite

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-sqlite) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/sqlite/)

为 HarmonyOS 上的 React Native 应用提供 Expo SQLite 的原生实现，与官方同版本的 `expo-sqlite` 配套使用。支持同步和异步 SQL、预编译语句、事务、数据库快照、备份、Session Extension、变更监听、libSQL 同步和扩展加载。`SQLiteProvider`、React hooks、`kv-store` 和 `localStorage` 同样可用。

## 安装

```bash
npm install @expo-harmony/expo-sqlite expo-sqlite@55.0.20
```

这条命令会同时安装本包和官方的 `expo-sqlite`。本包适配 Expo SDK 55，提供 HarmonyOS 上的原生实现，业务代码继续从官方包导入。原生模块在构建应用时由 Expo Harmony 自动链接。最低支持 HarmonyOS 5.0.1（API 13），宿主应用的 `compatibleSdkVersion` 不能低于这个版本。

```ts
import * as SQLite from 'expo-sqlite';

const db = await SQLite.openDatabaseAsync('notes.db');
try {
  await db.execAsync('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, body TEXT)');
  await db.runAsync('INSERT INTO notes (body) VALUES (?)', 'Hello HarmonyOS');
  console.log(await db.getAllAsync('SELECT * FROM notes'));
} finally {
  await db.closeAsync();
}
```

## Config Plugin

默认构建启用标准 SQLite 和 FTS。需要 SQLCipher、libSQL、sqlite-vec 或自定义编译选项时，在 `app.json` 的 `plugins` 中注册 `@expo-harmony/expo-sqlite`，然后重新 prebuild 和构建应用：

```json
{
  "expo": {
    "plugins": [
      ["@expo-harmony/expo-sqlite", {
        "enableFTS": true,
        "harmony": {
          "useSQLCipher": true,
          "withSQLiteVecExtension": true
        }
      }]
    ]
  }
}
```

已有 `expo-sqlite` 插件时，将其替换为上述包名并保留原选项。本插件调用官方插件处理 iOS/Android；Harmony 配置优先取 `harmony` 下的值，再回退到同名顶层选项，支持覆盖为 `false` 或空字符串。

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `enableFTS` | `true` | 启用 SQLite/SQLCipher 的 FTS3/4/5 |
| `customBuildFlags` | `""` | SQLite/SQLCipher 额外编译参数 |
| `useSQLCipher` | `false` | 使用 SQLCipher 和静态 OpenSSL，以 `PRAGMA key` 等官方接口配置加密 |
| `useLibSQL` | `false` | 使用官方 libSQL C 后端 |
| `withSQLiteVecExtension` | `false` | 打包官方 sqlite-vec 扩展 |

SQLCipher 与 libSQL 不能同时启用；libSQL 不支持扩展加载，不能与 sqlite-vec 同时启用。`enableFTS` 和 `customBuildFlags` 不改变 libSQL 内置的 SQLite 配置。插件通过自动链接流程在应用构建目录生成并缓存配置对应的 HAR，应用开发者无需修改 `node_modules`，也无需安装 Python 或 Rust。

## API 对照表

数据库引擎内置于应用，不使用系统自带的数据库组件，各 API 的行为不随 HarmonyOS SDK 版本变化。数据库文件保存在应用沙箱内，读写不需要存储权限。

### 打开与关闭

#### `SQLite.openDatabaseAsync()` / `SQLite.openDatabaseSync()`

打开数据库，返回 `SQLiteDatabase`。`databaseName` 是文件名或绝对路径，默认放在 `defaultDatabaseDirectory`，也可以用 `directory` 参数指定其他目录。文件不存在时自动创建，父目录不存在时一并创建。`:memory:` 打开内存数据库。

相同原始路径加相同打开选项的重复调用复用同一个原生连接，设置 `useNewConnection: true` 时每次打开创建独立连接。

#### `SQLite.deleteDatabaseAsync()` / `SQLite.deleteDatabaseSync()`

删除数据库文件，`:memory:` 上是空操作。打开中的数据库不能删除，文件不存在或删除失败时抛出 `E_SQLITE_DELETE_DATABASE`。

#### `db.closeAsync()` / `db.closeSync()`

关闭数据库。复用的连接按打开次数计数，全部关闭后才真正断开。`finalizeUnusedStatementsBeforeClosing` 默认为 `true`，未释放的语句在关闭时自动 finalize。改为 `false` 时未释放的语句可能让关闭返回 busy，此后这个连接不能再复用，再次 close 也不会重试，资源在应用内数据库模块卸载时清理。

#### `db.databasePath` / `db.options`

数据库的绝对路径和打开时使用的选项。

路径支持 `file:` URI 形式。路径规范化规则和文件系统错误文本可能与 Android/iOS 不同，覆盖已打开文件的行为也是一样。

### 执行 SQL

#### `db.execAsync()` / `db.execSync()`

执行一段或多段 SQL，不返回结果。参数不做转义，拼接 SQL 时注意注入风险。

#### `db.runAsync()` / `db.runSync()`

执行单条语句并绑定参数，返回 `lastInsertRowId` 和 `changes`。

#### `db.getFirstAsync()` / `db.getAllAsync()` / `db.getEachAsync()` 及各自的 Sync 版本

读取查询结果。`getFirst` 返回第一行或 `null`，`getAll` 返回全部行，`getEach` 返回逐行迭代器，适合大结果集。

#### `db.sql`

Bun 风格的标签模板查询，基于预编译语句自动绑定参数，返回的对象可以直接 `await`，也可以调用 `.first()`、`.values()`、`.each()` 等方法，行为与官方文档一致。

绑定值支持 `string`、`number`、`boolean`、`null` 和 `Uint8Array`，可以按数组或对象传命名参数。SQLite 与 SQLCipher 构建下文本中的内嵌 NUL 会保留，空 `Uint8Array` 绑定为空 BLOB。读出的数值和 `lastInsertRowId` 都是 JS number，超出安全整数范围的 INTEGER 会丢失精度。

同一个连接上的数据库操作串行执行。同步接口会等待这个连接上正在执行的查询，较重的 SQL 建议走异步接口。相互独立的异步调用之间不保证先后顺序。

### 预编译语句

#### `db.prepareAsync()` / `db.prepareSync()`

预编译 SQL，返回 `SQLiteStatement`。空字符串可以 prepare 成功，列名为空数组，执行时抛出 `ERR_INTERNAL_SQLITE_ERROR`。

#### `stmt.executeAsync()` / `stmt.executeSync()`

执行并返回结果对象，带 `changes` 和 `lastInsertRowId`。结果对象支持 `for await...of` 或 `for...of` 逐行迭代，也提供 `getFirstAsync`、`getAllAsync`、`resetAsync` 和对应的 Sync 方法，重新读取前先调用 `reset`。

#### `stmt.getColumnNamesAsync()` / `stmt.getColumnNamesSync()`

返回列名数组。

#### `stmt.finalizeAsync()` / `stmt.finalizeSync()`

释放语句，建议在 `try...finally` 中调用。访问已 finalize 的语句或已关闭的数据库抛出 `ERR_ACCESS_CLOSED_RESOURCE`。

### 事务

#### `db.withTransactionAsync()` / `db.withTransactionSync()`

自动提交和回滚的事务封装。事务不排他，事务外的异步查询可能插入执行。

#### `db.withExclusiveTransactionAsync()`

排他事务，内部查询必须通过 `txn` 对象执行。官方文档标注该方法不支持 web，HarmonyOS 上可用。

#### `db.isInTransactionAsync()` / `db.isInTransactionSync()`

返回当前是否在事务中。

### 序列化与备份

#### `db.serializeAsync()` / `db.serializeSync()`

把数据库序列化为 `Uint8Array`，默认序列化 `main`，也可以指定 `ATTACH` 的库名。

#### `SQLite.deserializeDatabaseAsync()` / `SQLite.deserializeDatabaseSync()`

把序列化数据反序列化为内存数据库。

#### `SQLite.backupDatabaseAsync()` / `SQLite.backupDatabaseSync()`

用 SQLite backup API 把源数据库复制到目标数据库，两个数据库都需要先打开。

### 变更监听

#### `SQLite.addDatabaseChangeListener()`

订阅 `DatabaseChangeEvent`，事件包含库名、文件路径、表名和行 ID。打开数据库时设置 `enableChangeListener: true` 才会收到事件。事件来自 SQLite update hook，事务回滚前的写入也可能触发通知。

### Session Extension

#### `db.createSessionAsync()` / `db.createSessionSync()`

创建会话对象，默认针对 `main`，也可以指定其他库名。

#### `SQLiteSession`

变更集的完整流程都可用。附加表、启停记录、生成和应用变更集、生成反转变更集以及关闭会话均有对应的 async 和 sync 方法，`attach` 传入 `null` 时附加全部表。

### React 集成

#### `<SQLiteProvider />`

通过 Context 向子组件提供数据库，`onInit`、`onError`、`useSuspense` 等属性行为与官方文档一致。`assetSource` 从本地资源导入数据库文件，`forceOverwrite` 覆盖已有文件。覆盖不是原子操作，复制失败可能留下部分文件，替换前先关闭数据库。

#### `useSQLiteContext()`

在 `<SQLiteProvider />` 内获取 `SQLiteDatabase`。

#### `SQLite.deepEqual()`

深度比较两个对象。

### 键值存储

#### `SQLite.Storage` 与 `SQLite.AsyncStorage`

从 `expo-sqlite/kv-store` 导入的键值存储，兼容 AsyncStorage 的接口，提供同步变体和 `mergeItem` 等扩展方法。

#### `localStorage` 适配

从 `expo-sqlite/localStorage/install` 导入后安装基于 SQLite 的 `localStorage` polyfill。

### libSQL

在 Config Plugin 中启用 `useLibSQL` 后，打开数据库时通过 `libSQLOptions` 传入服务器地址和认证信息：

```ts
const db = await SQLite.openDatabaseAsync('replica.db', {
  libSQLOptions: {
    url: 'libsql://your-database.turso.io',
    authToken: token,
    remoteOnly: false,
  },
});
await db.syncLibSQL();
await db.closeAsync();
```

`url` 和 `authToken` 必须同时提供，缺省时抛出 `ERR_INVALID_ARGUMENTS`。默认使用 offline embedded replica，启用 read-your-writes 和 WebPKI，`remoteOnly: true` 时使用 remote backend。`db.syncLibSQL()` 同步本地副本与远端。模块已声明网络权限。

libSQL 的 C API 使用 NUL 结尾字符串，绑定文本在首个 NUL 处截断，读取含内嵌 NUL 的 TEXT 时返回空字符串，需要保留任意字节时使用 `Uint8Array`。所有构建下 SQL 源文本也是 NUL 结尾，不应包含内嵌 NUL，参数文本通过绑定传入。

> **未实现的内容**
>
> libSQL 构建下这些接口调用时抛出 `ERR_UNSUPPORTED_OPERATION`。
>
> - 命名参数绑定，上游 C API 只提供按位置的绑定接口。
> - `serializeAsync`/`serializeSync`、`deserializeDatabaseAsync`/`deserializeDatabaseSync`、`backupDatabaseAsync`/`backupDatabaseSync`，上游 C API 未提供对应能力。
> - `isInTransactionAsync`/`isInTransactionSync`，libSQL 连接不暴露事务状态。
> - `createSessionAsync`/`createSessionSync` 与 `SQLiteSession` 的全部方法，上游 C API 未提供对应能力。
> - `addDatabaseChangeListener`，libSQL 不提供变更通知，打开时设置 `enableChangeListener: true` 也会抛出 `ERR_UNSUPPORTED_OPERATION`。
> - `loadExtensionAsync`/`loadExtensionSync`，libSQL 构建不支持扩展加载。

### 扩展加载

`loadExtensionAsync`/`loadExtensionSync` 在 SQLite 和 SQLCipher 构建下可用。官方文档把扩展加载标为 iOS 和 Android 专属，HarmonyOS 上同样提供。

启用 `withSQLiteVecExtension` 后，sqlite-vec 随应用打包，从 `SQLite.bundledExtensions` 取路径加载：

```ts
const extension = SQLite.bundledExtensions['sqlite-vec'];
await db.loadExtensionAsync(extension.libPath, extension.entryPoint);
```

也可以加载自行编译的同 ABI HarmonyOS 扩展。省略 `entryPoint` 或传入空字符串时按 SQLite 默认规则查找入口，空字符串的行为与 Android 一致。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
