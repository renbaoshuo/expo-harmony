/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { BlurTargetView, BlurView, type BlurMethod, type BlurTint } from 'expo-blur';
import { useRef, useState } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
import { ActionRow, Panel } from '../ui';
import { Cycle, Toggle } from './visual-controls';

const tints: BlurTint[] = [
  'default', 'light', 'dark', 'extraLight', 'regular', 'prominent',
  'systemUltraThinMaterial', 'systemThinMaterial', 'systemMaterial', 'systemThickMaterial', 'systemChromeMaterial',
  'systemUltraThinMaterialLight', 'systemThinMaterialLight', 'systemMaterialLight', 'systemThickMaterialLight', 'systemChromeMaterialLight',
  'systemUltraThinMaterialDark', 'systemThinMaterialDark', 'systemMaterialDark', 'systemThickMaterialDark', 'systemChromeMaterialDark',
];
const methods: BlurMethod[] = ['none', 'dimezisBlurView', 'dimezisBlurViewSdk31Plus'];

export function BlurDemo() {
  const target = useRef<View>(null);
  const [tint, setTint] = useState<BlurTint>('default');
  const [intensity, setIntensity] = useState(50);
  const [method, setMethod] = useState<BlurMethod>('dimezisBlurView');
  const [reduction, setReduction] = useState(4);
  const [useTarget, setUseTarget] = useState(true);
  const [experimental, setExperimental] = useState(false);

  return (
    <Panel title="BlurView">
      <View style={styles.scene}>
        <BlurTargetView ref={target} style={StyleSheet.absoluteFill}>
          <View style={[styles.orb, styles.blue]} />
          <View style={[styles.orb, styles.orange]} />
          <Text style={styles.backdrop}>HARMONY</Text>
        </BlurTargetView>
        <BlurView
          blurTarget={useTarget ? target : undefined}
          blurMethod={experimental ? undefined : method}
          experimentalBlurMethod={experimental ? method : undefined}
          blurReductionFactor={reduction}
          intensity={intensity}
          style={styles.glass}
          tint={tint}
          testID="blur-preview"
        >
          <Text style={styles.title}>材质模糊</Text>
        </BlurView>
      </View>
      <ActionRow>
        <Cycle label="色调" value={tint} choices={tints} onChange={setTint} />
        <Cycle label="强度" value={intensity} choices={[0, 25, 50, 75, 100]} onChange={setIntensity} />
      </ActionRow>
      {Platform.OS === 'android'
        ? (
            <ActionRow>
              <Cycle label="模糊方式" value={method} choices={methods} onChange={setMethod} />
              <Cycle label="模糊衰减系数" value={reduction} choices={[1, 2, 4, 8]} onChange={setReduction} />
              <Toggle label="指定目标视图" value={useTarget} onChange={setUseTarget} />
              <Toggle label="experimentalBlurMethod" value={experimental} onChange={setExperimental} />
            </ActionRow>
          )
        : null}
    </Panel>
  );
}

const styles = StyleSheet.create({
  backdrop: { color: '#FFCC00', fontSize: 46, fontWeight: '900', left: 18, letterSpacing: -2, position: 'absolute', top: 82 },
  glass: { borderColor: 'rgba(255,255,255,0.36)', borderRadius: 18, borderWidth: 1, bottom: 22, left: 18, minHeight: 128, overflow: 'hidden', padding: 20, position: 'absolute', right: 18, justifyContent: 'flex-end' },
  orb: { borderRadius: 90, height: 170, position: 'absolute', width: 170 },
  blue: { backgroundColor: '#32ADE6', bottom: -38, right: -36 },
  orange: { backgroundColor: '#FF6B35', right: 12, top: 44 },
  scene: { backgroundColor: '#263643', borderRadius: 14, height: 230, overflow: 'hidden' },
  title: { color: '#FFFFFF', fontSize: 24, fontWeight: '800' },
});
