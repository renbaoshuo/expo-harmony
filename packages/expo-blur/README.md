# @expo-harmony/expo-blur

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-blur) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/blur-view/)

为 HarmonyOS 上的 React Native 应用提供 Expo Blur 的原生实现，与官方 `expo-blur` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-blur expo-blur@~57.0.3
```

## API 对照表

### Components

#### `BlurView`

在视图区域显示系统材质模糊层，子内容绘制在模糊层上方。模糊层不拦截触摸事件。

##### `tint`

类型：`BlurTint`，默认值为 `'default'`。

色调对应的系统材质厚度如下：

- 极薄：`extraLight`、`systemUltraThinMaterial`、`systemUltraThinMaterialLight`、`systemUltraThinMaterialDark`
- 薄：`light`、`systemThinMaterial`、`systemThinMaterialLight`、`systemThinMaterialDark`
- 常规：`default`、`regular`、`dark`、`systemMaterial`、`systemMaterialLight`、`systemMaterialDark`
- 厚：`systemThickMaterial`、`systemThickMaterialLight`、`systemThickMaterialDark`
- 极厚：`prominent`、`systemChromeMaterial`、`systemChromeMaterialLight`、`systemChromeMaterialDark`

`light`、`extraLight` 和名称以 `Light` 结尾的值固定使用浅色模式；`dark` 和名称以 `Dark` 结尾的值固定使用深色模式；其他值跟随系统。材质的颜色、饱和度和模糊外观由系统决定。

##### `intensity`

类型：`number`，默认值为 `50`，范围为 `0` 到 `100`。超出范围的值按边界处理；`0` 时不显示模糊效果。非有限数值的更新会被忽略，保留之前的值。相同强度下，不同材质的模糊观感由系统决定。

##### `blurMethod`

类型：`BlurMethod`，默认值为 `'none'`。

- HarmonyOS 的模糊方式由系统材质确定，此属性不生效。

##### `blurReductionFactor`

类型：`number`，默认值为 `4`。

- 系统材质不提供独立的强度缩减系数，此属性不生效。

##### `blurTarget`

类型：`RefObject<View | null>`。

- 模糊范围由 `BlurView` 自身的位置决定，此属性不生效。

#### `BlurTargetView`

按普通容器显示，可使用容器属性和子内容。

- HarmonyOS 不使用此组件指定模糊范围。

### Types

#### `BlurTint`

取值为 `light`、`dark`、`default`、`extraLight`、`regular`、`prominent`，以及 `systemUltraThinMaterial`、`systemThinMaterial`、`systemMaterial`、`systemThickMaterial`、`systemChromeMaterial` 和这些材质的 `Light`、`Dark` 变体。材质对应关系见 [`BlurView.tint`](#tint)。

#### `BlurMethod`

取值为 `'none'`、`'dimezisBlurView'` 或 `'dimezisBlurViewSdk31Plus'`。

- HarmonyOS 始终使用系统材质，此类型对应的模糊方式选择不生效。

#### `BlurViewProps`

`BlurView` 的属性类型，包含 React Native `ViewProps` 以及 `tint`、`intensity`、`blurMethod`、`blurReductionFactor` 和 `blurTarget`。

#### `BlurTargetViewProps`

`BlurTargetView` 的属性类型，包含 React Native `ViewProps` 和可选的 `ref`（`RefObject<View | null>`）。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
