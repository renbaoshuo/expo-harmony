# @expo-harmony/cli

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/cli)

为 Expo 项目提供 HarmonyOS 平台的命令行工具，支持 CNG 原生工程生成、环境诊断、Harmony Expo Module 发现与校验、生产 Bundle 导出，以及 HAP 的构建、安装和启动。

## 安装

```sh
npm install --save-dev @expo-harmony/cli
```

CLI 必须安装在项目本地，JS 打包调用项目内的 Expo CLI，Hermes 字节码编译调用项目内的 `@expo/metro-config`，Release 原生构建也会回调项目本地的 `expo-harmony` 二进制生成 Bundle。

项目需要 Node.js 20 或更高版本，在 Expo 配置中注册 `@expo-harmony/prebuild-config` 插件，并使用 `@expo-harmony/metro-config` 组合 Metro 配置。

HAP 构建需要完整的 HarmonyOS SDK（含 HMS 与 OpenHarmony 组件）、OHPM、Hvigor 和 HDC，这些环境可用 `doctor` 命令检查。

## 命令

| 命令 | 作用 |
| --- | --- |
| `expo-harmony prebuild` | 使用 Expo CNG 生成或更新 HarmonyOS 原生工程 |
| `expo-harmony prebuild --clean` | 安全删除并重新生成受管理的 `harmony` 目录 |
| `expo-harmony prebuild --check` | 在隔离目录中生成期望状态并比较差异，不修改项目文件 |
| `expo-harmony build` | 构建 HAP，不选择设备，也不安装或启动应用 |
| `expo-harmony doctor` | 检查配置、依赖版本、Metro、RNOH、SDK、构建工具和签名 |
| `expo-harmony modules list` | 列出发现的 Harmony Expo Module 候选及其来源 |
| `expo-harmony modules inspect` | 展示模块解析后的 Harmony 元数据，如 HAR 与 ArkTS modules |
| `expo-harmony modules verify` | 检查 canonical metadata、应用级 registration/OHPM 冲突、路径边界和约定产物 |
| `expo-harmony export:embed` | 导出 Hermes 字节码、资源和 Source Map 并写入原生工程 |
| `expo-harmony run` | 构建 HAP，在连接的 HarmonyOS 设备上安装并启动应用 |

所有命令都可接收可选的项目路径（`modules` 命令写在子命令之后）；未提供时从当前目录向上查找最近的项目根目录作为默认值：

```sh
npx expo-harmony doctor ./my-app
npx expo-harmony prebuild ./my-app
npx expo-harmony build ./my-app --variant release
npx expo-harmony run ./my-app --device <hdc-target>
```

## Prebuild

```sh
npx expo-harmony prebuild
npx expo-harmony prebuild --clean
npx expo-harmony prebuild --check
```

`prebuild` 固定使用 HarmonyOS 平台和 `@expo-harmony/template` 模板，因此不像官方接受 `--platform` 和 `--template`。依赖安装相关选项会透传给 Expo CLI：`--no-install`、`--npm`/`--yarn`/`--pnpm`/`--bun`（最多选择一个）和 `--skip-dependency-update <packages>`。执行前会先运行一次 doctor（此阶段不要求构建工具就绪），发现阻塞错误时直接中止。

`--clean` 只会清理带有 Expo Harmony 模板标记的原生目录：CNG manifest 缺失、目标不是项目内的普通目录或模板标记异常时都会拒绝删除。`--check` 是只读操作，会把项目镜像到临时目录（`node_modules` 以符号链接共享，不复制），在其中执行一次隔离的 prebuild 后比较受管文件；无差异时退出码为 `0`，有差异时列出变更并以 `2` 退出，且不能与其他会修改工程的选项同时使用。

## Build

```sh
npx expo-harmony build
npx expo-harmony build --variant release
npx expo-harmony build --sync
```

`build` 在不使用设备的前提下完成 HAP 构建。缺少原生工程时自动执行 prebuild，`--sync` 强制重新生成，默认则校验 CNG 期望状态并在发现差错时报错。随后依次执行 OHPM 依赖安装、原生构建缓存校验和 Hvigor `assembleHap`，最后确认产物 HAP 存在且非空。原生依赖指纹变化时会自动失效旧的 `.cxx` 和 `build` 缓存，避免链接到过期的产物。

