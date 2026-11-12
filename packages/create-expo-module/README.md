# @expo-harmony/create-expo-module

为 HarmonyOS 上的 React Native 应用提供 Expo 原生模块创建工具，与官方同版本的 `create-expo-module` 配套使用。

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/create-expo-module) · [官方文档](https://docs.expo.dev/more/create-expo-module/)

## 安装

本包适配 Expo SDK 57。使用 npm 将其安装为开发依赖：

```sh
npm install --save-dev @expo-harmony/create-expo-module
```

## 使用

```sh
# 创建独立模块
npx create-expo-harmony-module @acme/expo-sensor

# 按需选择示例功能
npx create-expo-harmony-module expo-sensor --features Function AsyncFunction Event

# 在应用内创建本地模块，默认放在 modules/ 下
npx create-expo-harmony-module local-sensor --local

# 为已有模块添加 Harmony 支持
npx create-expo-harmony-module add-platform-support ../expo-sensor
```

常用参数：

- `--local` 在应用内创建模块，使用应用配置的 Harmony 模块目录；未配置时使用 `modules/`。
- `--path <directory>` 指定生成位置。
- `--features <features...>` 选择示例功能；`--full-example` 包含全部示例。
- `--barrel` 为本地模块添加根目录入口文件；`--no-example` 不生成独立模块的示例应用。
- `add-platform-support <directory>` 为已有模块添加 Harmony 支持，原有 JavaScript 入口和其他平台代码会保留。`--add` 和 `--add-to-existing` 也可用于此操作。

## 示例功能

可选示例为 `Constant`、`Function`、`AsyncFunction`、`Event`、`View`、`ViewEvent` 和 `SharedObject`。选择 View 事件时也会包含 View。默认只生成最小模块，不包含这些示例。

为已有模块添加 Harmony 支持后，生成的内容是起步模板，需要根据模块现有 API 补充对应实现。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
