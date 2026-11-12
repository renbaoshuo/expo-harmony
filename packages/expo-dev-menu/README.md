# @expo-harmony/expo-dev-menu

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-dev-menu) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/dev-menu/)

为 HarmonyOS 上的 React Native 应用提供 Expo Dev Menu 的原生实现，与官方同版本的 `expo-dev-menu` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-dev-menu expo-dev-menu
```

## API 对照表

### Methods

#### `openMenu()`

无参数，返回 `void`，打开开发菜单。菜单包含重新加载、元素检查、React Native DevTools、性能监视器、Fast Refresh、设置和源码查看；宿主提供返回首页行为时，也会显示相应入口。应用加载完成后即可打开菜单。

开发构建中会显示可拖动的悬浮菜单按钮，按钮位置会保存。应用退到后台、键盘弹出、引导页未完成或菜单打开时，按钮会隐藏。也可通过三指长按或外接键盘快捷键打开菜单：Ctrl/Command + D 切换菜单，Ctrl/Command + R、I、P 分别用于重新加载、切换元素检查器和性能监视器。菜单设置可关闭三指长按和快捷键。

- 摇动设备或从 React Native 开发菜单打开时，需要在该菜单中选择 “Open Expo development menu”；HarmonyOS 上摇动入口由 React Native 开发菜单管理，不能直接打开 Expo 开发菜单。
- React Native DevTools 和 Fast Refresh 仅在已加载 Metro 开发 bundle 时可用。Fast Refresh 开关状态会保存，并控制当前开发 bundle 的热更新。

源码查看器可浏览和搜索 source map 中的文件、复制源码或临时编辑；临时编辑不会改变运行中的应用。source map 未包含源码内容时，该文件无法查看。菜单还显示 bundle 地址、应用版本以及 runtimeVersion 或 SDK 版本，并支持复制这些信息。

#### `closeMenu()`

无参数，返回 `void`，收起开发菜单。

#### `hideMenu()`

无参数，返回 `void`，收起开发菜单；在 HarmonyOS 上与 `closeMenu()` 行为相同。

#### `registerDevMenuItems(items)`

传入 `ExpoDevMenuItem[]`，返回 `Promise<void>`。再次调用会替换此前注册的所有菜单项，传入空数组可清除。选中项目时会调用该项的 `callback`；`shouldCollapse` 控制是否收起菜单，HarmonyOS 上省略时默认为 `true`。`name` 应保持唯一；名称重复时，选择同名项目会调用最后注册的回调。

### Types

#### `ExpoDevMenuItem`

自定义菜单项，包含 `name: string`（菜单标签）、`callback: () => void`（选中时执行）和可选的 `shouldCollapse: boolean`（选中后是否收起菜单，HarmonyOS 上默认为 `true`）。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
