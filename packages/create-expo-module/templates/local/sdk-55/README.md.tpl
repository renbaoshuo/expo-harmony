# {{NPM_NAME}}

基于 Expo SDK {{SDK_MAJOR}} 的应用内 HarmonyOS Expo 模块，位于 Expo 应用中的 `modules/{{PACKAGE_BASENAME}}` 目录。此包保持 private，prebuild 时由 Expo Modules autolinking 自动接入，无需发布。

通过本目录的入口引用模块，根目录的 `index.ts` 转发 `./src` 中的公开 API。

## 命令

```sh
npm run harmony:build    # 安装 OHPM 依赖并构建 HAR
npm run harmony:clean    # 执行 Hvigor clean 任务
npm run harmony:inspect  # 输出解析后的模块配置和约定路径
```

## HAR 的构建

ArkTS 源码与独立模块一样位于 `harmony/library` 工程。prebuild 时，应用会以固定的 OHPM 和 Hvigor 命令构建该工程并自动拾取产物 HAR；模块元数据中不声明可执行命令，因此通常无需手动构建。只有想手动构建或查看解析后的配置时，才需要在本目录运行 `npm run harmony:build` 或 `harmony:inspect`。

## 示例模块

生成的 `{{MODULE_NAME}}` 模块与独立模板的起点相同：`echo`、`echoAsync` 函数，`{{MODULE_BASE}}Counter` SharedObject 和 `{{MODULE_BASE}}View` 原生 View。它们全部以 ArkTS 编写，位于 `harmony/library/src/main/ets/` 下，并通过官方 `requireNativeModule` 和 `requireNativeViewManager` API 从 `src/index.ts` 暴露。
