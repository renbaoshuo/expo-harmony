# @expo-harmony/config-plugins

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/config-plugins)

这个包定义 `expo.harmony` 的字段和默认值，并提供读写 Harmony 原生工程的 Mod、资源与权限操作，以及插件生成文件的归属管理。

## 安装

```sh
npm install @expo-harmony/config-plugins
```

## 声明 HarmonyOS 配置

用 `defineExpoHarmonyConfig` 在 `app.config.js` 里写配置：

```js
const { defineExpoHarmonyConfig } = require('@expo-harmony/config-plugins');

module.exports = defineExpoHarmonyConfig({
  name: 'Example',
  slug: 'example',
  platforms: ['ios', 'android', 'harmony'],
  plugins: ['@expo-harmony/prebuild-config'],
  harmony: {
    bundleName: 'com.example.app',
    versionCode: 1,
  },
});
```

`defineExpoHarmonyConfig` 里的 `harmony` 字段可以写这些配置：

| 字段 | 默认值 / 说明 |
| --- | --- |
| `bundleName` | 必填，至少三段点分隔的合法标识符 |
| `moduleName` | `entry` |
| `abilityName` | `EntryAbility` |
| `productName` | `default` |
| `vendor` | `expo-harmony` |
| `versionCode` | `1` |
| `versionName` | 配置里的 `version`，没有则 `1.0.0` |
| `targetApiVersion` | `24` |
| `targetSdkVersion` | 数字或 SDK 标签，默认跟随 `targetApiVersion` |
| `compatibleSdkVersion` | `13`，不能低于 13，也不能大于 `targetApiVersion` |
| `deviceTypes` | `['phone', 'tablet']` |
| `permissions` | 权限列表，默认包含 `ohos.permission.INTERNET` |
| `skills` | 技能列表，`scheme` 会追加对应项 |
| `querySchemes` | 默认包含 `http`、`https`、`tel`、`sms` 和 `scheme` |
| `icon` | 配置里的 `icon` |
| `label` | 配置里的 `name` |
| `backgroundColor` | 配置里的 `backgroundColor`，没有则 `#FFFFFF` |
| `orientation` | 配置里的 `orientation`，没有则 `default` |
| `userInterfaceStyle` | 供 `expo-system-ui` 和 `expo-splash-screen` 插件读取的 HarmonyOS 外观覆盖值，由模块插件校验和应用 |
| `jsEngine` | `hermes` |
| `abiFilters` | `['arm64-v8a', 'x86_64']` |
| `signingConfigFile` | 签名配置文件路径，不设置则忽略 |

`targetSdkVersion` 和 `compatibleSdkVersion` 可以写数字或带 API 级别的 SDK 标签。内置标签覆盖 API 13、14、20、21、23、24，其他版本写成 `6.1.1(24)` 这样的形式。`backgroundColor` 写 `#RRGGBB` 或 `#RRGGBBAA`，写入原生工程时转成 ARGB。`jsEngine` 目前只能是 `hermes`。

`normalizeHarmonyConfig(config)` 返回补齐默认值并校验后的配置。

## 修改原生工程文件

Mod 读写原生工程里的文件。以 `module.json5` 为例：

```js
const { withModuleJson } = require('@expo-harmony/config-plugins');

module.exports = function withExampleMetadata(config) {
  return withModuleJson(config, (mod) => {
    const moduleConfig = mod.modResults.module || {};
    const metadata = Array.isArray(moduleConfig.metadata) ? moduleConfig.metadata : [];

    mod.modResults.module = {
      ...moduleConfig,
      metadata: [...metadata, { name: 'example.enabled', value: 'true' }],
    };
    return mod;
  });
};
```

回调在 `mod.modResults` 上读写并返回 `mod`。JSON 文件的 `modResults` 是对象，文本文件是字符串，返回结果写回文件。同一个 Mod 注册多次时，后注册的回调先执行。需要读最终原始配置时用 `mod.modRawConfig`。

内置 Mod 与目标文件：

| 接口                       | 文件                                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `withAppJson`              | `AppScope/app.json5`                                                                                          |
| `withProjectBuildProfile`  | `build-profile.json5`                                                                                         |
| `withRootOhPackage`        | `oh-package.json5`                                                                                            |
| `withHvigorConfig`         | `hvigor/hvigor-config.json5`                                                                                  |
| `withEntryBuildProfile`    | `entry/build-profile.json5`                                                                                   |
| `withEntryOhPackage`       | `entry/oh-package.json5`                                                                                      |
| `withModuleJson`           | `entry/src/main/module.json5`                                                                                 |
| `withProfiles`             | `entry/src/main/resources/base/profile/main_pages.json`                                                       |
| `withReactNativeConfig`    | `react-native.config.js`                                                                                      |
| `withRootHvigor`           | `hvigorfile.ts`                                                                                               |
| `withEntryHvigor`          | `entry/hvigorfile.ts`                                                                                         |
| `withEntryAbility`         | `entry/src/main/ets/entryability/EntryAbility.ets`                                                            |
| `withIndexPage`            | `entry/src/main/ets/pages/Index.ets`                                                                          |
| `withWorker`               | `entry/src/main/ets/workers/RNOHWorker.ets`                                                                   |
| `withArkTSPackageProvider` | `entry/src/main/ets/PackageProvider.ets`                                                                      |
| `withCppPackageProvider`   | `entry/src/main/cpp/PackageProvider.cpp`                                                                      |
| `withCMakeLists`           | `entry/src/main/cpp/CMakeLists.txt`                                                                           |
| `withStrings`              | `AppScope/resources/base/element/string.json`、`entry/src/main/resources/base/element/string.json`            |
| `withColors`               | `entry/src/main/resources/base/element/color.json`、`entry/src/main/resources/dark/element/color.json`        |
| `withMedia`                | `AppScope/resources/base/media`、`entry/src/main/resources/base/media`、`entry/src/main/resources/dark/media` |

