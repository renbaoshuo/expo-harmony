# @expo-harmony/expo-system-ui

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-system-ui) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/system-ui/)

为 HarmonyOS 上的 React Native 应用提供 Expo System UI 的原生实现，与官方同版本的 `expo-system-ui` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-system-ui expo-system-ui
```

## 构建期配置

要在构建期配置背景色和界面模式，在 `app.json` 的 `plugins` 中注册 `@expo-harmony/expo-system-ui`，配置写在 `harmony` 字段下。这两项在窗口页面加载完成后应用，不改变系统启动图：

```json
{
  "expo": {
    "plugins": ["@expo-harmony/expo-system-ui"],
    "harmony": {
      "bundleName": "com.example.app",
      "backgroundColor": "#FFFFFF",
      "userInterfaceStyle": "automatic"
    }
  }
}
```

也可以在 `app.config.ts` 中使用 TypeScript 配置插件：

```ts
import systemUI from '@expo-harmony/expo-system-ui/plugin';

export default {
  expo: {
    plugins: [systemUI()],
    harmony: {
      bundleName: 'com.example.app',
      backgroundColor: '#FFFFFF',
      userInterfaceStyle: 'automatic',
    },
  },
};
```

`backgroundColor` 接受 React Native 支持的 CSS 颜色。`userInterfaceStyle` 可设为 `light`、`dark` 或 `automatic`，省略时按 `light` 处理。两项优先读取 `harmony` 字段下的值，没有时读取 Expo 顶层的同名配置。

`userInterfaceStyle` 在窗口页面加载完成和回到前台时应用。`light` 和 `dark` 把界面模式固定下来。`automatic` 取消本模块先前设置的模式，恢复系统默认的继承行为。API 18 及以上界面模式设置在当前 UIAbility 上，`automatic` 跟随宿主的应用级设置，没有时跟随系统。API 13–17 设置在整个应用上，多个 Ability 共享这一设置。

运行时读写背景色直接使用 `SystemUI.getBackgroundColorAsync` 和 `SystemUI.setBackgroundColorAsync`，插件只用于构建期的初始配置。

## API 对照表

### Methods

#### `SystemUI.setBackgroundColorAsync(color: ColorValue | null): Promise<void>`

将当前窗口背景色设为 `color`。`color` 接受有效的 CSS 3 (SVG) 颜色；传入 `null` 会清除已设置的颜色，恢复当前界面模式对应的默认背景色。

在窗口页面就绪前调用会等待页面就绪。如果等待期间窗口销毁或替换，Promise 会以错误拒绝。

设置的颜色会在应用重启后恢复，并覆盖构建期配置的背景色。系统无法保存颜色时，本次调用仍会更新当前窗口，但重启后不保证恢复。

#### `SystemUI.getBackgroundColorAsync(): Promise<ColorValue | null>`

返回当前窗口背景色，格式为不带透明度的小写 `#rrggbb`。若当前窗口尚无本包记录的背景色，则返回 `null`。

- HarmonyOS 不支持直接读取窗口背景色，因此返回本包为当前窗口记录并应用的颜色；如果其他代码修改了窗口背景色，返回值不会反映该修改。

未设置背景色时，默认背景色随界面模式变化：`light` 为白色，`dark` 为黑色，`automatic` 跟随当前有效的深浅色模式。

### Error codes

- `ERR_SYSTEM_UI_COLOR`：传入的颜色参数无效，无法用于当前窗口。
- `ERR_SYSTEM_UI_WINDOW`：当前应用窗口不可用，或操作完成前窗口已销毁或替换。
- `ERR_SYSTEM_UI_ABILITY_NOT_INITIALIZED`：当前 UIAbility 尚未完成 System UI 初始化。
- `ERR_SYSTEM_UI_DESTROYED`：调用时 Expo 运行时或 UIAbility 已销毁。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
