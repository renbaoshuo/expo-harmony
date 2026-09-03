# @expo-harmony/expo-module-scripts

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-module-scripts)

为 Harmony Expo Module 提供 HarmonyOS 平台的构建与打包命令。包内提供独立的 `expo-harmony-module` 命令，负责 OHPM 依赖安装、Hvigor HAR 构建、发布产物清洗和 npm 打包前校验；命令名与官方的 `expo-module` 不同，两者可以在同一个模块包中共存。

## 安装

```sh
npm install --save-dev @expo-harmony/expo-module-scripts
```

需要 Node.js 20 或更高版本，以及本机可用的 OHPM 和 Hvigor（安装 DevEco Studio 后通常已经具备）。

## 约定布局

所有命令都按固定约定定位文件，模块包需要具备以下结构：

```
my-expo-module/
├── expo-module.config.json    # platforms 须包含 "harmony"，harmony.modules 声明 ArkTS 模块类名
├── package.json
└── harmony/
    ├── build-profile.json5    # 可选，其中的模块名用于定位构建产物
    ├── library/               # HAR library 模块
    │   ├── oh-package.json5   # OHPM 清单
    │   └── build/default/outputs/default/<模块名>.har
    └── library.har            # 清洗后的发布产物，随 npm 包一起发布
```

模块名解析优先读取 `harmony/build-profile.json5` 中 `srcPath` 指向 `./library` 的模块名称；若未提供该文件，则默认回退至 `library`。

## 命令

| 命令                                       | 作用                                              |
| ------------------------------------------ | ------------------------------------------------- |
| `expo-harmony-module inspect`              | 输出解析后的模块配置和约定路径，不执行构建        |
| `expo-harmony-module prepare`              | 安装依赖、构建 HAR 并发布到 `harmony/library.har` |
| `expo-harmony-module prepare --clean-only` | 只执行 Hvigor `clean` 任务                        |
| `expo-harmony-module prepack`              | 从干净状态重建 HAR，并校验 npm 包内容             |

通用选项：`--root <path>` 指定模块包根目录（默认为当前目录）；`--json` 以 JSON 输出结果；`--dry-run` 只打印将要执行的命令而不实际运行（不能与 `inspect` 同用）。`inspect` 始终输出 JSON。

`prepare` 在 `harmony/` 工程内依次执行 `ohpm install --all` 和 Hvigor `assembleHar`（module 模式、`default` product、release buildMode、`--no-daemon`），然后把 `harmony/library/build/default/outputs/default/<模块名>.har` 清洗后原子替换 `harmony/library.har`。

`prepack` 在构建前额外执行一次 Hvigor `clean` 以保证全量重建，构建完成后运行 `npm pack --dry-run --json --ignore-scripts` 检查将要发布的内容：只允许约定内的文件（源码与各平台目录、文档、`harmony/library.har`、`harmony/library/oh-package.json5` 等），且 `package.json`、`expo-module.config.json`、`main`/`types` 入口和两个 Harmony 产物必须齐全；出现多余或缺失的文件都会报错。

## HAR 清洗

发布产物在写入 `harmony/library.har` 前会重新打包：`oh-package.json5` 的 `dependencies`、`devDependencies` 和 `dynamicDependencies` 不允许使用 `file:`、`link:`、`workspace:` 或本地路径，`oh-package-lock.json5` 会被移除，最终以 portable 格式重新压缩，避免把宿主机路径或本地依赖带进发布产物。

## 工具链

`ohpm` 和 `hvigorw` 可分别通过环境变量 `HARMONY_OHPM` 和 `HARMONY_HVIGORW` 指定路径；当 `HARMONY_HVIGORW` 指向 JS 脚本时，会改用 `HARMONY_NODE`（缺省为当前 Node 可执行文件）来运行。

## 在模块包中使用

```json
{
  "scripts": {
    "harmony:clean": "expo-harmony-module prepare --clean-only",
    "harmony:build": "expo-harmony-module prepare",
    "prepack": "expo-harmony-module prepack"
  }
}
```

`prepack` 挂在 npm 的同名生命周期钩子上，`npm pack` 和 `npm publish` 前会自动执行。除 CLI 外，包还导出 `inspectModule`、`prepareModule`、`prepackModule` 等函数供编程调用。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@baoshuo](https://twitter.com/baoshuo)
