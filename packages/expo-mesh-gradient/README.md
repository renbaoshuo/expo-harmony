# @expo-harmony/expo-mesh-gradient

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-mesh-gradient) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/mesh-gradient/)

为 HarmonyOS 上的 React Native 应用提供 Expo Mesh Gradient 的原生实现，与官方 `expo-mesh-gradient` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 23（HarmonyOS 6.1.0）。

```bash
npm install @expo-harmony/expo-mesh-gradient expo-mesh-gradient@~57.0.2
```

## API 对照表

### Components

#### `MeshGradientView`

绘制网格渐变的视图，从 `expo-mesh-gradient` 导入。接受 React Native `ViewProps` 和子视图；子视图显示在渐变上方并可交互。

```tsx
import { MeshGradientView } from 'expo-mesh-gradient';

<MeshGradientView
  style={{ width: 300, height: 300 }}
  columns={2}
  rows={2}
  points={[[0, 0], [1, 0], [0, 1], [1, 1]]}
  colors={['red', 'orange', 'blue', 'purple']}
/>;
```

##### `columns`

类型：`number`，默认 `0`。指定每行的顶点数，须为非负整数。值为 `0` 或 `1` 时不绘制渐变。

##### `rows`

类型：`number`，默认 `0`。指定每列的顶点数，须为非负整数。值为 `0` 或 `1` 时不绘制渐变。

##### `points`

类型：`number[][]`，默认 `[]`。按行排列的顶点坐标，数量须为 `columns * rows`；每个顶点为 `[x, y]`，坐标相对于视图宽高，须为有限数值。坐标可以超出 `[0, 1]`，超出视图的部分会被裁剪。

##### `colors`

类型：`ColorValue[]`，默认 `[]`。每个顶点对应一个颜色，数量须为 `columns * rows`，支持透明度。不支持对象形式的动态颜色。

##### `smoothsColors`

类型：`boolean`，默认 `true`。控制顶点之间的颜色过渡：`true` 使用 sRGB 色彩空间的平滑过渡，`false` 使用 Oklab 色彩空间的线性过渡。网格边缘以曲线连接；行列数不相等时，部分纵向边缘形状可能与预期不同。

##### `resolution`

类型：`{ x?: number; y?: number }`，`x`、`y` 各自默认 `8`，须为正整数。控制网格曲线的细分程度。HarmonyOS 的默认值为 `8`。

行列数、分辨率、顶点或颜色不符合要求时，渐变会被清除并在控制台输出警告；子视图仍可交互。采样顶点数上限为 `65,536`，超出时不会绘制渐变。有效参数恢复后会重新绘制。

##### `mask`

- HarmonyOS 上不生效：不支持根据子视图的透明度裁剪渐变，子视图仍会显示并响应交互。

##### `ignoresSafeArea`

- HarmonyOS 上不生效：视图按 React Native 布局范围绘制，不会扩展到安全区域之外。

### Types

#### `MeshGradientViewProps`

`MeshGradientView` 的属性类型，包含 React Native `ViewProps` 以及 `columns`、`rows`、`points`、`colors`、`smoothsColors`、`resolution`、`mask` 和 `ignoresSafeArea`。HarmonyOS 上的属性行为见 [`MeshGradientView`](#meshgradientview)。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
