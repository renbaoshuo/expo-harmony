# @expo-harmony/cli

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/cli)

Expo 项目的 HarmonyOS 命令行工具：启动 Metro 开发服务、生成原生工程、构建和安装 HAP。

## 安装

```sh
npm install --save-dev @expo-harmony/cli
```

CLI 必须装在项目本地。JS 打包调用项目内的 Expo CLI，Hermes 字节码编译调用项目内的 `@expo/metro-config`，Release 原生构建回调项目本地的 `expo-harmony` 二进制生成 Bundle。

项目需要 Node.js 20 或更高版本，在 Expo 配置中注册 `@expo-harmony/prebuild-config` 插件，并用 `@expo-harmony/metro-config` 组合 Metro 配置。

HAP 构建需要完整的 HarmonyOS SDK（含 HMS 和 OpenHarmony 组件）、OHPM、Hvigor 和 HDC。用 `doctor` 检查这些环境。

## 命令

| 命令 | 作用 |
| --- | --- |
| `expo-harmony start` | 启动 Harmony 开发所需的 Expo Metro 服务 |
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

所有命令都可以带一个可选的项目路径；`modules` 的路径写在子命令后面。不提供时，从当前目录向上找最近的项目根目录：

```sh
npx expo-harmony start ./my-app
npx expo-harmony doctor ./my-app
npx expo-harmony prebuild ./my-app
npx expo-harmony build ./my-app --variant release
npx expo-harmony run ./my-app --device <hdc-target>
```

## Start

```sh
npx expo-harmony start
npx expo-harmony start --port 8082
npx expo-harmony start --clear
```

CLI 入口先设置 `EXPO_HARMONY=1` 和 `EXPO_METRO_TARGET=harmony`，再读取应用配置，所有命令都如此。

`start` 调用项目本地的 Expo CLI，以 `--dev-client` 模式启动 Metro。它只启动 JS 开发服务：不生成原生工程，不构建、安装、启动应用，不做设备端口映射，也不要求 HarmonyOS SDK 和设备就绪。Metro 在当前终端输出日志，Ctrl+C 退出。

选项有 `--port <number>`（默认 `8081`）和 `--reset-cache`（别名 `--clear`、`-c`）。端口上已有 Metro 时提示并退出，不停止已有服务；这时缓存选项不生效，要先停掉已有的 Metro 再执行一次。端口被其他进程占用时报错。

要构建并启动应用，在另一个终端运行 `expo-harmony run --no-bundler`；指定了端口时，两个命令用同一个 `--port`。

## Prebuild

```sh
npx expo-harmony prebuild
npx expo-harmony prebuild --clean
npx expo-harmony prebuild --check
```

`prebuild` 固定生成 HarmonyOS 平台，固定用 `@expo-harmony/template` 模板，因此没有 `--platform` 和 `--template`。依赖安装的选项透传给 Expo CLI：`--no-install`、`--npm`/`--yarn`/`--pnpm`/`--bun`（最多选一个）和 `--skip-dependency-update <packages>`。执行前先跑一遍 doctor，有阻塞错误就中止；这个阶段不要求构建工具就绪。

`--clean` 只删除带 Expo Harmony 模板标记的原生目录。CNG manifest 缺失、目标不是项目内的普通目录、模板标记异常，都拒绝删除。

`--check` 是只读操作。它把项目镜像到临时目录（`node_modules` 里的包目录用链接共享，Windows 下的普通文件复制过去，不需要文件符号链接权限），在临时目录里执行一次 prebuild，再比较受管文件。没有差异时退出码为 0；有差异时列出变更，退出码为 2。它不能和其他会修改工程的选项一起用。

## Build

```sh
npx expo-harmony build
npx expo-harmony build --variant release
npx expo-harmony build --sync
```

`build` 构建 HAP，不选设备，也不安装和启动应用。没有原生工程时先执行 prebuild；`--sync` 强制重新生成；默认只校验 CNG 期望状态，发现差错就报错。之后安装 OHPM 依赖、校验原生构建缓存、执行 Hvigor `assembleHap`，最后确认产物 HAP 存在且非空。原生依赖的指纹变化时，旧的 `.cxx` 和 `build` 缓存会失效，不会链接到过期产物。

选项：`--variant debug|release`（默认 `debug`）和 `--sync`。Release 构建先执行生产导出，再带着预生成的 Bundle 进 Hvigor。

## Doctor

```sh
npx expo-harmony doctor
```

`doctor` 逐项检查：

- Expo `harmony` 配置和 `@expo-harmony/prebuild-config` 插件注册
- 签名配置文件
- Metro 配置是否启用 Harmony
- 必需依赖：RNOH 运行时和 CLI、`@expo-harmony/expo-modules-autolinking`
- Harmony Expo Modules
- HarmonyOS SDK 是否完整
- HDC、OHPM、Hvigor 是否可用
- 生成工程中的 Hvigor 文件和 RNOH 自动链接禁用状态

