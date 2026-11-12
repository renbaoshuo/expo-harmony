# @expo-harmony/expo-symbols

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-symbols) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/symbols/) | [鸿蒙图标库](https://developer.huawei.com/consumer/cn/design/harmonyos-symbol)

为 HarmonyOS 上的 React Native 应用提供 Expo Symbols 的原生实现，与官方同版本的 `expo-symbols` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 20（HarmonyOS 6.0.0）。

```bash
npm install @expo-harmony/expo-symbols expo-symbols
```

## API 对照表

### Components

#### `SymbolView`

显示 HarmonyOS 系统图标，接受下列属性及 React Native `ViewProps`。

##### `name`

类型：`string | HarmonySymbolName`，必填

对象形式读取 `harmony` 字段作为系统图标名称，例如 `house_fill`。字符串、没有 `harmony` 字段的对象、空名称、格式无效的名称或系统没有对应图标时渲染 `fallback`。不同 HarmonyOS 版本提供的系统图标可能不同。

##### `fallback`

类型：`React.ReactNode`

系统中没有 `name` 对应图标时显示的内容；未设置时不渲染内容。

##### `size`

类型：`number`，默认 `24`

图标字号，单位 vp，不随系统字体大小变化。接受非负有限数值；`0` 隐藏图形，负数或非有限数值抛出 `RangeError`。名称无效或图标不可用时会先显示 `fallback`，此时不校验字号。

默认容器尺寸为 `size × size`，`style` 中的宽高可覆盖容器尺寸。图形保持 `size` 指定的字号，并在容器中居中。

##### `weight`

类型：`SymbolWeight` 或对象形式，默认 `'unspecified'`

字符串值对应系统字重：`ultraLight`、`thin`、`light`、`regular`、`medium`、`semibold`、`bold`、`heavy` 和 `black` 分别映射到 100 至 900。省略、`unspecified` 或对象形式按 400 显示。实际字重效果取决于系统图标资源；未提供多种字重的图标保持资源默认外观。

##### `type`

类型：`SymbolType`，默认 `'monochrome'`

- `monochrome`：单色显示。
- `hierarchical`：按图层透明度分层显示。
- `palette`：使用 `colors` 提供的调色板。
- `multicolor`：使用系统图标的多色样式。

可用图层和颜色由 HarmonyOS 系统图标资源决定。

##### `tintColor`

类型：`ColorValue`

设置图标颜色，支持带透明度的 React Native 颜色。无法转换的颜色会抛出 `TypeError`。设置后优先于 `colors`；`hierarchical` 保留图层透明度，其他类型以指定颜色显示。移除后恢复调色板或系统配色。

##### `colors`

类型：`ColorValue | ColorValue[]`

仅当 `type` 为 `palette` 且未设置 `tintColor` 时，颜色数组才生效。数组至少包含两个颜色，最多使用前三个；单个颜色或少于两个颜色时不应用调色板。要使用系统多色样式，请设置 `type="multicolor"`。可通过 `style.opacity` 调整整个图标的透明度。

##### `scale`

- HarmonyOS 不提供独立的符号缩放级别；图形字号由 `size` 设置。

##### `resizeMode`

- HarmonyOS 按指定字号在容器中居中显示图形，不应用此属性的缩放模式。

##### `animationSpec`

- HarmonyOS 上图标静态显示，此属性不触发动画。

### Methods

#### `unstable_getMaterialSymbolSourceAsync(symbol, size, color)`

接收图标标识、字号和颜色，返回 `Promise<ImageSourcePropType | null>`。HarmonyOS 不提供 Material 图标资源，因此始终返回 `null`。

### Types

#### `HarmonySymbolName`

用于声明 HarmonyOS 系统图标名称的类型，`harmony` 字段为可选字符串。可从 `@expo-harmony/expo-symbols/src` 通过 `import type` 导入。

#### `SymbolViewProps`

`SymbolView` 的属性类型，包含上述图标属性并继承 React Native `ViewProps`。

#### `SymbolType`

图标样式类型，取值为 `'monochrome'`、`'hierarchical'`、`'palette'` 或 `'multicolor'`；各值的显示效果见 `SymbolView.type`。

#### `SymbolWeight`

图标字重类型，取值为 `'unspecified'`、`'ultraLight'`、`'thin'`、`'light'`、`'regular'`、`'medium'`、`'semibold'`、`'bold'`、`'heavy'` 或 `'black'`。HarmonyOS 上的字重映射见 `SymbolView.weight`。

#### `SymbolScale`

符号缩放级别类型，取值为 `'default'`、`'unspecified'`、`'small'`、`'medium'` 或 `'large'`。

- HarmonyOS 不应用这些缩放级别，图形字号由 `SymbolView.size` 设置。

#### `ContentMode`

容器内容显示方式类型，包含 `'scaleToFill'`、`'scaleAspectFit'`、`'scaleAspectFill'`、`'redraw'`、`'center'`、`'top'`、`'bottom'`、`'left'`、`'right'`、`'topLeft'`、`'topRight'`、`'bottomLeft'` 和 `'bottomRight'`。

- HarmonyOS 不应用这些显示方式，图形按 `size` 指定的字号在容器中居中显示。

#### `AnimationSpec`

`animationSpec` 属性的类型，包含 `effect`、`repeating`、`repeatCount`、`speed` 和 `variableAnimationSpec` 等动画配置字段。

- HarmonyOS 上图标静态显示，这些配置不触发动画。

#### `AnimationEffect`

动画效果的配置类型，包含 `type`、`wholeSymbol` 和 `direction` 字段。

#### `AnimationType`

动画效果类型，取值为 `'bounce'`、`'pulse'` 或 `'scale'`。

#### `VariableAnimationSpec`

图标图层动画的配置类型，包含 `reversing`、`nonReversing`、`cumulative`、`iterative`、`hideInactiveLayers` 和 `dimInactiveLayers` 字段。HarmonyOS 上这些配置不产生动画效果。

### Error codes

#### `ERR_SYMBOL_RESOURCE`

查询系统图标资源失败时抛出。图标名称格式无效或系统中不存在对应图标时会显示 `fallback`，不抛出此错误。

#### `ERR_SYMBOL_WEIGHT`

传入无法识别的字重值时抛出。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