选项：`--variant debug|release`（默认 `debug`）和 `--sync`。Release 构建会先执行生产导出，再带着预生成的 Bundle 进入 Hvigor。

## Doctor

```sh
npx expo-harmony doctor
```

`doctor` 逐项检查 Expo `harmony` 配置与 `@expo-harmony/prebuild-config` 插件注册、签名配置文件、启用 Harmony 的 Metro 配置、必需依赖（RNOH 运行时与 CLI、`@expo-harmony/expo-modules-autolinking`）、Harmony Expo Modules 校验、完整的 HarmonyOS SDK、HDC/OHPM/Hvigor 可用性，以及生成工程中的 Hvigor 文件和 RNOH 自动链接禁用状态。存在 error 级别的问题时命令以非零状态退出；未配置外部签名文件只会警告，不影响未签名构建。

## Modules

```sh
npx expo-harmony modules list
npx expo-harmony modules inspect --package expo-linear-gradient
npx expo-harmony modules verify
```

`list` 列出发现的模块候选（包名、版本、来源），并标出不支持 Harmony 的模块、重复版本和缺失的必需依赖。`inspect` 展示模块解析后的完整元数据，包括包根、ArkTS modules 和 HAR 路径，`--package <name>` 可筛选单个模块，未发现时报错。`verify` 输出诊断信息，存在 error 时以非零状态退出。

三个子命令都支持 `--variant debug|release` 和 `--native-modules-dir <dir>`（app-local 模块目录，默认 `./modules`）。

## Export

```sh
npx expo-harmony export:embed
npx expo-harmony export:embed --check
npx expo-harmony export:embed --reset-cache
```

`export:embed` 先运行 doctor，再用项目本地的 Expo CLI 生成 Harmony 平台的 JS Bundle 和资源，并交给项目本地 `@expo/metro-config` 的 Hermes 导出器编译字节码、合并 Source Map。产物经过校验（Hermes 字节码魔数、Source Map 不含宿主机绝对路径）后原子写入原生工程：Bundle 和资源进入模块的 `rawfile` 目录，Source Map 与清单写入 `.expo/harmony/export/`。清单 `.expo/harmony/export-manifest.json` 记录每个文件的哈希与大小，`--check` 据此校验已有导出而不重新构建，`--reset-cache` 会透传给 Metro 清除转换缓存。

## Run

```sh
npx expo-harmony run \
  --device <id-or-name> \
  --variant debug \
  --port 8081
```

`run` 会依次执行环境诊断、确保原生工程（缺失时自动预构建，`--sync` 强制重新生成，否则校验 CNG 状态）、选择设备、Release 生产导出、OHPM 安装、Hvigor 构建、Metro 端口反向映射（仅 Debug）、HAP 安装和 Ability 启动。模块接线的最终正确性由 OHPM、Hvigor、CMake 和 ArkTS 编译器验证。

常用选项：

- `--variant debug|release`：选择构建模式，默认为 `debug`。Release 构建会先执行生产导出，不启动 Metro。
- `--device <id-or-name>`：选择 HDC 设备；连接多台设备时必须指定。
- `--port <number>`：设置 Metro 端口及设备反向映射端口，默认为 `8081`。
- `--no-bundler`：连接已经运行的 Expo Metro，不启动新的服务；端口空闲或被其他进程占用时会报错。不加此选项时，若端口上已有 Metro 在运行则直接复用。
- `--reset-cache`：Debug 模式下启动 Metro 时清除 Metro 缓存；Release 模式下清除生产导出缓存。
- `--no-install`：跳过 HAP 安装，直接启动设备上已有的应用。
- `--app-id <bundleName>`：指定要启动的应用；与生成包名不同时必须同时使用 `--no-install`。
- `--sync`：构建前强制重新执行一次预构建。

Debug 模式下由 CLI 启动的 Metro 会接管终端输出日志，按 Ctrl+C 退出。

## 工具链与环境变量

工具链按「环境变量覆盖 → DevEco Studio 安装布局 → PATH」的顺序解析。`HARMONY_HDC`、`HARMONY_OHPM`、`HARMONY_HVIGORW` 和 `HARMONY_NODE` 可覆盖对应工具的路径，SDK 根目录可通过 `DEVECO_SDK_HOME`、`HARMONY_HOME` 或 `OHOS_SDK_HOME` 指定。原生构建回调 CLI 时使用的 Node.js 可通过 `EXPO_HARMONY_NODE` 显式指定。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
