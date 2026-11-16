# @expo-harmony/expo-module-scripts

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-module-scripts)

为 HarmonyOS 上的 React Native 应用开发原生模块提供构建命令，与官方同版本的 `expo-module-scripts` 配套使用。

## 安装

```sh
npm install --save-dev @expo-harmony/expo-module-scripts
```

## 使用

Expo 模块通过 `expo-module.config.json` 声明 `harmony` 平台。RNOH 原生包通过 `package.json` 的 `harmony.autolinking` 声明 `mainHarPath: 'harmony'` 和与 npm 包名一致的 `ohPackageName`。两者都在 `harmony/library/oh-package.json5` 中声明原生库依赖。运行构建命令前，需要在开发环境中配置 HarmonyOS SDK、OHPM 和 Hvigor。

| 命令 | 作用 |
| --- | --- |
| `expo-harmony-module inspect` | 查看模块配置和构建路径。 |
| `expo-harmony-module prepare` | 安装原生依赖并生成 HarmonyOS HAR 文件。 |
| `expo-harmony-module prepare --clean-only` | 清理 Hvigor 构建产物及复制到 npm 包目录的 HAR。 |
| `expo-harmony-module prepack` | 为 npm 打包准备 HarmonyOS 构建产物。 |

可以在模块的 `package.json` 中添加以下脚本：

```json
{
  "scripts": {
    "harmony:clean": "expo-harmony-module prepare --clean-only",
    "harmony:build": "expo-harmony-module prepare",
    "prepack": "expo-harmony-module prepack"
  }
}
```

配置 `prepack` 后，运行 `npm pack` 或 `npm publish` 时会先准备 HarmonyOS 构建产物。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