有 error 级别的问题时，命令以非零状态退出。未配置外部签名文件只警告，不影响未签名构建。

## Modules

```sh
npx expo-harmony modules list
npx expo-harmony modules inspect --package expo-linear-gradient
npx expo-harmony modules verify
```

`list` 列出发现的模块候选（包名、版本、来源），标出不支持 Harmony 的模块、重复版本和缺失的必需依赖。`inspect` 展示模块解析后的元数据：包根、ArkTS modules、HAR 路径。`--package <name>` 筛选单个模块，未发现时报错。`verify` 输出诊断信息，有 error 时以非零状态退出。

三个子命令都支持 `--variant debug|release` 和 `--native-modules-dir <dir>`（app-local 模块目录，默认 `./modules`）。

## Export

```sh
npx expo-harmony export:embed
npx expo-harmony export:embed --check
npx expo-harmony export:embed --reset-cache
```

`export:embed` 先运行 doctor，再用项目本地的 Expo CLI 生成 Harmony 平台的 JS Bundle 和资源，交给项目本地的 `@expo/metro-config` 的 Hermes 导出器编译字节码、合并 Source Map。

产物先校验再写入：检查 Hermes 字节码魔数、Source Map 不含宿主机绝对路径，然后原子写入原生工程。Bundle 和资源进入模块的 `rawfile` 目录，Source Map 和清单写入 `.expo/harmony/export/`。

清单 `.expo/harmony/export-manifest.json` 记录每个文件的哈希和大小。`--check` 按清单校验已有的导出，不重新构建。`--reset-cache` 透传给 Metro，清除转换缓存。

## Run

```sh
npx expo-harmony run \
  --device <id-or-name> \
  --variant debug \
  --port 8081
```

`run` 按顺序执行：环境诊断、确保原生工程（缺失时预构建，`--sync` 强制重新生成，否则复用已有工程）、选择设备、Release 生产导出、OHPM 安装、Hvigor 构建、Metro 端口反向映射（仅 Debug）、HAP 安装、Ability 启动。模块接线是否正确，由 OHPM、Hvigor、CMake 和 ArkTS 编译器验证。

常用选项：

- `--variant debug|release`：构建模式，默认 `debug`。Release 先执行生产导出，不启动 Metro。
- `--device <id-or-name>`：选择已连接的 HDC 设备，或按完整名称启动本地模拟器，例如 `--device "Pura 90 Pro"`。有多个候选目标时必须指定。
- `--port <number>`：Metro 端口和设备反向映射端口，默认 `8081`。
- `--no-bundler`：连接已经在运行的 Expo Metro，不启动新的服务；端口空闲或被其他进程占用时报错。不加此选项时，端口上已有 Metro 在运行就直接复用。
- `--reset-cache`：Debug 模式下启动 Metro 时清除 Metro 缓存；Release 模式下清除生产导出缓存。
- `--no-install`：跳过 HAP 安装，直接启动设备上已有的应用。
- `--app-id <bundleName>`：指定要启动的应用；与生成的包名不同时，必须同时使用 `--no-install`。
- `--sync`：构建前强制重新执行一次预构建。

Debug 模式下由 CLI 启动的 Metro 接管终端输出日志，Ctrl+C 退出。

未指定 `--device` 时，优先用已连接的设备。没有连接的设备时，先等正在启动的模拟器；否则启动唯一的本地模拟器。有多个候选模拟器时列出名称，用 `--device "模拟器名称"` 选择。通过名称选择或自动拉起模拟器时，CLI 等 HDC 连接、确认开机完成后才继续构建、安装和启动，最多等 120 秒。退出 CLI 或 Metro 后，模拟器继续运行。

自动启动需要 DevEco Studio 6.1.0 或更新版本，并且已在 Device Manager 中创建模拟器。CLI 按[华为模拟器命令行文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)调用 `Emulator -list -details` 和 `Emulator -start <name>`，使用 DevEco Studio 配置的实例和镜像路径。启动日志在项目的 `.expo/harmony/emulator.log`。启动失败时，先在 DevEco Studio 里处理首次使用协议或登录要求；文档注明需要登录开发者账号的模拟器版本无法从命令行启动。

## 工具链与环境变量

工具链按「环境变量覆盖 → DevEco Studio 安装布局 → PATH」的顺序解析。

`HARMONY_HDC`、`HARMONY_EMULATOR`、`HARMONY_OHPM`、`HARMONY_HVIGORW` 和 `HARMONY_NODE` 覆盖对应工具的路径。SDK 根目录用 `DEVECO_SDK_HOME`、`HARMONY_HOME` 或 `OHOS_SDK_HOME` 指定。Emulator 支持 DevEco Studio 的 `tools/emulator` 和 Command Line Tools 的 `emulator` 两种布局，只在需要模拟器时调用。原生构建回调 CLI 时用的 Node.js 可以用 `EXPO_HARMONY_NODE` 指定。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
