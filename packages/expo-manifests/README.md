# @expo-harmony/expo-manifests

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-manifests) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/manifests/)

为 HarmonyOS 上的 React Native 应用提供 Expo Manifests 的原生实现，与官方同版本的 `expo-manifests` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-manifests
```

## API 对照表

### Methods

#### `Manifest.fromManifestJson(value)`

参数 `value` 为 JSON 清单对象；返回 `ExpoUpdatesManifest` 或 `EmbeddedManifest`。存在 `metadata` 字段时按远程更新清单读取，否则按内置清单读取。根值无效或包含 `releaseId` 时会抛出 `ExpoManifestError`；其他必需字段和字段类型在对应方法读取时检查，错误码为 `ERR_MANIFEST_INVALID`。

- 带有 `releaseId` 字段的旧格式清单不受支持，调用会抛出 `ExpoManifestError`。

#### `Manifest.getRawJson()`

返回原始 JSON 清单对象，类型为 `object`。

#### `Manifest.toString()`

返回 JSON 清单的字符串表示，类型为 `string`。

#### `Manifest.getID()`

返回必需的清单 ID（`id`），类型为 `string`。

#### `Manifest.getLegacyID()`

返回 `getID()` 的结果，类型为 `string`。

#### `Manifest.getMetadata()`

返回 `metadata` 对象，类型为 `object | null`；字段不存在时返回 `null`。

#### `Manifest.getAssets()`

返回 `assets` 数组，类型为 `unknown[] | null`；字段不存在时返回 `null`。

#### `Manifest.isVerified()`

返回 `isVerified` 布尔值；字段不存在时返回 `false`。

#### `Manifest.getStableLegacyID()`

远程更新清单返回 `null`；内置清单返回 `originalFullName`，缺少该字段时返回清单 ID。

#### `Manifest.getScopeKey()`

远程更新清单从 `extra.scopeKey` 返回必需的项目隔离标识；内置清单返回 `scopeKey`，缺少时使用稳定旧 ID。

#### `Manifest.getEASProjectID()`

远程更新清单读取 `extra.eas.projectId`，内置清单读取 `projectId`。字段缺失时返回 `null`。

#### `Manifest.getBundleURL()`

远程更新清单返回 `launchAsset.url`；内置清单返回必需的 `bundleUrl`。

#### `Manifest.getExpoGoSDKVersion()`

远程更新清单从 Expo 客户端配置读取 `sdkVersion`；内置清单读取根字段 `sdkVersion`。字段缺失时返回 `null`。

#### `Manifest.getExpoGoConfigRootObject()`

远程更新清单返回 `extra.expoGo` 对象，缺失时返回 `null`；内置清单返回根清单对象。

#### `Manifest.getExpoClientConfigRootObject()`

远程更新清单返回 `extra.expoClient` 对象，缺失时返回 `null`；内置清单返回根清单对象。

#### `Manifest.getSlug()`

内置清单返回 `slug`，缺失时返回 `null`。

- 远程更新清单没有 `slug` 字段，因此返回 `null`。

#### `Manifest.getAppKey()`

内置清单返回 `appKey`，缺失时返回 `null`。

- 远程更新清单没有 `appKey` 字段，因此返回 `null`。

#### `Manifest.isDevelopmentMode()`

仅当 Expo Go 配置包含 `developer` 且 `packagerOpts.dev` 为 `true` 时返回 `true`；其他情况返回 `false`。

#### `Manifest.isDevelopmentSilentLaunch()`

当 Expo Go 配置中的 `developmentClient.silentLaunch` 为 `true` 时返回 `true`；字段缺失时返回 `false`。

#### `Manifest.isUsingDeveloperTool()`

当 Expo Go 配置中的 `developer.tool` 存在时返回 `true`，否则返回 `false`。

#### `Manifest.getRevisionId()`

返回 Expo 客户端配置中的必需字符串 `revisionId`。

#### `Manifest.getDebuggerHost()`

返回 Expo Go 配置中的必需字符串 `debuggerHost`。

#### `Manifest.getMainModuleName()`

Expo Go 配置不存在时返回 `main`；配置存在时返回其中的必需字符串 `mainModuleName`。

#### `Manifest.getHostUri()`

返回 Expo 客户端配置中的 `hostUri`，类型为 `string | null`；字段缺失时返回 `null`。

#### `Manifest.getExpoGoUsername()`

返回 Expo Go 配置中的 `username`，类型为 `string | null`；字段缺失时返回 `null`。

#### `Manifest.getName()`

返回 Expo 客户端配置中的 `name`，类型为 `string | null`；字段缺失时返回 `null`。

#### `Manifest.getVersion()`

返回 Expo 客户端配置中的 `version`，类型为 `string | null`；字段缺失时返回 `null`。

#### `Manifest.getUpdatesInfo()`

返回 Expo 客户端配置中的 `updates` 对象，类型为 `object | null`；字段缺失时返回 `null`。

#### `Manifest.getPrimaryColor()`

返回 Expo 客户端配置中的 `primaryColor`，类型为 `string | null`；字段缺失时返回 `null`。

#### `Manifest.getOrientation()`

返回 Expo 客户端配置中的 `orientation`，类型为 `string | null`；字段缺失时返回 `null`。

#### `Manifest.getIconUrl()`

返回 Expo 客户端配置中的 `iconUrl`，类型为 `string | null`；字段缺失时返回 `null`。

#### `Manifest.getFacebookAppId()`

返回 Expo 客户端配置中的必需字符串 `facebookAppId`。

#### `Manifest.getFacebookApplicationName()`

返回 Expo 客户端配置中的必需字符串 `facebookDisplayName`。

#### `Manifest.getFacebookAutoInitEnabled()`

返回 Expo 客户端配置中的必需布尔值 `facebookAutoInitEnabled`。

#### `Manifest.getPlatformConfig()`

返回 Expo 客户端配置中的 `harmony` 对象，类型为 `object | null`；字段缺失时返回 `null`。

#### `Manifest.getUserInterfaceStyle()`

优先返回 `harmony.userInterfaceStyle`，缺少时读取 Expo 客户端配置中的 `userInterfaceStyle`；均缺失时返回 `null`。返回类型为 `string | null`。

#### `Manifest.getBackgroundColor()`

优先返回 `harmony.backgroundColor`，缺少时读取 Expo 客户端配置中的 `backgroundColor`；均缺失时返回 `null`。返回类型为 `string | null`。

#### `Manifest.getPluginProperties(name)`

参数 `name` 为插件名称。返回匹配插件配置的属性对象，类型为 `object | null`；没有匹配项或未提供属性时返回 `null`。插件配置格式无效时会抛出 `ExpoManifestError`。

#### `ExpoUpdatesManifest.getRuntimeVersion()`

返回远程更新清单中的必需字符串 `runtimeVersion`。

#### `ExpoUpdatesManifest.getCreatedAt()`

返回远程更新清单中的必需字符串 `createdAt`。

#### `ExpoUpdatesManifest.getLaunchAsset()`

返回远程更新清单中的 `launchAsset` 对象。

#### `EmbeddedManifest.getCommitTimeLong()`

返回内置清单的 `commitTime` 整数。小数部分会截去；超出安全整数范围或无法转换为整数时会抛出 `ExpoManifestError`。

### Types

#### `ManifestAsset`

清单资源，包含必需的 `url: string`。

#### `ExpoClientConfig`

Expo 应用配置，另含可选的 `hostUri: string`。

#### `ClientScopingConfig`

可选的 `scopeKey: string`，用于标识项目。

#### `EASConfig`

可选的 `projectId: string`。

#### `ManifestExtra`

包含 `ClientScopingConfig` 字段，以及可选的 `expoClient`、`expoGo` 和 `eas` 配置。

#### `ExpoGoConfig`

Expo Go 配置，包含可选的 `mainModuleName`、`debuggerHost`、`developer` 和 `packagerOpts` 字段。

#### `ExpoGoPackagerOpts`

打包器配置，包含可选的 `hostType`、`dev`、`strict`、`minify`、`urlType`、`urlRandomness` 和 `lanType` 字段。

#### `ExpoUpdatesManifest`

远程更新清单类型，包含 `id`、`createdAt`、`runtimeVersion`、`launchAsset`、`assets` 和 `metadata`；`extra` 可选。

#### `EmbeddedManifest`

内置清单类型，包含 `id`、`commitTime` 和 `assets`。

#### `NewManifest`

`ExpoUpdatesManifest` 的旧别名，已废弃。

#### `BareManifest`

`EmbeddedManifest` 的旧别名，已废弃。

#### `ExpoManifestError`

清单读取失败时抛出的错误，继承自 `Error`；`name` 为 `ExpoManifestError`，`code` 为 `ERR_MANIFEST_INVALID`。

### Error codes

| 错误码 | 触发条件 |
| --- | --- |
| `ERR_MANIFEST_INVALID` | 清单对象无效、必需字段缺失或字段类型不符、旧格式清单不受支持，或内置清单的 `commitTime` 无效。 |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
