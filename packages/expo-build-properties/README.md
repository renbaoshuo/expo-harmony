# @expo-harmony/expo-build-properties

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-build-properties)

为 HarmonyOS 上的 React Native 应用提供 Expo Build Properties 的 HarmonyOS 构建配置，与官方同版本的 `expo-build-properties` 配套使用。

## 安装

本包适配 Expo SDK 57。

```sh
npm install @expo-harmony/expo-build-properties
```

## API 对照表

这是一个配置插件，不提供应用运行时 API。以下 API 用于 HarmonyOS 构建配置。

### Methods

#### `withBuildProperties`

HarmonyOS 构建属性配置插件。可选配置参数的类型为 [`PluginConfigType`](#pluginconfigtype)。

#### `withBuildPropertiesDefaults`

在 HarmonyOS 构建配置中应用该包的默认构建属性，不接收配置参数。

### Types

#### `PluginConfigType`

插件配置对象。`harmony` 可省略；其配置项见 [`HarmonyBuildProperties`](#harmonybuildproperties)。

#### `HarmonyBuildProperties`

`harmony` 对象支持以下配置项。

##### `compatibleSdkVersion`

应用兼容的最低 HarmonyOS SDK 版本，类型为 `number | string`，默认 API 20。该值须符合应用原生依赖的最低要求，且所选版本须由本机 DevEco 环境提供。

API 13、14、20、21、23 和 24 可用数字表示，也可写为带 API 级别的完整 SDK 版本字符串，例如 `24` 或 `"6.1.1(24)"`。其他低于 API 26 的版本需使用完整版本字符串。API 26 起可使用数字或点分隔版本字符串，例如 `26`、`"26.0.0"` 或 `"26.1.0"`。

##### `targetSdkVersion`

应用目标 HarmonyOS SDK 版本，类型和版本格式与 `compatibleSdkVersion` 相同，默认 API 24。

##### `abiFilters`

指定要构建的原生库 CPU 架构，类型为 `string[]`，默认值为 `["arm64-v8a", "x86_64"]`。Hvigor 支持的架构包括 `arm64-v8a` 和 `x86_64`。

##### `nativeCompiler`

指定 C/C++ 原生编译器名称，类型为 `string`，默认值为 `"BiSheng"`。

##### `nativeLib.filter`

原生 `.so` 文件筛选规则，类型为 [`NativeLibFilter`](#nativelibfilter)。筛选语法遵循 [Hvigor 原生库配置](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-cpp)，例如 `"**/libexample.so"`。

##### `compressNativeLibs`

是否将 `.so` 库压缩后打包进 HAP，类型为 `boolean`，默认值为 `false`。

##### `extractNativeLibs`

安装时是否将 `.so` 库解压到应用安装目录，类型为 `boolean`，默认值为 `true`。从 HarmonyOS API 20 起支持此配置。`compressNativeLibs` 和 `extractNativeLibs` 同时设为 `false` 时，应用安装时不解压 `.so` 库。详见 [模块配置文件](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/module-configuration-file/)。

##### `release.debugSymbol`

设置 release 构建的 `.so` 符号处理，类型为 [`DebugSymbol`](#debugsymbol)。未指定时保留已有构建设置；若没有已有设置，则使用 Hvigor 的默认值。

##### `release.obfuscation`

设置 release 构建的 ArkTS 混淆，支持 `enable: boolean` 和可选的 `files: string[]`。`enable` 为必填项；`files` 指定混淆规则文件路径，可使用相对于应用根目录的路径或绝对路径。未指定此项时不新增混淆设置。规则语法参见[ArkTS 混淆配置](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-build-obfuscation)。

##### `compileSdkVersion`

- 不提供此配置项；编译 SDK 使用 DevEco 配套 SDK 的默认版本。

#### `NativeLibFilter`

`nativeLib.filter` 的筛选字段。

##### `excludes`

匹配的 `.so` 文件不会打入 HAP，类型为 `string[]`。

##### `pickFirsts`

匹配的 `.so` 文件优先打包，类型为 `string[]`。

##### `pickLasts`

匹配的 `.so` 文件最后打包，类型为 `string[]`。

##### `enableOverride`

同名 `.so` 文件存在优先级差异时，是否允许高优先级文件覆盖低优先级文件，类型为 `boolean`，默认值为 `false`。

#### `DebugSymbol`

release 构建的 `.so` 符号处理字段。Hvigor 配置详情见[原生库配置](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-cpp)。

##### `strip`

是否剥离符号表和调试信息，类型为 `boolean`。未指定时沿用 Hvigor 默认值。

##### `exclude`

匹配的 `.so` 文件符号保留或剥离，类型为 `string[]`。`strip: true` 时，匹配项保留符号；`strip: false` 时，仅剥离匹配项的符号。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
