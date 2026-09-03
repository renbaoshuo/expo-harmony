# {{NPM_NAME}}

由 `create-expo-harmony-module` 生成的 HarmonyOS Expo 模块，基于 Expo SDK {{SDK_MAJOR}}。npm 包发布编译后的 TypeScript facade 和预构建的 `harmony/library.har`，HarmonyOS 应用中的 Expo Modules autolinking 会自动发现它们。

## 命令

```sh
npm run build            # 编译 src/ 下的 TypeScript facade 到 build/
npm run harmony:build    # 安装 OHPM 依赖并构建 harmony/library.har
npm run harmony:clean    # 执行 Hvigor clean 任务
npm run harmony:inspect  # 输出解析后的模块配置和约定路径
```

`npm prepare` 一次完成 facade 编译和 HAR 构建；`prepack` 额外从干净状态重建，并校验 `npm pack` 将要发布的内容。构建 HAR 需要本机可用的 `ohpm` 和 `hvigorw`，安装 DevEco Studio 后通常已经具备。

## 目录结构

```
{{PACKAGE_BASENAME}}/
├── src/index.ts             # TypeScript facade，编译产物在 build/
├── expo-module.config.json  # 声明 harmony 平台和 ArkTS 模块类
├── harmony/
│   ├── library/             # 存放 ArkTS 源码的 Hvigor HAR 模块
│   └── library.har          # 构建产物，随 npm 包一起发布
└── example/                 # 演示模块用法的 Expo 应用
```

## 示例模块

原生代码全部是 ArkTS，位于 `harmony/library/src/main/ets/{{MODULE_BASE}}Module.ets`。`{{MODULE_NAME}}` 模块定义了 `platform` 常量和 `echo`、`echoAsync` 函数；`{{MODULE_BASE}}Counter` SharedObject 提供 `value` 属性、`increment` 与 `emitValueChanged` 方法、静态 `add`，以及 `onValueChanged` 事件；`{{MODULE_BASE}}View` 原生 View 带有 `label`、`value` props、`onValueChanged` 事件和异步的 `increment` ref 方法。

`src/index.ts` 中的 facade 通过官方 `requireNativeModule` 和 `requireNativeViewManager` 暴露这套 API。第一个 `.view(...)` 定义对应 `requireNativeViewManager('{{MODULE_NAME}}')`；更多的 View 以注册名作为第二个参数获取。View 的名称、props、事件和函数体都来自 ArkTS 的 `definition()`，`expo-module.config.json` 只注册模块类，没有需要维护的生成绑定，也没有模块级 C++、CMake 目标、Provider 或 RNOH package class。

## 示例应用

`example/` 是一个通过 `file:..` 依赖本模块的最小 Expo 应用。在该目录下执行：

```sh
npm run prebuild:harmony  # 生成 HarmonyOS 工程
npm run harmony           # 构建并运行到设备或模拟器
```
