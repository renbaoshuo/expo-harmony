# @expo-harmony/cli

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/cli) | [Expo CLI 文档](https://docs.expo.dev/more/expo-cli/)

为 HarmonyOS 上的 React Native 应用提供项目所需的 Expo CLI，与官方 `@expo/cli` 配套使用。

## 安装

本包适配 Expo SDK 57。在 Expo 应用项目目录中运行以下命令安装：

```sh
npm install --save-dev @expo-harmony/cli
```

## 项目配置

Metro 配置需要使用 `@expo-harmony/metro-config`。通过 Expo 配置生成原生工程的项目（CNG），还需要在 Expo 配置中注册 `@expo-harmony/prebuild-config` 插件。手工维护 `harmony/` 工程的项目可以使用 bare 模式，按原生工程中的配置构建和运行，无需注册 prebuild 插件。

构建 HAP 需要 HarmonyOS SDK（含 HMS 和 OpenHarmony 组件）、OHPM 和 Hvigor。连接设备需要 HDC。可以运行 `npx expo-harmony doctor` 检查环境。

## 命令

| 命令 | 作用 |
| --- | --- |
| `expo-harmony start` | 启动 Metro 开发服务 |
| `expo-harmony prebuild` | 使用 Expo CNG 清理并重新生成 HarmonyOS 原生工程 |
| `expo-harmony prebuild --no-clean` | 在现有原生工程上增量更新 |
| `expo-harmony prebuild --check` | 检查 CNG 生成的文件是否需要更新 |
| `expo-harmony build` | 构建 HAP |
| `expo-harmony doctor` | 检查项目配置、依赖、开发环境和签名配置 |
| `expo-harmony modules list` | 列出项目中的 Expo Modules 及其来源 |
| `expo-harmony modules inspect` | 查看模块的 Harmony 配置和原生文件路径 |
| `expo-harmony modules verify` | 检查模块配置、依赖冲突和原生文件 |
| `expo-harmony export:embed` | 导出 Hermes 字节码、资源和 Source Map 并写入原生工程 |
| `expo-harmony run` | 构建 HAP，在设备或模拟器上安装并启动应用 |

所有命令都可以指定项目路径，`modules` 的路径写在子命令后面。不指定时，CLI 从当前目录向上查找最近的项目根目录：

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
npx expo-harmony start --host 192.168.1.100
npx expo-harmony start --clear
```

`start` 启动 Metro，为 Debug 应用提供 JS Bundle。运行这个命令不需要 HarmonyOS SDK 或已连接的设备。日志显示在当前终端，按 Ctrl+C 退出。

可以用 `--port <number>` 指定端口，默认是 `8081`。`--reset-cache` 清除 Metro 缓存，也可以写成 `--clear` 或 `-c`。

多网卡环境下，可以用 `--host <IP 或主机名>` 指定设备连接的电脑地址，例如 `npx expo-harmony start --host 192.168.1.100 --port 8082`。地址应是设备能访问的网卡 IPv4 或主机名，不带协议和端口。

端口上已有 Metro 时，命令会提示并退出，已有服务继续运行。要清除它的缓存，需要先停止服务，再带缓存选项启动。端口被其他进程占用时，命令会报错。

要构建并启动应用，在另一个终端运行 `npx expo-harmony run --no-bundler`。如果指定了端口，两个命令应使用相同的 `--port`。

## Prebuild

```sh
npx expo-harmony prebuild
npx expo-harmony prebuild --no-clean
npx expo-harmony prebuild --check
```

`prebuild` 根据 Expo 配置生成 HarmonyOS 原生工程，仅用于 CNG 项目。

命令会先检查项目配置和依赖，有错误时停止。这一步不要求安装好原生构建工具。

依赖安装支持以下选项：

- `--no-install`：跳过依赖安装。
- `--npm`、`--yarn`、`--pnpm` 或 `--bun`：选择包管理器，最多指定一个。
- `--skip-dependency-update <packages>`：跳过指定依赖的版本更新。

默认情况下，`prebuild` 会清理并重新生成原生工程。使用 `--no-clean` 可以保留现有工程并增量更新。

`--check` 比较现有文件与当前配置生成的文件，不修改项目文件。没有差异时退出码为 0，有差异时列出变更并以退出码 2 结束。这个选项不能同时指定清理方式、依赖安装或依赖更新选项。

## Build

```sh
npx expo-harmony build
npx expo-harmony build --variant release
npx expo-harmony build --sync
```

`build` 构建 HAP，并输出文件路径。执行这个命令不需要连接设备，构建后也不会安装或启动应用。

默认构建 Debug 版本。使用 `--variant release` 构建 Release 版本时，命令会将 JS Bundle 和资源打包进应用。

项目没有原生工程时，命令会先运行 prebuild。已有 CNG 工程时，会检查生成的文件是否需要更新，有差异就停止构建，可以用 `--sync` 重新生成后继续构建。bare 工程按现有原生配置构建，不支持 `--sync`。

## Doctor

```sh
npx expo-harmony doctor
```

`doctor` 逐项检查：

- CNG 工程的 Expo `harmony` 配置和 prebuild 插件；bare 工程的包名、模块、Ability 和构建配置
- 签名配置文件及其引用
- Metro 配置是否启用 Harmony
- RNOH 运行时和 CLI、`@expo-harmony/expo-modules-autolinking` 是否已安装
- Expo Modules 的 Harmony 支持和配置
- HarmonyOS SDK 是否完整
- HDC、OHPM、Hvigor 是否可用
- 原生工程的 Hvigor 文件和自动链接配置

有 `error` 级别的问题时，命令以非零退出码结束。未配置签名时，CNG 工程仍可构建未签名的 HAP。配置签名后，CLI 会检查签名文件和材料是否存在；证书是否有效由 Hvigor 在构建时检查。

## Modules

```sh
npx expo-harmony modules list
npx expo-harmony modules inspect --package expo-linear-gradient
npx expo-harmony modules verify
```

`list` 显示模块的包名、版本和来源，并标出不支持 Harmony 的模块、重复版本和缺失的依赖。

`inspect` 查看模块的 Harmony 配置，包括包目录、ArkTS 模块和 HAR 路径。可以用 `--package <name>` 筛选单个模块，找不到时会报错。

`verify` 检查模块配置、依赖冲突和原生文件。有 `error` 级别的问题时，以非零退出码结束。

三个子命令都支持 `--variant debug|release`，也可以用 `--native-modules-dir <dir>` 指定应用内的模块目录，默认是 `./modules`。

## Export

```sh
npx expo-harmony export:embed
npx expo-harmony export:embed --check
npx expo-harmony export:embed --reset-cache
```

`export:embed` 导出 Release 应用使用的 Hermes 字节码、资源和 Source Map。命令会先检查项目配置，再生成并校验导出文件。

Bundle 和资源写入原生模块的 `rawfile` 目录，Source Map 写入 `.expo/harmony/export/`。导出清单位于 `.expo/harmony/export-manifest.json`。

`--check` 检查已有导出文件是否与清单一致，不重新导出。`--reset-cache` 清除 Metro 转换缓存后重新导出。

## Run

```sh
npx expo-harmony run \
  --device <id-or-name> \
  --variant debug \
  --port 8081
```

`run` 构建 HAP，在设备或模拟器上安装并启动应用。它使用项目中已有的原生工程，工程不存在时先运行 prebuild。

常用选项：

- `--variant debug|release`：构建模式，默认 `debug`。Release 将 JS Bundle 和资源打包进应用，不启动 Metro。
- `--device <id-or-name>`：选择已连接的 HDC 设备，或按完整名称启动本地模拟器，例如 `--device "Pura 90 Pro"`。有多个候选目标时必须指定。
- `--port <number>`：电脑上的 Metro 端口，默认 `8081`。Debug 模式下会配置设备端口映射，让应用连接到这个端口。
- `--host <IP 或主机名>`：指定本次启动的 Metro 对外公布的地址，与 `start --host` 相同；使用 `--no-bundler` 时应在启动 Metro 的命令中指定。
- `--no-bundler`：使用已运行的 Metro，找不到服务时报错。不加此选项时，会启动 Metro，或复用端口上已有的 Metro。
- `--reset-cache`：Debug 模式下启动 Metro 时清除 Metro 缓存；Release 模式下清除生产导出缓存。
- `--no-install`：仍会构建 HAP，但跳过安装，启动设备上已有的应用。
- `--app-id <bundleName>`：指定要启动的应用；与项目配置中的包名不同时，必须同时使用 `--no-install`。
- `--sync`：构建前重新运行 prebuild，仅用于 CNG 项目。bare 项目不支持此选项。

Debug 模式下，如果 Metro 由这个命令启动，日志会显示在当前终端，按 Ctrl+C 退出。

未指定 `--device` 时，优先使用已连接的设备。没有连接的设备时，先等待正在启动的模拟器，没有的话就启动本地唯一的模拟器。有多个可选设备或模拟器时，需要用 `--device` 指定。

按名称选择或自动启动模拟器时，CLI 会等待模拟器开机并连接 HDC，最多等待 120 秒。退出 CLI 或 Metro 后，模拟器继续运行。

自动启动模拟器需要 DevEco Studio 6.1.0 或更高版本，并且已在 Device Manager 中创建模拟器。启动日志位于 `.expo/harmony/emulator.log`。启动失败时，可以先在 DevEco Studio 中打开模拟器，处理首次使用协议或登录提示。需要登录开发者账号的模拟器版本不支持从命令行启动，详见 [华为的模拟器文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)。

## 工具链与环境变量

CLI 先读取环境变量指定的工具路径，再查找 DevEco Studio 的安装目录，最后从 `PATH` 查找。

找不到工具或需要使用其他版本时，可以设置以下变量：

| 环境变量 | 用途 |
| --- | --- |
| `REACT_NATIVE_PACKAGER_HOSTNAME` | 指定 Metro 对外公布的 IP 或主机名，`--host` 优先 |
| `HARMONY_HDC` | 指定 HDC 路径 |
| `HARMONY_EMULATOR` | 指定模拟器命令行工具路径 |
| `HARMONY_OHPM` | 指定 OHPM 路径 |
| `HARMONY_HVIGORW` | 指定 Hvigor 路径 |
| `HARMONY_NODE` | 指定 OHPM、Hvigor 使用的 Node.js 路径 |
| `EXPO_HARMONY_NODE` | 指定原生构建过程中运行 Expo Harmony CLI 的 Node.js 路径 |
| `DEVECO_SDK_HOME`、`HARMONY_HOME` 或 `OHOS_SDK_HOME` | 指定 HarmonyOS SDK 根目录 |

### 超时

OHPM 安装、Hvigor 构建、等待模拟器这些步骤都有超时，默认值见下表，可以通过环境变量覆盖。变量名为 `EXPO_HARMONY_<操作名大写下划线>_TIMEOUT_MS`，单位为毫秒，例如 `EXPO_HARMONY_OHPM_INSTALL_TIMEOUT_MS`。设置成 0、负数或无法解析的值时，这个变量会被忽略，并给出警告。

| 环境变量 | 对应操作 | 默认值 |
| --- | --- | --- |
| `EXPO_HARMONY_OHPM_INSTALL_TIMEOUT_MS` | OHPM 依赖安装 | 30 分钟 |
| `EXPO_HARMONY_HVIGOR_BUILD_TIMEOUT_MS` | Hvigor 构建 | 15 分钟 |
| `EXPO_HARMONY_EXPO_EXPORT_EMBED_TIMEOUT_MS` | `export:embed`（Hermes 打包） | 10 分钟 |
| `EXPO_HARMONY_METRO_READY_TIMEOUT_MS` | 等待 Metro 就绪 | 30 分钟 |
| `EXPO_HARMONY_START_EMULATOR_TIMEOUT_MS` | 等待模拟器连接 HDC | 2 分钟 |
| `EXPO_HARMONY_INSTALL_HAP_TIMEOUT_MS` | 安装 HAP 到设备 | 2 分钟 |
| `EXPO_HARMONY_LAUNCH_APP_TIMEOUT_MS` | 启动应用 | 30 秒 |
| `EXPO_HARMONY_LIST_DEVICES_TIMEOUT_MS` | HDC 列出设备 | 15 秒 |
| `EXPO_HARMONY_LIST_EMULATORS_TIMEOUT_MS` | 列出模拟器实例 | 15 秒 |
| `EXPO_HARMONY_FORCE_STOP_APP_TIMEOUT_MS` | 强制停止应用 | 15 秒 |
| `EXPO_HARMONY_LIST_METRO_PORTS_TIMEOUT_MS` | 列出 Metro 端口转发 | 15 秒 |
| `EXPO_HARMONY_REMOVE_METRO_PORT_TIMEOUT_MS` | 移除 Metro 端口转发 | 15 秒 |
| `EXPO_HARMONY_REVERSE_METRO_PORT_TIMEOUT_MS` | 反向转发 Metro 端口 | 15 秒 |
| `EXPO_HARMONY_HDC_TIMEOUT_MS` | 其他 HDC 命令 | 60 秒 |
| `EXPO_HARMONY_DOCTOR_TIMEOUT_MS` | Doctor 工具检查 | 10 秒 |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
