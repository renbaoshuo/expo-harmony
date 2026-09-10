import * as Network from 'expo-network';
import { useEffect, useState } from 'react';
import { StyleSheet, Text } from 'react-native';
import { palette } from '../theme';
import { ActionButton, DataRow, Note, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

export function NetworkDemo() {
  const action = useAsyncResult();
  const state = Network.useNetworkState();
  const [events, setEvents] = useState(0);
  const [lastEvent, setLastEvent] = useState<Network.NetworkState>();

  useEffect(() => {
    const subscription = Network.addNetworkStateListener((event) => {
      setEvents(value => value + 1);
      setLastEvent(event);
    });

    return () => subscription.remove();
  }, []);

  const inspect = () => action.run(async () => {
    const [current, ipAddress, airplaneMode] = await Promise.all([
      Network.getNetworkStateAsync(),
      Network.getIpAddressAsync(),
      Network.isAirplaneModeEnabledAsync(),
    ]);

    return json({ airplaneMode, ipAddress, state: current });
  });

  return (
    <>
      <Panel eyebrow="实时状态" title="观察 Harmony 网络连接">
        <DataRow label="连接类型" value={state.type ?? '加载中'} />
        <DataRow label="已连接" value={String(state.isConnected ?? '未知')} />
        <DataRow label="互联网可达" value={String(state.isInternetReachable ?? '未知')} />
        <DataRow label="状态事件数" value={String(events)} />
        {lastEvent ? <Text selectable style={styles.compactCode}>{json(lastEvent)}</Text> : null}
      </Panel>

      <Panel eyebrow="原生方法" title="读取当前网络快照">
        <Note>返回当前承载网络、本地 IPv4 地址与系统飞行模式设置。</Note>
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取网络状态"
          onPress={() => void inspect()}
          testID="network-read-state"
        />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  compactCode: { backgroundColor: palette.canvas, borderRadius: 4, color: palette.muted, fontFamily: 'monospace', fontSize: 10, lineHeight: 16, padding: 12 },
});
