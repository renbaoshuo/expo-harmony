# @expo-harmony/create-expo-module

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/create-expo-module)

为 HarmonyOS 平台提供 Expo 模块脚手架。包内提供独立的 `create-expo-harmony-module` 命令，命令名与官方的 `create-expo-module` 不同，两者可以在同一环境中共存。它可以从版本化模板创建可发布的独立模块包或应用内的 local 模块，也可以为已有的 Expo 模块补充 Harmony 平台支持。需要 Node.js 20 或更高版本。

## 用法

```sh
# 创建独立 npm 模块，默认生成到 ./expo-sensor
npx @expo-harmony/create-expo-module @acme/expo-sensor

# 创建应用内模块，默认生成到应用根目录的 modules/local-sensor
npx @expo-harmony/create-expo-module local-sensor --local

# 为已有模块补充 Harmony 支持，默认作用于当前目录
npx @expo-harmony/create-expo-module --add --path ../expo-sensor
```

完整命令行格式：

```
create-expo-harmony-module <name> [--local] [--path <directory>] [--sdk 55]
create-expo-harmony-module (--add | --add-to-existing) [--path <module-directory>] [--sdk 55]
```

| 选项                                   | 作用                                                                                      |
| -------------------------------------- | ----------------------------------------------------------------------------------------- |
| `<name>`                               | 新模块的 npm 包名，支持 scope；ArkTS 类名前缀、harmony 模块名和 bundleName 都由它推导     |
| `--local`                              | 创建应用内模块，生成到应用根目录的 `modules/<basename>`                                    |
| `--add`、`--add-to-existing`           | 为已有模块包补充 Harmony 支持，不能与 `--local` 同用                                       |
| `--path <directory>`                   | 指定目标目录，覆盖各模式的默认位置                                                         |
| `--sdk <major>`                        | 显式指定 Expo SDK 大版本，当前仅有 SDK 55 模板                                             |

不指定 `--sdk` 时，命令会从当前目录逐级向上读取 `package.json` 中的 `expo` 依赖版本来检测 SDK；检测不到时回退到 SDK 55 并输出提示。

## 创建独立模块

默认模式生成一个可直接发布的模块包，包含 TypeScript facade（`src/index.ts`）、`expo-module.config.json`、完整的 `harmony/` Hvigor HAR 工程，以及一个演示用法的 `example/` 应用。`package.json` 已配好 `harmony:clean`、`harmony:build`、`harmony:inspect`、`prepack` 等脚本和 npm 发布所需的 `files` 白名单，peer 依赖包含 `@expo-harmony/expo-modules-core`。

## 创建应用内模块

`--local` 会从当前目录向上查找最近的 `package.json` 来定位 Expo 应用根目录，并把模块生成到 `modules/<basename>`。相比独立模块，它是一个 `private` 包：根目录增加转发 `./src` 的 `index.ts`，并移除 `example/` 和发布相关文件，其余源码与独立模板一致。

## 为已有模块补充 Harmony 支持

`--add`（或 `--add-to-existing`）作用于一个已有的 Expo 模块包，目标目录默认为当前目录，也可以作为位置参数或通过 `--path` 传入，其中须包含 `package.json` 和 `expo-module.config.json`。命令会：

- 生成与独立模板相同的 `harmony/` 工程；
- 在 `expo-module.config.json` 的 `platforms` 中加入 `harmony`，并写入 `harmony` 配置；
- 补充 `harmony:clean`、`harmony:build`、`harmony:inspect` 脚本，已存在且内容不同的同名脚本会导致报错；
- 缺失时补上 peer 依赖 `@expo-harmony/expo-modules-core` 和开发依赖 `@expo-harmony/expo-module-scripts`，已存在则保持原样；若声明了 `files`，追加 HAR 发布产物路径。

若目标已存在 `harmony/` 目录，或 `expo-module.config.json` 已声明 `harmony`，命令会拒绝执行。

## 生成的模块

SDK 55 模板位于包内的 `templates/standalone` 和 `templates/local`。ArkTS 侧提供一个继承 `ExpoModule` 的模块类，在 `definition()` 中声明 constants、sync/async function、events、可扩展的 `ExpoSharedObject` 和默认 `ExpoView`（配合官方 `requireNativeViewManager` 使用）；不含模块级 C++、Provider、RNOH package class 和 CMake 目标。

TypeScript facade 基于官方 `expo-modules-core` 的 `requireNativeModule` 和 `requireNativeViewManager`，导出 `echo`、`echoAsync`、计数器 `SharedObject` 和原生 View 等示例 API。HAR 构建与发布校验由 `@expo-harmony/expo-module-scripts` 的 `expo-harmony-module` 命令完成，详见该包文档。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
