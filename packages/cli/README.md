# @expo-harmony/cli

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/cli)

为 Expo 项目提供 HarmonyOS 相关 Expo CLI，支持 CNG、环境诊断、生产 Bundle 构建，以及 HAP 构建、安装和启动。

## 安装

```sh
npm install -g @expo-harmony/cli
```

项目需要使用 Node.js 20 或更高版本，并配置 `@expo-harmony/prebuild-config` 和 `@expo-harmony/metro-config`。原生构建还需要可用的 HarmonyOS SDK、OHPM、Hvigor 和 HDC。

## 命令

| 命令 | 作用 |
| --- | --- |
| `expo-harmony prebuild` | 使用 Expo CNG 生成或更新 HarmonyOS 原生工程 |
| `expo-harmony prebuild --clean` | 安全删除并重新生成受管理的 `harmony` 目录 |
| `expo-harmony prebuild --check` | 在隔离目录中比较期望状态，不修改项目文件 |
| `expo-harmony doctor` | 检查配置、依赖版本、Metro、RNOH、SDK、构建工具和签名 |
| `expo-harmony export:embed` | 导出 Hermes 字节码、资源和 Source Map |
| `expo-harmony run` | 构建 HAP，并在连接的 HarmonyOS 设备上安装和启动应用 |

所有命令都可接收可选的项目路径；未提供时使用当前目录：

```sh
npx expo-harmony doctor ./my-app
npx expo-harmony prebuild ./my-app
npx expo-harmony run ./my-app --device <hdc-target>
```

## Prebuild

```sh
npx expo-harmony prebuild
npx expo-harmony prebuild --clean
npx expo-harmony prebuild --check
```

`prebuild` 固定使用 HarmonyOS 平台和 `@expo-harmony/template`，因此不接受 `--platform` 或 `--template`。它支持 Expo 的 `--no-install`、`--npm`、`--yarn`、`--pnpm`、`--bun` 和 `--skip-dependency-update <packages>` 选项。

`--clean` 只会清理包含 Expo Harmony 模板标记的原生目录。`--check` 是只读操作，会在隔离环境中重新生成期望状态并报告 CNG 文件差异；输出无差异时退出码为 `0`，存在差异时为 `2`。

## Doctor

```sh
npx expo-harmony doctor
npx expo-harmony doctor --json
```

`doctor` 会验证 Expo Harmony 配置、项目依赖与版本、Metro 组合、RNOH CLI、HarmonyOS SDK、OHPM、Hvigor、HDC 和签名配置。存在阻塞问题时命令以非零状态退出。

## Export

```sh
npx expo-harmony export:embed
npx expo-harmony export:embed --check
npx expo-harmony export:embed --reset-cache
```

`export:embed` 使用项目本地的 Expo CLI 和 `hermes-compiler` 生成生产 Hermes 字节码、应用资源及组合后的 Source Map，并写入 HarmonyOS 原生工程。导出文件的哈希记录在 `.expo/harmony/export-manifest.json`；`--check` 仅校验已有导出，不重新构建。

## Run

```sh
npx expo-harmony run \
  --device <id-or-name> \
  --variant debug \
  --port 8081
```

`run` 会依次执行环境诊断、CNG 状态检查、原生模块验证、OHPM 安装、Hvigor 构建、HDC 安装和 Ability 启动。缺少原生工程时会自动执行预构建；已有工程发生变动时可使用 `--sync` 重新生成。

常用选项：

- `--variant debug|release`：选择构建模式，默认为 `debug`。Release 构建会先执行生产导出。
- `--device <id-or-name>`：选择 HDC 设备；连接多个设备时必须指定。
- `--port <number>`：设置 Metro 与设备端口反向映射，默认为 `8081`。
- `--no-bundler`：连接已经运行的 Expo Metro，不启动新的服务。
- `--no-install`：跳过 HAP 安装，直接启动设备上的应用。
- `--app-id <bundleName>`：指定要启动的应用；与生成包名不同时必须同时使用 `--no-install`。
- `--sync`：检测到 CNG 变化时自动重新执行预构建。
- `--json`：输出便于脚本消费的 JSON 结果。

工具链路径可以通过 `HARMONY_HDC`、`HARMONY_OHPM`、`HARMONY_HVIGORW`、`HARMONY_NODE` 和 `DEVECO_SDK_HOME` 覆盖。原生构建使用的 Node.js 也可通过 `EXPO_HARMONY_NODE` 显式指定。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