`withHarmonyMod(config, [name, action])` 按名称注册 Mod，`HARMONY_MOD_NAMES` 列出可用名称。`withHarmonyResources` 把同一个 action 注册到 strings、colors、media。`withHarmonyDangerousMod` 用来改写没有固定目标文件的内容。`withHarmonyAutolinking` 执行原生模块自动链接。`withHarmonyBaseMods` 注册整套 Harmony Base Mod。

`compileHarmonyModsAsync(config, { projectRoot, introspect?, ignoreExistingNativeFiles? })` 直接执行 Mods。`introspect: true` 时只跑静态 Mod，不写文件，结果保存在 `_internal.modResults.harmony`，自定义文件以 `file:<相对路径>` 为键。从 `expo/config` 读配置时要设 `isModdedConfig: true`，否则 Mods 会丢失。

`HarmonyPaths` 提供工程内路径常量（`HARMONY_PATHS`、`PROJECT_PATHS`、`PROJECT_PATH_CANDIDATES`、`RESOURCE_PATHS`）和路径解析、边界检查函数。

## Manifest

`HarmonyManifest` 原地修改和查询 `module.json5`：

- `getModuleOrThrow(manifest)` 读取 `module`，缺失或格式不对时抛错。
- `getMainAbilityOrThrow(manifest, name?)` 按显式名称、`mainElement`、第一个 Ability 的顺序选取，目标缺失或重名时抛错。
- `setMetadata(target, item)`、`removeMetadata(target, name)` 按名称更新 module 或 Ability 的 metadata，保留其他条目和字段。
- `ensureExtensionAbility(manifest, ability)` 添加 ExtensionAbility，重复调用不会追加，同名声明存在不兼容字段时抛错。

`withModuleJson` 的结果是 `HarmonyModuleJson`。`HarmonyModule`、`HarmonyAbility`、`HarmonyExtensionAbility`、`HarmonyMetadata` 保留未知字段，可以使用新 SDK 的字段。`HarmonySkillUri` 的值可以是字符串、数字或布尔值。

```js
const { HarmonyManifest, withModuleJson } = require('@expo-harmony/config-plugins');

function withExample(config) {
  return withModuleJson(config, (mod) => {
    const module = HarmonyManifest.getModuleOrThrow(mod.modResults);
    HarmonyManifest.setMetadata(module, { name: 'example.enabled', value: 'true' });

    const ability = HarmonyManifest.getMainAbilityOrThrow(mod.modResults);
    ability.backgroundModes = [...new Set([...(ability.backgroundModes || []), 'audioPlayback'])];
    return mod;
  });
}
```

## 权限

`withHarmonyPermissions(config, permissions)` 把权限合并进 `expo.harmony.permissions` 和生成的 `module.json5`。权限名用完整的 `ohos.permission.*`。同名权限合并 `usedScene.abilities`，任一声明要求 `always` 就保留 `always`，后传入的 `reason` 覆盖旧值。`reason` 写 `$string:...` 这样的原生引用，文案放在字符串资源里。

`HarmonyPermissions.mergePermissions(current, additions)` 返回合并后的新数组。`ensurePermissions(manifest, additions)` 和 `removePermissions(manifest, names)` 修改并返回 manifest。删除只改应用 manifest 里列出的声明，不会动 HAR 自己声明的权限。

## 字符串、颜色和媒体

`HarmonyResources.setString(file, { name, value })`、`removeString(file, name)`、`setColor`、`removeColor` 原地修改单个资源 JSON 对象并返回，按名称去重，保留其他内容。空字符串是合法值，删除要显式调用 remove。

```js
const { HarmonyResources, registerHarmonyConfigPlugin, withStrings } = require('@expo-harmony/config-plugins');

function withExampleReason(config, reason) {
  config = registerHarmonyConfigPlugin(config, 'example-plugin', {
    resources: { strings: { entry: ['example_permission_reason'] } },
  });
  return withStrings(config, (mod) => {
    const entry = (mod.modResults.entry ??= {});
    HarmonyResources.setString(entry, { name: 'example_permission_reason', value: reason });
    return mod;
  });
}
```

`setColor` 接收原生颜色值，不改通道顺序。`HarmonyResources.toArgb` 把 `#RRGGBB`、Expo 的 `#RRGGBBAA` 或无符号 RGBA 整数转成 Harmony 颜色。命名颜色先用调用方的颜色解析器转成 RGBA 整数。

