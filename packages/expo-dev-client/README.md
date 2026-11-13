# @expo-harmony/expo-dev-client

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-dev-client) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/dev-client/)

为 HarmonyOS 上的 React Native 应用提供 Expo Dev Client 的原生实现，与官方 `expo-dev-client` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-dev-client expo-dev-client@~57.0.20
```

## API 对照表

### Methods

#### `devClient(options?)`

从 `@expo-harmony/expo-dev-client/plugin` 默认导入。返回 Expo 配置插件元组 `['@expo-harmony/expo-dev-client', options]`。

`options` 可包含以下字段：

- `launchMode?: 'most-recent' | 'launcher'`：默认值为 `most-recent`。该模式先尝试打开最近使用的项目，再尝试 `defaultLaunchURL`；`launcher` 跳过最近项目，直接尝试默认地址。没有可用地址或加载失败时停留在启动器。
- `launchModeExperimental?: 'most-recent' | 'launcher'`：已弃用，保留兼容旧配置；设置 `launchMode` 时以 `launchMode` 为准。
- `defaultLaunchURL?: string`：启动器尝试打开的项目地址，支持 HTTP(S)、`exp(s)` 地址和开发客户端链接。地址必须有效，且不能包含登录凭据或 URL fragment。
- `toolsButton?: boolean`：设置浮动工具按钮的默认显示状态。
- `embeddedBundle?: boolean`：启用内置 bundle 入口；应用需提供内置 JavaScript bundle。
- `skipOnboarding?: boolean`：设置是否跳过首次启动引导。
- `showMenuAtLaunch?: boolean`：设置开发菜单的默认启动状态。
- `harmony`：可选的 HarmonyOS 专属配置；其中的配置项优先于顶层同名项，可使用以上字段。

这些默认设置不会覆盖用户已保存的设置。

### Permissions

- 配置插件会为开发服务连接和局域网服务发现声明 `ohos.permission.INTERNET` 与 `ohos.permission.GET_NETWORK_INFO`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
