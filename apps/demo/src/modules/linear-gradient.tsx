/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { LinearGradient, type LinearGradientPoint } from 'expo-linear-gradient';
import { useState } from 'react';
import { Platform, StyleSheet, Text } from 'react-native';

import { ActionRow, DataRow, Panel } from '../ui';
import { Cycle, Toggle } from './visual-controls';

const palettes = {
  三色: ['#FFB000', '#72D8FF', '#7B61FF'],
  冷色: ['#172554', '#2563EB', '#67E8F9'],
  暖色: ['#FB7185', '#F97316', '#FDE68A'],
} as const;
const stops = {
  均匀: null,
  偏移: [0.2, 0.7, 1],
  硬过渡: [0, 0.55, 0.55],
} as const;
const points = {
  默认: null,
  左上: [0, 0],
  右上: [1, 0],
  左下: [0, 1],
  右下: [1, 1],
  视图外: { x: 1.5, y: 0.5 },
} satisfies Record<string, LinearGradientPoint | null>;

export function LinearGradientDemo() {
  const [colors, setColors] = useState<keyof typeof palettes>('三色');
  const [locations, setLocations] = useState<keyof typeof stops>('均匀');
  const [start, setStart] = useState<keyof typeof points>('左上');
  const [end, setEnd] = useState<keyof typeof points>('右下');
  const [dither, setDither] = useState(true);
  const [rounded, setRounded] = useState(true);

  return (
    <Panel title="LinearGradient">
      <LinearGradient
        colors={palettes[colors]}
        locations={stops[locations]}
        start={points[start]}
        end={points[end]}
        dither={dither}
        style={[styles.preview, rounded ? styles.rounded : null]}
        testID="linear-gradient-preview"
      >
        <Text style={styles.caption}>线性渐变</Text>
      </LinearGradient>
      <DataRow label="颜色位置" value={stops[locations]?.join(' / ') ?? '均匀分布'} />
      <ActionRow>
        <Cycle label="配色" value={colors} choices={['三色', '冷色', '暖色']} onChange={setColors} />
        <Cycle label="颜色位置" value={locations} choices={['均匀', '偏移', '硬过渡']} onChange={setLocations} />
        <Cycle label="起点" value={start} choices={['默认', '左上', '右上', '左下', '右下', '视图外']} onChange={setStart} />
        <Cycle label="终点" value={end} choices={['默认', '左上', '右上', '左下', '右下', '视图外']} onChange={setEnd} />
        <Toggle label="圆角" value={rounded} onChange={setRounded} />
        {Platform.OS === 'android' ? <Toggle label="抖动" value={dither} onChange={setDither} /> : null}
      </ActionRow>
    </Panel>
  );
}

const styles = StyleSheet.create({
  preview: { height: 160, justifyContent: 'flex-end', padding: 18 },
  rounded: { borderBottomRightRadius: 24, borderTopLeftRadius: 24, overflow: 'hidden' },
  caption: { color: '#111920', fontSize: 24, fontWeight: '800' },
});
