# @expo-harmony/expo-linear-gradient

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-linear-gradient) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/linear-gradient/)

为 HarmonyOS 上的 React Native 应用提供 Expo LinearGradient 的原生实现，与官方 `expo-linear-gradient` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-linear-gradient expo-linear-gradient@~57.0.2
```

## API 对照表

### Components

#### `LinearGradient`

沿指定方向绘制多色渐变的视图。子组件显示在渐变上方；渐变不拦截触摸事件。视图的圆角会裁剪渐变内容。组件接受 React Native `ViewProps`。

##### `colors`

类型：`readonly [ColorValue, ColorValue, ...ColorValue[]]`。

按顺序指定渐变颜色，至少需要两个颜色。少于两个颜色或颜色值无效时，本次更新不绘制渐变，并保留之前有效的渐变。

##### `locations`

类型：`readonly [number, number, ...number[]] | null`，默认 `null`。

指定每种颜色沿渐变轴的位置，取值为 `0` 到 `1`，顺序须从小到大；相同位置可形成硬过渡。省略或设为 `null` 时，颜色均匀分布。位置数量多于颜色时，多余位置会被忽略；位置数量少于颜色、超出范围或顺序无效时，本次渐变更新不生效，保留之前有效的渐变。首个位置大于 `0` 或末个位置小于 `1` 时，端点颜色延伸至渐变轴两端。

##### `start`

类型：`LinearGradientPoint | null`，默认 `{ x: 0.5, y: 0 }`。

指定渐变起点，`x` 和 `y` 分别相对于视图宽度和高度。可使用 `{ x, y }` 或 `[x, y]`。

##### `end`

类型：`LinearGradientPoint | null`，默认 `{ x: 0.5, y: 1 }`。

指定渐变终点，`x` 和 `y` 分别相对于视图宽度和高度，写法与 `start` 相同。

##### `dither`

- 不支持此属性：HarmonyOS 没有对应的渐变抖动设置。

### Types

#### `LinearGradientPoint`

表示渐变起点或终点，可写为 `{ x: number; y: number }` 或 `[x: number, y: number]`。坐标相对于视图宽高；HarmonyOS 接受超出 `0` 到 `1` 的有限数值，渐变轴相应延伸到视图范围之外。

#### `NativeLinearGradientPoint`

渐变起点或终点的数组形式：`[x: number, y: number]`。

#### `LinearGradientProps`

`LinearGradient` 的属性类型，包含 React Native `ViewProps` 以及 `colors`、`locations`、`start`、`end` 和 `dither`。其中 `dither` 在 HarmonyOS 上不生效。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
