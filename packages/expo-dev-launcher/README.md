# @expo-harmony/expo-dev-launcher

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-dev-launcher) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/dev-client/)

为 HarmonyOS 上的 React Native 应用提供 Expo Dev Launcher 的原生实现，与官方同版本的 `expo-dev-launcher` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-dev-launcher expo-dev-launcher
```

## API 对照表

### Methods

#### `devLauncher(options?)`

类型化插件入口，参数为 `PluginConfigType`，返回 Expo 配置插件元组 `['@expo-harmony/expo-dev-launcher', options]`。通过 `@expo-harmony/expo-dev-launcher/plugin` 导入。

### Types

#### `PluginConfigOptions`

HarmonyOS 启动器配置项：

- `launchMode?: 'most-recent' | 'launcher'`：启动时先尝试最近项目，失败后使用 `defaultLaunchURL`；`launcher` 跳过最近项目。默认 `most-recent`。
- `launchModeExperimental?: 'most-recent' | 'launcher'`：`launchMode` 的弃用别名。
- `defaultLaunchURL?: string`：默认项目地址，支持 HTTP(S)、`exp(s)` 地址及开发客户端链接；不能包含登录凭据或 URL fragment。
- `toolsButton?: boolean`：浮动工具按钮的初始显示状态。
- `embeddedBundle?: boolean`：是否显示加载内置 bundle 的入口；启用时应用需提供内置 JavaScript bundle。
- `skipOnboarding?: boolean`：是否跳过启动器引导。
- `showMenuAtLaunch?: boolean`：是否在启动时打开开发菜单。

上述布尔值用于设置初始状态；用户保存的设置优先。

#### `PluginConfigType`

插件配置类型。选项可放在顶层，或放在 `harmony` 对象中；同名的 `harmony` 选项优先。

### Permissions

注册插件后，HarmonyOS 应用清单会声明 `ohos.permission.INTERNET`，用于加载开发项目；同时声明 `ohos.permission.GET_NETWORK_INFO`，用于发现局域网内的开发服务。

## 插件配置

如果同时使用 `@expo-harmony/expo-dev-client`，还需要在 Expo 配置中单独注册本包的插件。

```json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-dev-launcher",
        {
          "launchMode": "launcher",
          "toolsButton": true
        }
      ]
    ],
    "harmony": {
      "bundleName": "com.example.app"
    }
  }
}
```

`launchMode` 可设为 `most-recent`（默认）或 `launcher`。前者先尝试打开最近项目，失败后再尝试 `defaultLaunchURL`；后者跳过最近项目，直接尝试默认地址。未设置默认地址或加载失败时会停留在启动器。`defaultLaunchURL` 支持 HTTP(S)、`exp(s)` 地址和开发客户端链接，不能包含登录凭据或 URL fragment。

`toolsButton`、`skipOnboarding` 和 `showMenuAtLaunch` 分别控制浮动工具按钮、是否跳过引导和是否在启动时打开菜单。用户保存的设置优先于这些默认值。

设为 `embeddedBundle: true` 后，启动器会显示“Load embedded bundle”。使用此功能时，应用需要提供内置 JavaScript bundle。内置项目不会保存到最近项目列表。

也可以在 TypeScript 配置中注册插件：

```ts
import devLauncher from '@expo-harmony/expo-dev-launcher/plugin';

export default { plugins: [devLauncher({ launchMode: 'launcher', skipOnboarding: true })] };
```

## 启动器

启动器会列出最近打开的项目和局域网内发现的开发服务，也可手动输入项目地址或扫码。失效的服务会从列表中移除，用户可以手动刷新。最近项目按地址去重并保存三天。扫码使用系统扫码界面，无需额外申请相机权限；设备不支持扫码时会显示错误。

开发构建可通过 `expo-harmony://open?url=...` 链接打开项目，应用自己的深链接仍可正常使用。链接可附带 `disableOnboarding=1`、`disableFab=1` 或 `disableAutoLaunch=1`，分别用于跳过引导、隐藏浮动工具按钮或关闭启动时自动打开菜单。发布版本不会打开开发链接。

加载的项目需要与开发客户端包含的运行环境和原生功能相匹配。已发布的项目需要客户端安装 `@expo-harmony/expo-updates`，否则无法加载。

从开发菜单选择 Home 会返回启动器。JavaScript 运行时错误会保留三天；再次启动时，启动器会显示错误信息，不会自动重新打开出错项目。系统原生崩溃不在此列。

### 暂不支持的内容

- 账户登录和 EAS 分支浏览。HarmonyOS 开发客户端不提供 EAS 账户功能。
- 按应用标识或用户筛选项目、查看签名证书或本地网络权限。HarmonyOS 开发客户端不提供这些信息。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
