/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { HarmonySymbolName } from '@expo-harmony/expo-symbols/src';
import { SymbolView, unstable_getMaterialSymbolSourceAsync } from 'expo-symbols';
import type { AndroidSymbol, AnimationSpec, AnimationType, ContentMode, SymbolScale, SymbolType, SymbolWeight } from 'expo-symbols';
import { useState } from 'react';
import { Image, Platform, StyleSheet, Text, View, type ImageSourcePropType } from 'react-native';

import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { Cycle, Toggle } from './visual-controls';

const types: SymbolType[] = ['monochrome', 'hierarchical', 'palette', 'multicolor'];
const weights: SymbolWeight[] = ['unspecified', 'ultraLight', 'thin', 'light', 'regular', 'medium', 'semibold', 'bold', 'heavy', 'black'];
const scales: SymbolScale[] = ['default', 'unspecified', 'small', 'medium', 'large'];
const contentModes: ContentMode[] = [
  'scaleToFill', 'scaleAspectFit', 'scaleAspectFill', 'redraw', 'center',
  'top', 'bottom', 'left', 'right', 'topLeft', 'topRight', 'bottomLeft', 'bottomRight',
];
const names = {
  文件夹: { ios: 'folder.badge.plus', android: 'create_new_folder', web: 'create_new_folder', harmony: 'ohos_folder_badge_plus' },
  房屋: { ios: 'house.fill', android: 'home', web: 'home', harmony: 'house_fill' },
  无线网络: { ios: 'wifi', android: 'wifi', web: 'wifi', harmony: 'ohos_wifi' },
  箭头: { ios: 'arrow.up', android: 'arrow_upward', web: 'arrow_upward', harmony: 'ohos_arrow_up' },
  占位: {},
} satisfies Record<string, HarmonySymbolName>;

export function SymbolsDemo() {
  const [preset, setPreset] = useState<keyof typeof names>('文件夹');
  const [harmonyName, setHarmonyName] = useState('');
  const [size, setSize] = useState(64);
  const [weight, setWeight] = useState<SymbolWeight>('regular');
  const [type, setType] = useState<SymbolType>('palette');
  const [tint, setTint] = useState('');
  const [colors, setColors] = useState('#007AFF, #FF9500, #34C759');
  const [fallback, setFallback] = useState('图标不可用');
  const [layout, setLayout] = useState('');
  const [scale, setScale] = useState<SymbolScale>('default');
  const [resizeMode, setResizeMode] = useState<ContentMode>('scaleAspectFit');
  const [effect, setEffect] = useState<AnimationType>('bounce');
  const [direction, setDirection] = useState<'up' | 'down'>('up');
  const [wholeSymbol, setWholeSymbol] = useState(true);
  const [repeating, setRepeating] = useState(false);
  const [repeatCount, setRepeatCount] = useState(2);
  const [speed, setSpeed] = useState(1);
  const [animate, setAnimate] = useState(false);
  const name = harmonyName.trim();
  const symbol: HarmonySymbolName = name ? { ...names[preset], harmony: name } : names[preset];
  const animationSpec: AnimationSpec | undefined = animate
    ? { effect: { type: effect, direction, wholeSymbol }, repeating, repeatCount, speed }
    : undefined;

  return (
    <>
      <Panel title="SymbolView">
        <View style={styles.preview}>
          <SymbolView
            accessibilityLabel="系统图标"
            fallback={<Text style={styles.fallback}>{fallback}</Text>}
            name={symbol}
            onLayout={({ nativeEvent }) => setLayout(`${nativeEvent.layout.width} × ${nativeEvent.layout.height}`)}
            size={size}
            type={type}
            weight={weight}
            tintColor={tint.trim() || undefined}
            colors={colors.split(',').map(color => color.trim()).filter(Boolean)}
            scale={scale}
            resizeMode={resizeMode}
            animationSpec={animationSpec}
            testID="symbols-preview"
          />
        </View>
        <Cycle
          label="图标"
          value={preset}
          choices={['文件夹', '房屋', '无线网络', '箭头', '占位']}
          onChange={(value) => {
            setPreset(value);
            setHarmonyName('');
          }}
        />
        {String(Platform.OS) === 'harmony' ? <Field label="HarmonyOS 图标名称" placeholder="使用预设名称" value={harmonyName} onChangeText={setHarmonyName} /> : null}
        <Field label="备用文本" value={fallback} onChangeText={setFallback} />
        <Field label="着色（tintColor）" placeholder="使用图标配色" value={tint} onChangeText={setTint} />
        <Field label="调色板（用逗号分隔）" value={colors} onChangeText={setColors} />
        <ActionRow>
          <Cycle label="尺寸" value={size} choices={[32, 64, 88, 112]} onChange={setSize} />
          <Cycle label="字重" value={weight} choices={weights} onChange={setWeight} />
          <Cycle label="渲染模式" value={type} choices={types} onChange={setType} />
        </ActionRow>
        {layout ? <DataRow label="布局尺寸" value={layout} /> : null}
        {Platform.OS === 'ios'
          ? (
              <ActionRow>
                <Cycle label="比例" value={scale} choices={scales} onChange={setScale} />
                <Cycle label="适配方式" value={resizeMode} choices={contentModes} onChange={setResizeMode} />
                <Toggle label="播放动画" value={animate} onChange={setAnimate} />
                <Cycle label="效果" value={effect} choices={['bounce', 'pulse', 'scale']} onChange={setEffect} />
                <Cycle label="方向" value={direction} choices={['up', 'down']} onChange={setDirection} />
                <Toggle label="整枚图标" value={wholeSymbol} onChange={setWholeSymbol} />
                <Toggle label="重复播放" value={repeating} onChange={setRepeating} />
                <Cycle label="播放次数" value={repeatCount} choices={[1, 2, 4]} onChange={setRepeatCount} />
                <Cycle label="播放速度" value={speed} choices={[0.5, 1, 2]} onChange={setSpeed} />
              </ActionRow>
            )
          : null}
      </Panel>
      {Platform.OS === 'android' ? <MaterialSourceDemo /> : null}
    </>
  );
}

function MaterialSourceDemo() {
  const action = useAsyncResult();
  const [name, setName] = useState<AndroidSymbol>('home');
  const [size, setSize] = useState(64);
  const [color, setColor] = useState(palette.signal as string);
  const [source, setSource] = useState<ImageSourcePropType | null>(null);

  return (
    <Panel title="Material 图标图片">
      {source ? <Image source={source} style={{ width: size, height: size }} /> : null}
      <ActionRow>
        <Cycle label="图标" value={name} choices={['home', 'wifi', 'create_new_folder']} onChange={setName} />
        <Cycle label="尺寸" value={size} choices={[24, 48, 64, 88]} onChange={setSize} />
      </ActionRow>
      <Field label="颜色" value={color} onChangeText={setColor} />
      <ActionButton
        disabled={action.state.phase === 'running'}
        label="生成图片"
        onPress={() => void action.run(async () => {
          const image = await unstable_getMaterialSymbolSourceAsync(name, size, color);
          setSource(image);
          return JSON.stringify(image, null, 2);
        })}
      />
      <ResultPanel state={action.state} />
    </Panel>
  );
}

const styles = StyleSheet.create({
  preview: { alignItems: 'center', backgroundColor: palette.surfaceRaised, borderRadius: 12, height: 136, justifyContent: 'center' },
  fallback: { color: palette.muted, fontSize: 13 },
});
