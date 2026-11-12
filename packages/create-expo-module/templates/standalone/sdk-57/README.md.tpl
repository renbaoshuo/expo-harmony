# {{NPM_NAME}}

Expo SDK {{SDK_MAJOR}} 的 Harmony 模块，默认只有最小 ArkTS 模块和 TypeScript facade。
使用 --features 或 --full-example 选择示例。已有模块添加 Harmony 后，示例仅为骨架，仍需实现已有 JS API。

- npm run build：编译 TypeScript。
- npm run harmony:build：安装 OHPM 依赖并构建 HAR，需要 DevEco Studio 的 OHPM / Hvigor。
- npm run harmony:inspect：检查配置与产物路径。
- npm pack：编译、构建并校验 JS、类型、HAR、OHPM 清单。

发布内容由 package.json#files 指定，HAR 使用版本化的 OHPM 依赖。
先在模块根目录执行 `npm install --legacy-peer-deps`，安装构建工具并生成 facade 和 HAR。再进入 `example/` 执行 `npm install --legacy-peer-deps`、`npm run prebuild:harmony` 和 `npm run harmony`。该安装选项用于接受 SDK 57 和 Harmony Worklets 的上游 peer 版本差异。
修改 ArkTS 后，在模块根目录执行 `npm run harmony:build`，然后重新预构建并编译示例应用。普通 Expo View 使用 ArkUI。
