# @expo-harmony/config-plugins

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/config-plugins) | [官方文档](https://docs.expo.dev/config-plugins/introduction/)

为 HarmonyOS 上的 React Native 应用提供 Expo Config Plugins 的原生实现，与官方同版本的 `@expo/config-plugins` 配套使用。

## 安装

本包适配 Expo SDK 57。

```sh
npm install @expo-harmony/config-plugins
```

## API 对照表

### Constants

#### `HARMONY_MOD_NAMES`

Harmony Mod 名称列表：`dangerous`、`reactNativeConfig`、`appJson`、`projectBuildProfile`、`rootOhPackage`、`rootHvigor`、`hvigorConfig`、`entryBuildProfile`、`entryOhPackage`、`entryHvigor`、`moduleJson`、`strings`、`colors`、`media`、`profiles`、`abilityStage`、`entryAbility`、`indexPage`、`worker`、`arktsPackageProvider`、`cppPackageProvider`、`cmakeLists` 和 `autolinking`。

#### `HarmonyPaths`

提供 Harmony 工程路径常量和路径查询方法。路径均相对于 Harmony 工程根目录。

| 常量 | 路径 |
| --- | --- |
| `HARMONY_PATHS.appJson` | `AppScope/app.json5` |
| `HARMONY_PATHS.projectBuildProfile` | `build-profile.json5` |
| `HARMONY_PATHS.rootOhPackage` | `oh-package.json5` |
| `HARMONY_PATHS.rootHvigor` | `hvigorfile.ts` |
| `HARMONY_PATHS.hvigorConfig` | `hvigor/hvigor-config.json5` |
| `HARMONY_PATHS.entryBuildProfile` | `entry/build-profile.json5` |
| `HARMONY_PATHS.entryOhPackage` | `entry/oh-package.json5` |
| `HARMONY_PATHS.entryHvigor` | `entry/hvigorfile.ts` |
| `HARMONY_PATHS.moduleJson` | `entry/src/main/module.json5` |
| `HARMONY_PATHS.profiles` | `entry/src/main/resources/base/profile/main_pages.json` |
| `HARMONY_PATHS.abilityStage` | `entry/src/main/ets/abilitystage/EntryAbilityStage.ets` |
| `HARMONY_PATHS.entryAbility` | `entry/src/main/ets/entryability/EntryAbility.ets` |
| `HARMONY_PATHS.indexPage` | `entry/src/main/ets/pages/Index.ets` |
| `HARMONY_PATHS.worker` | `entry/src/main/ets/workers/RNOHWorker.ets` |
| `HARMONY_PATHS.arktsPackageProvider` | `entry/src/main/ets/PackageProvider.ets` |
| `HARMONY_PATHS.cppPackageProvider` | `entry/src/main/cpp/PackageProvider.cpp` |
| `HARMONY_PATHS.cmakeLists` | `entry/src/main/cpp/CMakeLists.txt` |
| `PROJECT_PATHS.reactNativeConfig` | `react-native.config.js` |
| `PROJECT_PATH_CANDIDATES.reactNativeConfig` | `react-native.config.js`、`.cjs`、`.ts`、`.mjs` |
| `RESOURCE_PATHS.strings` | `app`、`entry` 两个作用域的 string 资源文件 |
| `RESOURCE_PATHS.colors` | `entry`、`entryDark` 两个作用域的 color 资源文件 |
| `RESOURCE_PATHS.media` | `app`、`entry`、`entryDark` 三个作用域的 media 目录 |

### Methods

#### `defineExpoHarmonyConfig(config)`

接受包含 `harmony` 字段的 Expo 配置并原样返回。此函数保留配置的具体 TypeScript 类型，可用于 `app.config.ts`。

#### `normalizeHarmonyConfig(config)`

返回补齐默认值并校验后的 `NormalizedHarmonyConfig`。`harmony.bundleName` 必须是至少三段的点分隔标识符；SDK 版本值、权限、技能、设备类型、颜色和模块构建选项不符合类型或格式时会抛出 `HarmonyConfigPluginError`。

#### `parseHarmonySdkVersion(value, field?)`

把 API 级别或 SDK 标签解析为 `{ api, native }`。数字 API 支持 13、14、20、21、23、24，以及 26 及以上；其他低于 26 的 API 级别需传入完整标签，例如 `6.1.1(24)`。API 26 及以上使用 `26.0.0` 格式。`field` 可用于指定错误信息中的字段名。

#### `compareHarmonyApiVersions(left, right)`

逐段比较由数字或点分隔字符串表示的 API 版本，返回负数、零或正数。

#### `compileHarmonyModsAsync(config, options)`

执行 Harmony Mods 并返回更新后的配置。`options.projectRoot` 必填；`introspect: true` 只读取可 introspect 的 Mod，不写工程文件；`ignoreExistingNativeFiles: true` 忽略工程中的现有原生文件。

使用 `expo/config` 读取配置后再调用时，应将 `isModdedConfig` 设为 `true`，以保留 Mod 配置。

#### `withHarmonyBaseMods(config)`

为配置注册 `HARMONY_MOD_NAMES` 中的基础 Mod，返回更新后的配置。

#### `withHarmonyMod(config, [name, action])`

按 `name` 将 `action` 注册到 Harmony Mod，返回更新后的配置。`action` 接收并返回 Mod 配置，可同步或异步执行；Mod 回调按后注册先执行的顺序调用。

JSON Mod 的 `modResults` 是对象，文本 Mod 是字符串，资源 Mod 是按作用域组织的对象。回调可从 `mod.modRawConfig` 读取原始 Expo 配置；`mod.modRequest.platform` 的值为 `harmony`。

#### `withHarmonyResources(config, action)`

将同一个 `action` 注册到 `strings`、`colors` 和 `media` 三个 Mod。每次回调收到对应 Mod 的资源结果。

#### `withReactNativeConfig(config, action)`

修改 Expo 项目根目录中的 `react-native.config.js`，回调的 `modResults` 是文本。

#### `withAppJson(config, action)`

修改 `AppScope/app.json5`，回调的 `modResults` 是 JSON 对象。

#### `withProjectBuildProfile(config, action)`

修改 Harmony 工程根目录的 `build-profile.json5`，回调的 `modResults` 是 JSON 对象。

#### `withRootOhPackage(config, action)`

修改 Harmony 工程根目录的 `oh-package.json5`，回调的 `modResults` 是 JSON 对象。

#### `withRootHvigor(config, action)`

修改 Harmony 工程根目录的 `hvigorfile.ts`，回调的 `modResults` 是文本。

#### `withHvigorConfig(config, action)`

修改 `hvigor/hvigor-config.json5`，回调的 `modResults` 是 JSON 对象。

#### `withEntryBuildProfile(config, action)`

修改 `entry/build-profile.json5`，回调的 `modResults` 是 JSON 对象。

#### `withEntryOhPackage(config, action)`

修改 `entry/oh-package.json5`，回调的 `modResults` 是 JSON 对象。

#### `withEntryHvigor(config, action)`

修改 `entry/hvigorfile.ts`，回调的 `modResults` 是文本。

#### `withModuleJson(config, action)`

修改 `entry/src/main/module.json5`，回调的 `modResults` 是 `HarmonyModuleJson` 对象。

```js
const { HarmonyManifest, withModuleJson } = require('@expo-harmony/config-plugins');

function withExample(config) {
  return withModuleJson(config, (mod) => {
    const module = HarmonyManifest.getModuleOrThrow(mod.modResults);
    HarmonyManifest.setMetadata(module, { name: 'example.enabled', value: 'true' });
    return mod;
  });
}
```

#### `withStrings(config, action)`

修改 `app` 和 `entry` 作用域的字符串资源。回调的 `modResults` 是作用域到资源 JSON 的映射。

#### `withColors(config, action)`

修改 `entry` 和 `entryDark` 作用域的颜色资源。回调的 `modResults` 是作用域到资源 JSON 的映射。

#### `withMedia(config, action)`

修改 `app`、`entry` 和 `entryDark` 作用域的媒体文件。回调的 `modResults` 是作用域到文件名和媒体描述符的映射；`source` 指向 Expo 项目中的文件，`content` 可为字符串或 `Uint8Array`。设置 `replaceBase: true` 会替换同基本名的文件。

#### `withProfiles(config, action)`

修改 `entry/src/main/resources/base/profile/main_pages.json`，回调的 `modResults` 是 JSON 对象。

#### `withAbilityStage(config, action)`

修改 `entry/src/main/ets/abilitystage/EntryAbilityStage.ets`，回调的 `modResults` 是文本。

#### `withEntryAbility(config, action)`

修改 `entry/src/main/ets/entryability/EntryAbility.ets`，回调的 `modResults` 是文本。

#### `withIndexPage(config, action)`

修改 `entry/src/main/ets/pages/Index.ets`，回调的 `modResults` 是文本。

#### `withWorker(config, action)`

修改 `entry/src/main/ets/workers/RNOHWorker.ets`，回调的 `modResults` 是文本。

#### `withArkTSPackageProvider(config, action)`

修改 `entry/src/main/ets/PackageProvider.ets`，回调的 `modResults` 是文本。

#### `withCppPackageProvider(config, action)`

修改 `entry/src/main/cpp/PackageProvider.cpp`，回调的 `modResults` 是文本。

#### `withCMakeLists(config, action)`

修改 `entry/src/main/cpp/CMakeLists.txt`，回调的 `modResults` 是文本。

#### `withHarmonyAutolinking(config, action)`

注册 Harmony 自动链接 Mod 的回调。该 Mod 的 `modResults` 为 `null`。

#### `withHarmonyDangerousMod(config, action)`

注册没有固定目标文件的 Harmony Mod 回调。该 Mod 的 `modResults` 为 `null`。

#### `withRawfile(config, options)`

将文件写入 `entry/src/main/resources/rawfile`。`options.files` 的键是相对 rawfile 根目录的路径，值为 `source` 或 `content` 描述符；`source` 相对 Expo 项目根目录，也可使用绝对路径，`content` 为字符串或 `Uint8Array`。路径不能包含绝对路径、反斜线、`.` 或 `..` 段。

#### `withHarmonyGeneratedFiles(config, options)`

将文件写入 Harmony 工程。`options.files` 的键是相对工程根目录的路径，值必须且只能指定 `source` 或 `content`。`source` 相对 Expo 项目根目录，也可使用绝对路径；`content` 为字符串或 `Uint8Array`。路径不能越出工程目录、指向工程外的符号链接，或覆盖内置 Mod 管理的文件。

`options.owner` 标识文件归属。配合 `@expo-harmony/prebuild-config` 使用时，后续生成会清理该 owner 不再声明的文件，卸载插件时会清理其管理的文件。不同 owner 不能声明相同路径或文件与目录的父子路径。

#### `createHarmonyFileMod(options)`

为自定义文件格式创建 Mod，返回接收 `(config, action)` 的插件函数。`options.path` 是相对 Harmony 工程根目录的文件路径；`parse(source)` 接收文本或 `null`（文件不存在），`serialize(value)` 返回文本。仅当 Mod 可在不写文件时安全读取结果，才设置 `isIntrospective: true`。

#### `withHarmonyJsonFile(config, options)`

创建 JSON 或 JSON5 文件 Mod。`options` 包含相对工程根目录的 `path`、`owner` 和修改 `modResults` 的 `action`；`modResults` 是对象。

#### `registerHarmonyConfigPlugin(config, owner, claims?)`

声明插件管理的文件、Ability 字段和资源名，并返回配置。`claims.files` 是相对工程根目录的文件路径；`claims.resources` 按 `strings`、`colors`、`media` 和资源作用域声明名称；`claims.ability` 支持 `startWindowBackground`、`startWindowIcon`。不同 owner 不能声明相同文件或文件与目录的父子路径。

#### `recordManagedFile(config, file, owner)`

登记已生成文件的归属，供 `@expo-harmony/prebuild-config` 在后续生成或移除插件时清理。

#### `withPlugins(config, plugins)`

按数组顺序应用静态插件，并保留 Harmony 配置的类型。插件可以是包名、插件函数，或 `[插件, props]`。

#### `withRunOnce(config, options)`

只应用一次指定插件。`options` 包含 `plugin`、`name` 和可选的 `version`。

#### `withStaticPlugin(config, options)`

应用静态插件。`options` 支持 `plugin`、可选的 `projectRoot` 和 `fallback`。

#### `createRunOncePlugin(plugin, name, version?)`

将插件包装为只运行一次的插件，返回保留 Harmony 配置类型的插件函数。

#### `HarmonyManifest.getModuleOrThrow(manifest)`

返回 `manifest.module`。模块缺失或格式不正确时抛出 `ERR_HARMONY_MANIFEST_INVALID`。

#### `HarmonyManifest.getMainAbilityOrThrow(manifest, name?)`

返回目标 Ability。未传 `name` 时，按 `module.mainElement`、第一个 Ability 的顺序选择；目标缺失或同名 Ability 重复时抛错。

#### `HarmonyManifest.setMetadata(target, item)`

按 `item.name` 更新 `module` 或 Ability 的 metadata；同名项会合并字段，其他 metadata 保留。`target` 可以是 `HarmonyModule` 或 `HarmonyAbility`。

#### `HarmonyManifest.removeMetadata(target, name)`

从 `module` 或 Ability 的 metadata 中删除指定名称。

#### `HarmonyManifest.ensureExtensionAbility(manifest, ability)`

按名称添加 ExtensionAbility。已有同名声明且字段兼容时不重复添加；同名声明字段冲突或重复时抛错。

#### `HarmonyResources.setString(file, item)`

按 `item.name` 添加或替换字符串资源并返回更新后的资源对象。`item` 需要包含合法的 `name` 和字符串 `value`；空字符串值有效。

#### `HarmonyResources.removeString(file, name)`

删除指定名称的字符串资源并返回更新后的资源对象。

#### `HarmonyResources.setColor(file, item)`

按 `item.name` 添加或替换颜色资源并返回更新后的资源对象。`item.value` 是 Harmony 颜色字符串。

#### `HarmonyResources.removeColor(file, name)`

删除指定名称的颜色资源并返回更新后的资源对象。

#### `HarmonyResources.toArgb(value)`

将 React Native 颜色字符串或无符号 32 位 RGBA 整数转换为 Harmony 颜色字符串并返回。`#RRGGBB` 会转为大写原样返回。

#### `atomicWrite(file, content)`

将字符串或 `Uint8Array` 写入文件，返回 `Promise<void>`。

#### `stableHarmonyJson(value)`

返回按键名排序、缩进两个空格并以换行结尾的 JSON 字符串。

#### `HarmonyPaths.assertNoExternalSymlink(root, target)`

检查目标路径是否留在 `root` 内；发现指向工程外部的符号链接时抛出路径错误。

#### `HarmonyPaths.isInside(root, target)`

判断 `target` 是否位于 `root` 内，返回布尔值。

#### `HarmonyPaths.resolveHarmonyPath(directory, relative)`

解析 Harmony 工程内的相对路径并返回绝对路径。拒绝绝对路径、越界路径和指向工程外部的符号链接。

#### `HarmonyPaths.resolveProjectPath(root, name)`

根据 `name` 解析 Expo 项目文件路径。`reactNativeConfig` 按 `react-native.config.js`、`.cjs`、`.ts`、`.mjs` 的顺序查找；均不存在时返回第一个候选路径。

#### `HarmonyPaths.toPosixRelative(root, target)`

返回以 `/` 分隔的相对路径字符串。

### Types

#### `HarmonyConfig` 与 `ExpoConfigWithHarmony`

`ExpoConfigWithHarmony` 是增加 `harmony` 配置和 `harmony` 平台类型的 Expo 配置。`harmony` 对象支持以下字段：

| 字段 | 类型 | 默认值或行为 |
| --- | --- | --- |
| `bundleName` | `string` | 必填；至少三段点分隔标识符 |
| `moduleName` | `string` | `entry` |
| `abilityName` | `string` | `EntryAbility` |
| `productName` | `string` | `default` |
| `vendor` | `string` | `expo-harmony` |
| `versionCode` | `number` | `1` |
| `versionName` | `string` | Expo 配置中的 `version`，默认 `1.0.0` |
| `runtimeVersion` | `string \| object` | 版本字符串或 `nativeVersion`、`sdkVersion`、`appVersion`、`fingerprint` 策略 |
| `targetSdkVersion` | `number \| string` | 默认 API 24；SDK 标签或 API 26 起的点分隔版本 |
| `compatibleSdkVersion` | `number \| string` | 默认 API 20；格式同 `targetSdkVersion` |
| `targetApiVersion` | `number` | 已弃用；未设置 `targetSdkVersion` 时仍可提供目标 API 级别 |
| `deviceTypes` | `string[]` | `['phone', 'tablet']` |
| `permissions` | `HarmonyPermission[]` | 默认包含 `ohos.permission.INTERNET` |
| `skills` | `HarmonySkill[]` | `scheme` 配置会追加对应的 URI 技能 |
| `querySchemes` | `string[]` | 默认包括 `http`、`https`、`tel`、`sms` 和 `scheme` 中的值 |
| `icon`、`label` | `string` | 分别取 Expo 配置的 `icon`、`name` |
| `backgroundColor` | `string` | Expo 配置中的 `backgroundColor`，默认 `#FFFFFF` |
| `orientation` | `string` | Expo 配置中的 `orientation`，默认 `default` |
| `userInterfaceStyle` | `'light' \| 'dark' \| 'automatic'` | Harmony 外观覆盖值，供相关插件读取 |
| `jsEngine` | `'hermes'` | 目前只接受 `hermes` |
| `abiFilters` | `string[]` | `['arm64-v8a', 'x86_64']` |
| `signingConfigFile` | `string` | 可选的签名配置文件路径 |
| `moduleBuilds` | `Record<string, Record<string, string \| number \| boolean>>` | 可选的原生模块构建选项 |

`HarmonyPlatform` 的值为 `harmony`；`ExpoHarmonyPlatform` 包含 Expo 已知平台及 `harmony`。

#### `HarmonyPermission`

权限声明包含必填的 `name` 和可选的 `reason`、`usedScene`。`usedScene` 支持 `abilities: string[]`、`when: 'inuse' | 'always'` 及 HarmonyOS 权限字段；未指定 `when` 时为 `inuse`。其他 HarmonyOS 声明字段会保留。

#### `HarmonySkill` 与 `HarmonySkillUri`

`HarmonySkill` 支持 `entities`、`actions` 和 `uris`；至少提供其中一项。`HarmonySkillUri` 的各字段值可以是字符串、数字或布尔值。

#### `HarmonyConfigPlugin<Props>`

配置插件函数类型，参数为 Expo Harmony 配置和可选插件参数 `Props`，返回同一配置类型。

#### `HarmonyModAction<T>` 与 `HarmonyModConfig<T>`

`HarmonyModAction<T>` 接收并返回 Mod 配置，可返回 Promise。`HarmonyModConfig<T>` 为 Harmony 平台的 Mod 配置类型：`modRawConfig` 包含 Harmony 配置，`modRequest.platform` 固定为 `harmony`；文件 Mod 可提供 `modRequest.modFile` 和 `modFileExists`。

#### `HarmonyModName` 与 `HarmonyJson`

`HarmonyModName` 是 `HARMONY_MOD_NAMES` 中 Mod 名称的联合类型。`HarmonyJson` 是 Harmony JSON 配置对象类型。

#### `HarmonyCompileOptions`

编译选项包含必填的 `projectRoot`，以及可选布尔值 `introspect`、`ignoreExistingNativeFiles`。

#### `HarmonyPluginReference` 与 `HarmonyStaticPlugin`

插件引用可以是包名或插件函数。静态插件也可以写成 `[插件引用, props]`。

#### Harmony 清单类型

`HarmonyModuleJson`、`HarmonyModule`、`HarmonyAbility`、`HarmonyExtensionAbility` 和 `HarmonyMetadata` 对应 Harmony `module.json5` 的结构。对象保留未列出的 HarmonyOS 字段，可用于扩展 SDK 字段。

#### Harmony 资源类型

`HarmonyResourceFile` 表示字符串或颜色资源文件；`HarmonyResourceItem` 包含资源 `name` 和字符串 `value`。`HarmonyResourceMap` 表示按作用域组织的资源对象。`HarmonyMediaDescriptor` 为 `{ source, content?, replaceBase? }` 或 `{ content, source?, replaceBase? }`，其中 `source` 与 `content` 二选一；`HarmonyMediaMap` 按作用域和文件名组织描述符。

#### 生成文件类型

`HarmonyFileDescriptor` 为 `{ source }` 或 `{ content }`，`HarmonyFileMap` 按目标相对路径映射描述符。`HarmonyGeneratedFilesOptions` 包含 `owner` 和 `files`。

#### 自定义文件类型

`HarmonyFileModOptions<T>` 包含 `path`、`owner`、`parse`、`serialize` 和可选的 `isIntrospective`。`HarmonyJsonFileOptions` 包含 `path`、`owner` 和接收 JSON 对象 Mod 配置的 `action`。

#### `HarmonyConfigPluginOwnership`

插件归属声明包含可选的 `files`、`ability` 和 `resources`。资源名称按 `strings`、`colors`、`media` 及其作用域列出；Ability 可声明 `startWindowBackground` 和 `startWindowIcon`。

#### `HarmonySdkVersion`

SDK 版本解析结果包含 `api` 和 `native` 字段，分别表示 API 级别和 Harmony SDK 版本标签。

#### `HarmonyConfigPluginError`

错误对象提供 `code`、`operation` 和可选的 `file`、`cause`。构造参数 `HarmonyConfigPluginErrorOptions` 支持 `cause`、`file`、`operation`。

### Error codes

| 错误码 | 触发情况 |
| --- | --- |
| `ERR_HARMONY_CONFIG_INVALID` | Expo Harmony 配置、SDK 版本、资源描述符或构建选项格式无效 |
| `ERR_HARMONY_MANIFEST_INVALID` | Harmony 模块清单或 Ability 声明格式无效、同名声明冲突 |
| `ERR_HARMONY_MOD_NOT_REGISTERED` | 注册了不存在或不可用的 Harmony Mod |
| `ERR_HARMONY_MOD_RESULTS_INVALID` | Mod 回调返回的 JSON、资源对象或文本类型不符合该 Mod 的要求 |
| `ERR_HARMONY_RESOURCE_INVALID` | 字符串或颜色资源项格式无效 |
| `ERR_HARMONY_RESOURCE_READ` | 无法读取 Harmony 媒体目录 |
| `ERR_HARMONY_PATH_INVALID` | 路径格式不支持，或目标由内置 Mod 管理 |
| `ERR_HARMONY_PATH_ESCAPE` | 路径超出 Harmony 工程，或符号链接指向工程外部 |
| `ERR_HARMONY_JSON5_INVALID` | Harmony JSON5 文件读取或解析失败 |
| `ERR_HARMONY_TEXT_INVALID` | Harmony 文本文件读取失败 |

### Permissions

#### `harmony.permissions`

权限项使用完整的 HarmonyOS 权限名，例如 `ohos.permission.INTERNET`。`reason` 可引用字符串资源，如 `$string:permission_reason`。`usedScene` 可声明使用时机和 Ability；同名权限合并时，`reason` 取后传入的值，`usedScene.abilities` 去重合并，`when: 'always'` 优先于 `inuse`。

#### `withHarmonyPermissions(config, permissions)`

将权限合并到 `expo.harmony.permissions`，并写入入口模块 `module.json5` 的 `requestPermissions`。该接口只处理应用的权限声明。

#### `HarmonyPermissions.mergePermissions(current, additions)`

按权限名称合并两个数组并返回新数组，不修改输入数组。

#### `HarmonyPermissions.ensurePermissions(manifest, additions)`

将权限合并到 manifest 的 `module.requestPermissions`，原地修改并返回 manifest。

#### `HarmonyPermissions.removePermissions(manifest, names)`

从 manifest 的 `module.requestPermissions` 删除指定权限名，原地修改并返回 manifest。
