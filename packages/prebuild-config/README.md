# @expo-harmony/prebuild-config

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/prebuild-config)

为 Expo 项目生成 HarmonyOS 原生工程。读取 `expo.harmony` 配置，写入 AppScope、Entry 模块、资源、Hvigor 配置、CMake 和 RNOH 宿主代码，并完成原生模块自动链接。

## 安装

```sh
npm install @expo-harmony/prebuild-config
```

应用还需要 `@react-native-oh/react-native-harmony` 和 `@react-native-oh/react-native-harmony-cli`，以及用来运行和构建的 `@expo-harmony/cli`。

## 快速开始

在 `app.json` 里注册插件：

```json
{
  "expo": {
    "name": "Example",
    "slug": "example",
    "version": "1.0.0",
    "platforms": ["ios", "android", "harmony"],
    "plugins": ["@expo-harmony/prebuild-config"],
    "harmony": {
      "bundleName": "com.example.app",
      "versionCode": 1,
      "deviceTypes": ["phone", "tablet"]
    }
  }
}
```

`bundleName` 必填，其余字段有默认值。完整列表见 [@expo-harmony/config-plugins](../config-plugins/README.md)。

生成或更新原生工程：

```sh
npx expo-harmony prebuild
```

工程写入项目根目录下的 `harmony`。`--clean` 先删除再重新生成，`--check` 只比较差异，不修改文件。

## 生成内容

| 文件                                   | 内容                                                |
| -------------------------------------- | --------------------------------------------------- |
| `AppScope/app.json5`                   | 包名、版本号、vendor、应用名和图标引用              |
| `build-profile.json5`                  | product、module、SDK 版本、ABI 和签名配置           |
| `entry/build-profile.json5`            | Entry 模块的 CMake 路径和 ABI                       |
| `entry/src/main/module.json5`          | module、Ability、设备类型、权限和 querySchemes      |
| `entry/src/main/resources/`            | 字符串、颜色和 media 资源                           |
| `oh-package.json5`                     | RNOH 运行时依赖                                     |
| `hvigor/hvigor-config.json5`           | RNOH Hvigor 插件依赖                                |
| `hvigorfile.ts`、`entry/hvigorfile.ts` | Hvigor 构建脚本                                     |
| `entry/src/main/ets/`                  | EntryAbility、Index 页面、Worker 和 PackageProvider |
| `entry/src/main/cpp/`                  | PackageProvider.cpp 和 CMakeLists.txt               |
| `react-native.config.js`               | RNOH 的 link-harmony 命令                           |

## 应用图标

`harmony.icon` 指定图标文件，支持 PNG、JPG、SVG 和 WebP。文件写入 AppScope 和 Entry 模块的 media 资源，替换同基本名的 `app_icon`。不设置时用模板自带的图标。

## 权限

`harmony.permissions` 里的权限写入 `module.json5` 的 `requestPermissions`，权限名用 `ohos.permission.*`。同名权限合并 `usedScene.abilities`，后写入的 `reason` 覆盖旧值。`reason` 写成 `$string:...` 引用，文案放在字符串资源里。

## 自动链接

prebuild 发现项目里支持 Harmony 的 Expo 模块，把模块信息和依赖写进工程，构建时由 Hvigor 和 CMake 链接。`buildType` 选项选择自动链接的构建模式：

```json
{
  "expo": {
    "plugins": [["@expo-harmony/prebuild-config", { "buildType": "release" }]]
  }
}
```

未指定时读取 `EXPO_HARMONY_BUILD_TYPE`，默认 `debug`。自动链接始终启用。

## 签名配置

`harmony.signingConfigFile` 指向一个 JSON5 文件，内容是一个签名配置对象，或一个 `signingConfigs` 数组。数组有多项时，其中一项要命名为 `default`。

```json5
{
  name: 'default',
  type: 'HarmonyOS',
  material: {
    certpath: './signing/app.cer',
    storePassword: '...',
    keyAlias: '...',
    keyPassword: '...',
    profile: './signing/app.p7b',
    signAlg: 'SHA256withECDSA',
    storeFile: './signing/app.p12',
  },
}
```

`material` 的七个字段都是必填的非空字符串，`signAlg` 固定为 `SHA256withECDSA`，`certpath`、`profile` 和 `storeFile` 指向真实文件。这些文件和签名配置文件本身要放在 `harmony` 目录之外，否则 `prebuild --clean` 会删掉它们。配置里的相对路径按签名配置文件所在目录解析。生成的 `build-profile.json5` 引用配置的 `name`，没有配置时不写签名。

## 插件顺序

默认配置在执行阶段读取最终的 app config，其他 Harmony 配置插件可以放在本包前面或后面。要覆盖默认值，把本包放到插件列表最后：

```json
{
  "expo": {
    "plugins": [
      "@expo-harmony/expo-font",
      [
        "@expo-harmony/expo-splash-screen",
        {
          "image": "./assets/splash.png",
          "backgroundColor": "#FFFFFF"
        }
      ],
      "@expo-harmony/expo-system-ui",
      "@expo-harmony/prebuild-config"
    ]
  }
}
```

默认导出和具名导出 `withHarmonyPrebuildConfig` 是同一个插件，重复注册只生效一次。

## 文件清理

再次 prebuild 时，插件不再声明的文件会被删除；卸载插件后，它管理的文件也会清理。

## 原生补丁

用 [`@expo-harmony/patch-project`](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/patch-project) 保存原生修改，并在 prebuild 时自动恢复。

## 读取配置

`getPrebuildConfigAsync(projectRoot)` 读取静态或动态 app config，执行已声明的配置插件，返回 `HarmonyProjectConfig`。它不生成原生工程。

```ts
import { getPrebuildConfigAsync } from '@expo-harmony/prebuild-config';

const project = await getPrebuildConfigAsync(projectRoot);
```

`withHarmonyPrebuildConfig` 是插件本身，可以带 `HarmonyPrebuildOptions` 手动组合。`HarmonyPrebuildError` 带有 `code`、`operation` 和 `file`，用于识别预构建失败的原因。

## 与上游 Expo 的分工

HarmonyOS 的工程生成由本包负责，iOS 和 Android 仍使用 Expo 上游的预构建。此外，上游面向旧版应用的自动插件列表不适用于 HarmonyOS，模块插件要在应用里显式声明。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
