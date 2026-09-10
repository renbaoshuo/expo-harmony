import * as Battery from 'expo-battery';
import { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text } from 'react-native';
import { palette } from '../theme';
import { ActionButton, DataRow, Note, Panel, ResultPanel, Tag, useAsyncResult } from '../ui';
import { json } from '../format';

const BATTERY_STATE_LABELS: Record<Battery.BatteryState, string> = {
  [Battery.BatteryState.UNKNOWN]: '未知',
  [Battery.BatteryState.UNPLUGGED]: '未充电',
  [Battery.BatteryState.CHARGING]: '充电中',
  [Battery.BatteryState.FULL]: '已充满',
};

function batteryLevelLabel(level: number): string {
  return level < 0 ? '未知' : `${Math.round(level * 100)}%`;
}

function isBatteryLevel(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= -1 && value <= 1;
}

function isBatteryState(value: unknown): value is Battery.BatteryState {
  return typeof value === 'number' && Object.prototype.hasOwnProperty.call(BATTERY_STATE_LABELS, value);
}

export function BatteryDemo() {
  const powerState = Battery.usePowerState();
  const action = useAsyncResult();
  const [events, setEvents] = useState({ level: 0, mode: 0, state: 0 });
  const [payloads, setPayloads] = useState({ level: '暂无', mode: '暂无', state: '暂无' });
  const [invalidEvent, setInvalidEvent] = useState<string | null>(null);
  const [removal, setRemoval] = useState({ calls: 0, phase: 'idle' });
  const removalSubscription = useRef<Battery.Subscription | null>(null);

  useEffect(() => {
    const subscriptions = [
      Battery.addBatteryLevelListener((event) => {
        if (!isBatteryLevel(event?.batteryLevel)) {
          setInvalidEvent(`无效的电量事件：${json(event)}`);
        } else {
          setPayloads(value => ({ ...value, level: String(event.batteryLevel) }));
        }

        setEvents(value => ({ ...value, level: value.level + 1 }));
      }),
      Battery.addBatteryStateListener((event) => {
        if (!isBatteryState(event?.batteryState)) {
          setInvalidEvent(`无效的电池状态事件：${json(event)}`);
        } else {
          setPayloads(value => ({ ...value, state: String(event.batteryState) }));
        }

        setEvents(value => ({ ...value, state: value.state + 1 }));
      }),
      Battery.addLowPowerModeListener((event) => {
        if (typeof event?.lowPowerMode !== 'boolean') {
          setInvalidEvent(`无效的低电量模式事件：${json(event)}`);
        } else {
          setPayloads(value => ({ ...value, mode: String(event.lowPowerMode) }));
        }

        setEvents(value => ({ ...value, mode: value.mode + 1 }));
      }),
    ];

    return () => {
      subscriptions.forEach(subscription => subscription.remove());
      removalSubscription.current?.remove();
      removalSubscription.current = null;
    };
  }, []);

  const armRemovalProbe = () => {
    removalSubscription.current?.remove();
    removalSubscription.current = null;
    setRemoval({ calls: 0, phase: '等待首个电量事件' });

    let calls = 0;
    const subscription = Battery.addBatteryLevelListener((event) => {
      calls += 1;

      if (!isBatteryLevel(event?.batteryLevel)) {
        setInvalidEvent(`无效的移除探针事件：${json(event)}`);
      }

      setRemoval({
        calls,
        phase: calls === 1 ? '首个事件后已移除' : '失败：回调被重复触发',
      });

      if (calls === 1) {
        subscription.remove();
        if (removalSubscription.current === subscription) removalSubscription.current = null;
      }
    });

    removalSubscription.current = subscription;
  };

  const inspect = () => action.run(async () => {
    const [available, current, optimized] = await Promise.all([
      Battery.isAvailableAsync(),
      Battery.getPowerStateAsync(),
      Battery.isBatteryOptimizationEnabledAsync(),
    ]);

    return json({ available, batteryOptimization: optimized, ...current });
  });

  return (
    <>
      <Panel eyebrow="实时 Hook" title="观察 Harmony 电源状态">
        <DataRow label="电量" value={batteryLevelLabel(powerState.batteryLevel)} />
        <DataRow
          label="电池状态"
          value={`${BATTERY_STATE_LABELS[powerState.batteryState]} (${String(powerState.batteryState)})`}
        />
        <DataRow label="低电量模式" value={String(powerState.lowPowerMode)} />
      </Panel>

      <Panel eyebrow="原生事件" title="跟踪 Expo Battery 的全部公开事件">
        <DataRow label="电量事件数" value={String(events.level)} />
        <DataRow label="状态事件数" value={String(events.state)} />
        <DataRow label="低电量模式事件数" value={String(events.mode)} />
        <DataRow label="最近电量事件值" value={payloads.level} />
        <DataRow label="最近状态事件值" value={payloads.state} />
        <DataRow label="最近模式事件值" value={payloads.mode} />
        <DataRow
          label="事件数据契约"
          value={<Tag tone={invalidEvent === null ? 'success' : 'danger'}>{invalidEvent ?? '有效'}</Tag>}
        />
        <Note>
          请在本页面停留期间修改模拟器的电量或充电状态。Hook 数值与对应计数器应即时更新，无需重新进入页面。
        </Note>
        <Text selectable style={styles.compactCode}>
          {'Emulator -instance "<name>" -battery 37\nEmulator -instance "<name>" -batteryStatus 1'}
        </Text>
      </Panel>

      <Panel eyebrow="移除契约" title="在首个事件后移除监听器">
        <DataRow label="探针状态" value={removal.phase} />
        <DataRow label="回调次数" value={String(removal.calls)} />
        <ActionButton
          label="启动「首个事件后移除」探针"
          onPress={armRemovalProbe}
          testID="battery-arm-removal-probe"
          tone="secondary"
        />
        <Note>
          启动探针后，连续修改两次模拟器电量。回调次数应达到一次，且第二次修改后仍保持一次。
        </Note>
      </Panel>

      <Panel eyebrow="原生方法" title="读取一致的电源快照">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="读取电池状态"
          onPress={() => void inspect()}
          testID="battery-read-state"
        />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  compactCode: { backgroundColor: palette.canvas, borderRadius: 4, color: palette.muted, fontFamily: 'monospace', fontSize: 10, lineHeight: 16, padding: 12 },
});
