import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import * as Battery from 'expo-battery';

type Snapshot = Battery.PowerState & { available: boolean; optimized: boolean };
const stateNames: Record<Battery.BatteryState, string> = {
  [Battery.BatteryState.UNKNOWN]: '未知',
  [Battery.BatteryState.UNPLUGGED]: '使用电池',
  [Battery.BatteryState.CHARGING]: '充电中',
  [Battery.BatteryState.FULL]: '已充满',
};

export default function App() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);
  const [events, setEvents] = useState(0);

  useEffect(() => {
    let active = true;
    const pending: Partial<Battery.PowerState> = {};
    const update = (value: Partial<Battery.PowerState>) => {
      if (!active) return;
      Object.assign(pending, value);
      setSnapshot(previous => previous ? { ...previous, ...value } : previous);
      setEvents(previous => previous + 1);
      console.info('[bare-battery] event', JSON.stringify(value));
    };
    const subscriptions = [
      Battery.addBatteryLevelListener(update),
      Battery.addBatteryStateListener(update),
      Battery.addLowPowerModeListener(update),
    ];
    setError(null);
    Promise.all([
      Battery.getPowerStateAsync(),
      Battery.isAvailableAsync(),
      Battery.isBatteryOptimizationEnabledAsync(),
    ]).then(([power, available, optimized]) => {
      if (!active) return;
      const next = { ...power, ...pending, available, optimized };
      setSnapshot(next);
      console.info('[bare-battery] snapshot', JSON.stringify(next));
    }).catch((reason) => {
      if (active) setError(String(reason));
    });
    return () => {
      active = false;
      subscriptions.forEach(subscription => subscription.remove());
    };
  }, [revision]);

  const percent = snapshot && snapshot.batteryLevel >= 0 ? Math.round(snapshot.batteryLevel * 100) : null;
  return (
    <ScrollView contentContainerStyle={styles.page}>
      <Text style={styles.eyebrow}>EXPO MODULES · HARMONYOS</Text>
      <Text style={styles.title}>电池演示</Text>
      <Text style={styles.subtitle}>一个纯 React Native 应用，由 expo-battery 提供电池数据。</Text>
      <View style={styles.battery}>
        <View style={[styles.fill, { width: `${percent ?? 0}%` }]} />
        <Text style={styles.percentage}>{percent === null ? '—' : `${percent}%`}</Text>
      </View>
      {snapshot
        ? (
            <View style={styles.details}>
              <Row label="电源状态" value={stateNames[snapshot.batteryState]} />
              <Row label="低电量模式" value={snapshot.lowPowerMode ? '开' : '关'} />
              <Row label="电池 API" value={snapshot.available ? '可用' : '不可用'} />
              <Row label="电池优化" value={snapshot.optimized ? '开' : '关'} />
              <Row label="已接收事件" value={String(events)} />
            </View>
          )
        : error ? null : <ActivityIndicator accessibilityLabel="正在读取电池信息" color="#20643a" />}
      {error ? <Text accessibilityRole="alert" style={styles.error}>{error}</Text> : null}
      <Pressable accessibilityRole="button" onPress={() => setRevision(value => value + 1)} style={({ pressed }) => [styles.button, pressed && styles.pressed]}>
        <Text style={styles.buttonText}>重新读取电池状态</Text>
      </Pressable>
      <Text style={styles.footer}>原生工程手动维护，不使用 prebuild 或 CNG。</Text>
    </ScrollView>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.value}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  page: { flexGrow: 1, backgroundColor: '#f5f6ef', paddingHorizontal: 28, paddingTop: 76, paddingBottom: 40, gap: 22 },
  eyebrow: { color: '#52604f', fontSize: 11, letterSpacing: 1.5, fontWeight: '600' },
  title: { color: '#172b1d', fontSize: 38, fontWeight: '700' },
  subtitle: { color: '#65715f', fontSize: 16, lineHeight: 24 },
  battery: { height: 150, marginVertical: 10, borderWidth: 2, borderColor: '#20643a', borderRadius: 22, overflow: 'hidden', justifyContent: 'center', alignItems: 'center' },
  fill: { position: 'absolute', left: 0, top: 0, bottom: 0, backgroundColor: '#c2df9a' },
  percentage: { color: '#172b1d', fontSize: 64, fontWeight: '600', fontVariant: ['tabular-nums'] },
  details: { borderTopWidth: 1, borderColor: '#d7dece' },
  row: { flexDirection: 'row', justifyContent: 'space-between', gap: 12, paddingVertical: 15, borderBottomWidth: 1, borderColor: '#d7dece' },
  label: { color: '#65715f', fontSize: 14 },
  value: { color: '#172b1d', fontSize: 14, fontWeight: '600' },
  error: { color: '#a52824', fontSize: 14, lineHeight: 22 },
  button: { backgroundColor: '#20643a', padding: 18, alignItems: 'center', borderRadius: 14 },
  pressed: { opacity: 0.75 },
  buttonText: { color: '#ffffff', fontWeight: '600', fontSize: 16 },
  footer: { color: '#65715f', fontSize: 12, lineHeight: 20 },
});
