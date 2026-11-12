# @expo-harmony/expo-dev-menu-interface

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-dev-menu-interface)

为 HarmonyOS 上的 React Native 应用提供 Expo Dev Menu Interface 的原生实现，与官方同版本的 `expo-dev-menu-interface` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-dev-menu-interface expo-dev-menu-interface
```

## API 对照表

### Types

#### `DevMenuManagerProtocol`

开发菜单的可见状态和操作。

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `isVisible` | `boolean` | 菜单当前是否可见。 |
| `openMenu(screen?: string \| null): boolean` | 方法 | 打开菜单；省略 `screen` 或传入 `null` 时打开默认页面。若菜单已打开或当前不可打开，返回 `false`；否则返回 `true`，菜单随后显示。 |
| `closeMenu(): boolean` | 方法 | 收起菜单。菜单已收起时返回 `false`，否则返回 `true`。 |
| `hideMenu(): boolean` | 方法 | 收起菜单，行为与 `closeMenu()` 相同。 |
| `toggleMenu(): boolean` | 方法 | 切换菜单的显示状态，返回值表示是否接受请求。 |

#### `DevMenuBridgeProtocol`

用于提供原生模块查询和重载操作；三个成员均可省略。

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `module?(name: string): Object \| null` | 方法 | 按名称查找模块；找不到时返回 `null`。 |
| `modulesConforming?(conforms: (module: Object) => boolean): Object[]` | 方法 | 返回所有使 `conforms` 返回 `true` 的模块。 |
| `requestReload?(): void` | 方法 | 请求重载应用。 |

- HarmonyOS 未提供完整的原生模块列表，因此无法按名称查询或筛选模块。
- 本包不提供通用重载桥接，因此不能通过 `requestReload` 请求重载。

#### `DevMenuHostDelegate`

宿主可选实现的菜单行为回调。

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `devMenuNavigateHome?(): void` | 方法 | 返回宿主应用的首页。 |
| `devMenuTogglePerformanceMonitor?(): void` | 方法 | 切换宿主的性能监视器。 |
| `devMenuToggleElementInspector?(): void` | 方法 | 切换宿主的元素检查器。 |
| `devMenuShouldShowReactNativeDevMenu?(): boolean` | 方法 | 返回是否显示 React Native 开发菜单入口；省略时默认为 `true`。 |

#### `DevMenuUIResponderExtensionProtocol`

键盘事件回调。

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `EXDevMenu_handleKeyCommand(key: KeyEvent): void` | 方法 | 接收 ArkUI 键盘事件。启用快捷键时，Ctrl/Command + D 切换菜单，Ctrl/Command + R 重载应用，Ctrl/Command + I 切换元素检查器，Ctrl/Command + P 切换性能监视器。带 Alt 或 Shift 修饰键时不处理；软键盘弹出时快捷键不可用。 |

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
