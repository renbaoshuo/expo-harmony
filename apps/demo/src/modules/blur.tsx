import { BlurView, type BlurTint } from 'expo-blur';
import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { ActionButton, ActionRow, DataRow, Note, Panel } from '../ui';

const TINTS: readonly BlurTint[] = [
  'default',
  'dark',
  'systemMaterialLight',
  'prominent',
];

export function BlurDemo() {
  const [tintIndex, setTintIndex] = useState(0);
  const [intensity, setIntensity] = useState(55);
  const tint = TINTS[tintIndex] ?? 'default';

  return (
    <>
      <Panel eyebrow="原生视图" title="渲染由 ArkUI 支持的材质模糊">
        <View style={styles.blurScene}>
          <View style={[styles.blurOrb, styles.blurOrbBlue]} />
          <View style={[styles.blurOrb, styles.blurOrbOrange]} />
          <Text style={styles.blurBackdrop}>HARMONY</Text>
          <BlurView intensity={intensity} style={styles.blurGlass} tint={tint}>
            <Text style={styles.blurLabel}>EXPO BLUR</Text>
            <Text style={styles.blurTitle}>材质模糊背景</Text>
            <Text style={styles.blurValue}>{tint} · {intensity}</Text>
          </BlurView>
        </View>
        <Note>卡片后方的文字与色块应仍然可见，但能看出明显的柔化效果。</Note>
      </Panel>

      <Panel eyebrow="动态属性" title="无需重新挂载即可更新色调与强度">
        <DataRow label="tint" value={tint} />
        <DataRow label="intensity" value={String(intensity)} />
        <ActionRow>
          <ActionButton
            label="下一个色调"
            onPress={() => setTintIndex(value => (value + 1) % TINTS.length)}
            testID="blur-next-tint"
          />
          <ActionButton
            label="强度 +25"
            onPress={() => setIntensity(value => value >= 100 ? 0 : value + 25)}
            testID="blur-next-intensity"
            tone="secondary"
          />
        </ActionRow>
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  blurBackdrop: { color: '#FFCC00', fontSize: 38, fontWeight: '900', left: 18, letterSpacing: -2, position: 'absolute', top: 26 },
  blurGlass: { borderColor: 'rgba(255,255,255,0.36)', borderRadius: 18, borderWidth: 1, bottom: 22, gap: 7, left: 18, overflow: 'hidden', padding: 20, position: 'absolute', right: 18 },
  blurLabel: { color: '#FFCC00', fontSize: 10, fontWeight: '800', letterSpacing: 1.2 },
  blurOrb: { borderRadius: 90, height: 170, position: 'absolute', width: 170 },
  blurOrbBlue: { backgroundColor: '#32ADE6', bottom: -38, right: -36 },
  blurOrbOrange: { backgroundColor: '#FF6B35', right: 12, top: 44 },
  blurScene: { backgroundColor: '#263643', borderRadius: 14, height: 300, overflow: 'hidden' },
  blurTitle: { color: '#FFFFFF', fontSize: 24, fontWeight: '800' },
  blurValue: { color: '#F5F7FA', fontFamily: 'monospace', fontSize: 11 },
});
