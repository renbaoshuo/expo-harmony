import { LinearGradient } from 'expo-linear-gradient';
import { useState } from 'react';
import { StyleSheet, Text } from 'react-native';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Panel } from '../ui';

export function LinearGradientDemo() {
  const [direction, setDirection] = useState<'horizontal' | 'vertical'>('horizontal');
  const start = { x: 0, y: 0 } as const;
  const end = direction === 'horizontal' ? { x: 1, y: 0 } as const : { x: 0, y: 1 } as const;

  return (
    <>
      <Panel eyebrow="多色渐变" title="精确的对角端点">
        <LinearGradient
          colors={['#FFB000', '#72D8FF', '#7B61FF']}
          end={{ x: 1, y: 1 }}
          locations={[0, 0.45, 1]}
          start={{ x: 0, y: 0 }}
          style={styles.gradientHero}
          testID="linear-gradient-multi-stop"
        >
          <Text style={styles.gradientEyebrow}>原生画布</Text>
          <Text style={styles.gradientTitle}>三种颜色，一个原生视图。</Text>
          <Text style={styles.gradientCopy}>
            子内容浮于渐变之上，原生图层始终跟随视图边界。
          </Text>
        </LinearGradient>
      </Panel>

      <Panel eyebrow="动态属性" title="切换渐变方向">
        <LinearGradient
          colors={['#FF7064', '#FFB000', '#51D88A']}
          end={end}
          locations={[0, 0.52, 1]}
          start={start}
          style={styles.gradientDirection}
          testID="linear-gradient-direction"
        >
          <Text style={styles.gradientDirectionText}>{direction === 'horizontal' ? '水平' : '垂直'}</Text>
        </LinearGradient>
        <DataRow label="起点 → 终点" value={direction === 'horizontal' ? '(0, 0) → (1, 0)' : '(0, 0) → (0, 1)'} />
        <ActionRow>
          <ActionButton label="水平" onPress={() => setDirection('horizontal')} tone="secondary" />
          <ActionButton label="垂直" onPress={() => setDirection('vertical')} tone="secondary" />
        </ActionRow>
      </Panel>

      <Panel eyebrow="断点与裁剪" title="硬过渡与单独圆角">
        <LinearGradient
          colors={['#111920', '#111920', '#72D8FF', '#7B61FF']}
          end={{ x: 1, y: 0 }}
          locations={[0, 0.5, 0.5, 1]}
          start={{ x: 0, y: 0 }}
          style={styles.gradientHardStop}
          testID="linear-gradient-hard-stop"
        >
          <Text style={styles.gradientHardStopText}>50% 硬过渡</Text>
        </LinearGradient>
      </Panel>

      <Panel eyebrow="边界情况" title="偏移断点与视图外坐标">
        <LinearGradient
          colors={['#FF7064', '#FFB000', '#72D8FF']}
          end={{ x: 1, y: 0 }}
          locations={[0.2, 0.65, 1]}
          start={{ x: 0, y: 0 }}
          style={styles.gradientPartial}
          testID="linear-gradient-partial-locations"
        >
          <Text style={styles.gradientEdgeText}>三个颜色对应 20% / 65% / 100%</Text>
        </LinearGradient>
        <LinearGradient
          colors={['#FF7064', '#51D88A']}
          end={{ x: 1.5, y: 0.5 }}
          start={{ x: -0.5, y: 0.5 }}
          style={styles.gradientDegenerate}
          testID="linear-gradient-degenerate"
        >
          <Text style={styles.gradientEdgeText}>渐变轴可延伸到视图边界之外</Text>
        </LinearGradient>
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  gradientHero: { borderRadius: 18, gap: 10, minHeight: 210, overflow: 'hidden', padding: 22, justifyContent: 'flex-end' },
  gradientEyebrow: { color: '#111920', fontFamily: 'monospace', fontSize: 10, fontWeight: '800', letterSpacing: 1.8 },
  gradientTitle: { color: '#111920', fontSize: 28, fontWeight: '800', letterSpacing: -0.8, lineHeight: 31, maxWidth: 280 },
  gradientCopy: { color: '#243039', fontSize: 12, fontWeight: '600', lineHeight: 18, maxWidth: 300 },
  gradientDirection: { alignItems: 'center', borderRadius: 12, height: 124, justifyContent: 'center', overflow: 'hidden' },
  gradientDirectionText: { color: '#111920', fontFamily: 'monospace', fontSize: 13, fontWeight: '800', letterSpacing: 2 },
  gradientHardStop: { borderBottomRightRadius: 24, borderTopLeftRadius: 24, height: 92, justifyContent: 'center', overflow: 'hidden', paddingHorizontal: 18 },
  gradientHardStopText: { color: palette.text, fontFamily: 'monospace', fontSize: 11, fontWeight: '800', letterSpacing: 1.4, textAlign: 'center' },
  gradientPartial: { borderRadius: 12, height: 88, justifyContent: 'center', overflow: 'hidden', paddingHorizontal: 18 },
  gradientDegenerate: { borderRadius: 12, height: 72, justifyContent: 'center', overflow: 'hidden', paddingHorizontal: 18 },
  gradientEdgeText: { color: '#111920', fontFamily: 'monospace', fontSize: 10, fontWeight: '800', letterSpacing: 1.2, textAlign: 'center' },
});