`withStrings` 改的是 `app` 和 `entry`，`withColors` 改的是 `entry` 和 `entryDark`。`withMedia` 在 `app`、`entry` 或 `entryDark` 里按文件名设置 `{ source }` 或 `{ content }`，`replaceBase: true` 会替换同基本名的其他扩展名。

## Rawfile 和生成文件

```js
const { withRawfile, withHarmonyGeneratedFiles } = require('@expo-harmony/config-plugins');

function withExampleFiles(config) {
  config = withRawfile(config, {
    owner: 'example-plugin',
    files: {
      'audio/example.wav': { source: './assets/example.wav' },
      'example.json': { content: JSON.stringify({ enabled: true }) },
    },
  });
  return withHarmonyGeneratedFiles(config, {
    owner: 'example-plugin',
    files: {
      'entry/src/main/ets/example/Example.ets': { content: 'export const enabled = true;\n' },
    },
  });
}
```

`withRawfile` 的路径相对 `entry/src/main/resources/rawfile`，`withHarmonyGeneratedFiles` 的路径相对 Harmony 工程根目录。路径用 `/`，不接受绝对路径、`.`、`..` 和指向工程外的符号链接。`source` 相对 Expo 项目根目录，也可以用绝对路径；`content` 是字符串或 `Uint8Array`，和 `source` 二选一。

两个接口会覆盖自己声明的目标文件，执行时读取源文件，先校验整批输入再原子写入，并登记文件归属。introspection 阶段不写文件。多个插件不能声明同一个目标路径，同一个 owner 的多次调用合并成这次配置的完整文件集合。

配合 `@expo-harmony/prebuild-config` 时，下次生成会清掉同一 owner 不再声明的旧文件，卸载插件会清理它管理的文件。字体这类需要动态计算的场景可以用 `withHarmonyDangerousMod`、`atomicWrite` 和 `recordManagedFile`。

## 自定义文件

`withHarmonyJsonFile` 管理一个 JSON 或 JSON5 文件：

```js
const { withHarmonyJsonFile } = require('@expo-harmony/config-plugins');

module.exports = (config) =>
  withHarmonyJsonFile(config, {
    path: 'entry/src/main/resources/zh_CN/element/string.json',
    owner: 'my-library/locales',
    action: (mod) => {
      mod.modResults.string = [{ name: 'my_message', value: '你好' }];
      return mod;
    },
  });
```

一个文件由一个 owner 管理。其他插件用相同的 `path` 和 `owner` 继续修改时，文件只读写一次；不同 owner 声明同一路径会报错。多个插件改资源数组时按名称合并，避免覆盖别人的条目。

`createHarmonyFileMod({ path, owner, parse, serialize, isIntrospective? })` 用来定义其他文本格式，返回和 `withModuleJson` 一样接收 `(config, action)` 的函数。`parse` 接收文件内容或表示文件不存在的 `null`，`serialize` 返回字符串，两者是纯函数。序列化对象时可以用 `stableHarmonyJson`，它按固定键序输出。定义一次并导出，供其他插件复用。只有静态、可 JSON 序列化、不产生文件副作用的 Mod 才能设 `isIntrospective: true`，JSON 快捷接口已经开启。

provider 会校验路径、登记归属并原子写入，移除 provider 后 prebuild 会清理它生成的文件。它管理整个文件，不会单独撤销某个 action 对字段的修改。内置 Mod 已经管理的路径不能再声明。

## 声明文件与资源归属

`registerHarmonyConfigPlugin(config, owner, claims)` 声明插件占用的文件和资源名。`files` 是相对路径列表，`resources` 按 `strings`、`colors`、`media` 分组，每组再按作用域列出名称，`ability` 现在能写 `startWindowBackground` 和 `startWindowIcon`。不同 owner 声明同一个文件会报错。

```js
const { registerHarmonyConfigPlugin } = require('@expo-harmony/config-plugins');

module.exports = (config) =>
  registerHarmonyConfigPlugin(config, 'my-plugin', {
    files: ['entry/src/main/resources/base/profile/shortcuts.json'],
    resources: {
      colors: { entry: ['brand_primary'] },
      strings: { app: ['app_display_name'] },
    },
  });
```

`recordManagedFile(config, file, owner)` 单独登记一个受管理文件，适合动态生成的文件。

## 插件组合

`withPlugins`、`withRunOnce`、`withStaticPlugin`、`createRunOncePlugin` 可以写 `platforms: ['harmony']`，并保留调用方的配置类型。其他 Expo 通用工具从项目的 `expo/config-plugins` 取。

## 类型

`HarmonyConfigPlugin<Props>` 保留传入配置的具体类型，可以写 `platforms: ['harmony']`。`HarmonyModAction<T>` 和 `HarmonyModConfig<T>` 里的 Harmony 配置、`modRawConfig.harmony`、`modRequest.platform: 'harmony'` 和结果都有类型。文件 Mod 还能读到可选的 `modRequest.modFile` 和 `modFileExists`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
