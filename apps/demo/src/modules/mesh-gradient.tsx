/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { MeshGradientView } from 'expo-mesh-gradient';
import { useState } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';

import { palette } from '../theme';
import { ActionRow, Panel } from '../ui';
import { Cycle, Toggle } from './visual-controls';

const colors = ['#FF7064', '#FFB000', '#FFE79B', '#C36BF0', '#FFFFFF', '#51D88A', '#7B61FF', '#72D8FF', '#007AFF'];

export function MeshGradientDemo() {
  const [columns, setColumns] = useState(3);
  const [rows, setRows] = useState(3);
  const [shifted, setShifted] = useState(false);
  const [reversed, setReversed] = useState(false);
  const [smoothsColors, setSmoothsColors] = useState(true);
  const [transparent, setTransparent] = useState(false);
  const [resolutionX, setResolutionX] = useState(8);
  const [resolutionY, setResolutionY] = useState(8);
  const [mask, setMask] = useState(false);
  const [ignoresSafeArea, setIgnoresSafeArea] = useState(false);

  const points = Array.from({ length: columns * rows }, (_, index) => {
    const column = index % columns;
    const row = Math.floor(index / columns);
    const x = column / (columns - 1);
    const y = row / (rows - 1);
    return shifted && column === 1 && columns === 3 ? [x - 0.2, y] : [x, y];
  });
  const activeColors = colors.slice(0, points.length);
  if (reversed) activeColors.reverse();

  return (
    <Panel title="MeshGradientView">
      <View style={styles.scene}>
        {mask ? null : <Text style={styles.backdrop}>网格渐变</Text>}
        <MeshGradientView
          columns={columns}
          rows={rows}
          points={points}
          colors={transparent ? activeColors.map(color => `${color}66`) : activeColors}
          smoothsColors={smoothsColors}
          resolution={{ x: resolutionX, y: resolutionY }}
          mask={mask}
          ignoresSafeArea={ignoresSafeArea}
          style={StyleSheet.absoluteFill}
          testID="mesh-gradient-preview"
        >
          {mask ? <Text style={styles.mask}>网格渐变</Text> : null}
        </MeshGradientView>
      </View>
      <ActionRow>
        <Cycle label="列数" value={columns} choices={[2, 3]} onChange={setColumns} />
        <Cycle label="行数" value={rows} choices={[2, 3]} onChange={setRows} />
        <Toggle label="移动中间列" value={shifted} onChange={setShifted} disabled={columns !== 3} />
        <Toggle label="反转颜色" value={reversed} onChange={setReversed} />
        <Toggle label="半透明" value={transparent} onChange={setTransparent} />
        <Toggle label="平滑过渡" value={smoothsColors} onChange={setSmoothsColors} />
      </ActionRow>
      {Platform.OS !== 'ios'
        ? (
            <ActionRow>
              <Cycle label="横向采样" value={resolutionX} choices={[1, 8, 16]} onChange={setResolutionX} />
              <Cycle label="纵向采样" value={resolutionY} choices={[1, 8, 16]} onChange={setResolutionY} />
            </ActionRow>
          )
        : (
            <ActionRow>
              <Toggle label="用文字裁剪渐变" value={mask} onChange={setMask} />
              <Toggle label="忽略安全区" value={ignoresSafeArea} onChange={setIgnoresSafeArea} />
            </ActionRow>
          )}
    </Panel>
  );
}

const styles = StyleSheet.create({
  scene: { alignItems: 'center', backgroundColor: palette.surfaceRaised, borderRadius: 12, height: 192, justifyContent: 'center', overflow: 'hidden' },
  backdrop: { color: palette.text, fontSize: 30, fontWeight: '800' },
  mask: { fontSize: 40, fontWeight: '900', textAlign: 'center' },
});
