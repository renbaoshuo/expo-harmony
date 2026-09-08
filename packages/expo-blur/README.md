# @expo-harmony/expo-blur

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-blur) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/blur-view/)

为 HarmonyOS 上的 React Native 应用提供 `expo-blur` 的原生实现，与官方同版本的 `expo-blur` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-blur expo-blur@55.0.14
```

## API 对照表

### Component

#### `BlurView`

模糊视图组件。在子组件下方渲染一层系统材质模糊，模糊层不接收触摸事件，触摸会落到子组件上。

#### `tint`

类型：`BlurTint`，默认 `'default'`

模糊色调。HarmonyOS 的材质分五档厚度，多个 `tint` 取值对应同一档材质，`Light`、`Dark` 变体只切换明暗模式，不改变厚度。

| 材质档位 | `tint` 取值                                                                                          |
| -------- | ---------------------------------------------------------------------------------------------------- |
| 极薄     | `extraLight`、`systemUltraThinMaterial`、`systemUltraThinMaterialLight`、`systemUltraThinMaterialDark` |
| 薄       | `light`、`systemThinMaterial`、`systemThinMaterialLight`、`systemThinMaterialDark`                    |
| 常规     | `default`、`regular`、`dark`、`systemMaterial`、`systemMaterialLight`、`systemMaterialDark`            |
| 厚       | `systemThickMaterial`、`systemThickMaterialLight`、`systemThickMaterialDark`                           |
| 极厚     | `prominent`、`systemChromeMaterial`、`systemChromeMaterialLight`、`systemChromeMaterialDark`           |

`light`、`extraLight` 和 `Light` 变体固定按浅色模式渲染，`dark` 和 `Dark` 变体固定按深色模式渲染，其余跟随系统。

#### `intensity`

类型：`number`，默认 `50`

模糊强度，取值 0 到 100，超出范围钳制到边界。取 0 时不模糊。非有限值忽略，保持之前的值。强度是相对同一档材质模糊程度的比例，相同强度在不同 `tint` 下看到的模糊量不同。

#### `BlurTargetView`

包裹需要被模糊的内容。HarmonyOS 上按普通容器渲染，不参与模糊计算，把它的 ref 传给 `blurTarget` 也不会改变模糊范围。

> **未实现的内容**
>
> - `blurMethod`：Android 专属属性，用于选择 Android 上的模糊实现，HarmonyOS 的模糊统一由系统材质提供，该取值不生效。
> - `blurReductionFactor`：Android 专属属性，用于调整 Android 上不同实现之间的模糊强度差异，HarmonyOS 上没有对应行为。
> - `blurTarget`：Android 专属属性，用于指定被模糊的内容，HarmonyOS 的模糊层始终作用于自身下方的内容，该属性不生效。

### Types

#### `BlurTint`

`'light' | 'dark' | 'default' | 'extraLight' | 'regular' | 'prominent' | 'systemUltraThinMaterial' | 'systemThinMaterial' | 'systemMaterial' | 'systemThickMaterial' | 'systemChromeMaterial' | 'systemUltraThinMaterialLight' | 'systemThinMaterialLight' | 'systemMaterialLight' | 'systemThickMaterialLight' | 'systemChromeMaterialLight' | 'systemUltraThinMaterialDark' | 'systemThinMaterialDark' | 'systemMaterialDark' | 'systemThickMaterialDark' | 'systemChromeMaterialDark'`，默认 `'default'`。

取值与材质的对应关系见 `BlurView.tint`。

#### `BlurViewProps`

`BlurView` 的属性类型，在 `ViewProps` 之上增加 `tint`、`intensity` 和 Android 专属属性。

#### `BlurTargetViewProps`

`BlurTargetView` 的属性类型，在 `ViewProps` 之上增加 `ref`。

> **未实现的内容**
>
> - `BlurMethod`：Android 专属类型，用于选择 Android 上的模糊实现，HarmonyOS 上不生效。
> - `ExperimentalBlurMethod`：已弃用的 Android 专属类型，HarmonyOS 上不生效。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
