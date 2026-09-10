import { activateKeepAwakeAsync, deactivateKeepAwake, isAvailableAsync, useKeepAwake } from 'expo-keep-awake';
import { useEffect, useState } from 'react';
import { StyleSheet, Switch, Text, View } from 'react-native';
import { palette } from '../theme';
import { ActionButton, DataRow, Panel, ResultPanel, Tag, useAsyncResult } from '../ui';

const MANUAL_KEEP_AWAKE_TAG = 'expo-harmony-demo-manual';

function HookKeepAwakeProbe() {
  useKeepAwake('expo-harmony-demo-hook');
  return <Tag tone="success">Hook 已挂载</Tag>;
}

export function KeepAwakeDemo() {
  const action = useAsyncResult();
  const [manualActive, setManualActive] = useState(false);
  const [hookActive, setHookActive] = useState(false);

  useEffect(() => () => {
    void deactivateKeepAwake(MANUAL_KEEP_AWAKE_TAG);
  }, []);

  const toggleManual = () => action.run(async () => {
    if (manualActive) {
      await deactivateKeepAwake(MANUAL_KEEP_AWAKE_TAG);
      setManualActive(false);
      return '手动标签已释放，屏幕可以正常休眠。';
    }
    await activateKeepAwakeAsync(MANUAL_KEEP_AWAKE_TAG);
    setManualActive(true);
    return '手动标签已生效。请将应用切到后台再切回，验证常亮状态是否恢复。';
  });

  return (
    <>
      <Panel eyebrow="标签常亮锁" title="手动生命周期">
        <DataRow label="本地 UI 状态" value={<Tag tone={manualActive ? 'success' : 'neutral'}>{manualActive ? '生效中' : '已释放'}</Tag>} />
        <ActionButton
          disabled={action.state.phase === 'running'}
          label={manualActive ? '释放标签' : '激活标签'}
          onPress={() => void toggleManual()}
          tone={manualActive ? 'secondary' : 'primary'}
        />
        <ResultPanel state={action.state} />
      </Panel>

      <Panel eyebrow="React Hook" title="随挂载生效的常亮锁">
        <View style={styles.switchRow}>
          <View style={styles.switchCopy}>
            <Text style={styles.switchTitle}>useKeepAwake</Text>
            <Text style={styles.switchCaption}>卸载探针时会自动释放其独立标签。</Text>
          </View>
          <Switch
            onValueChange={setHookActive}
            thumbColor={hookActive ? palette.signal : palette.muted}
            trackColor={{ false: palette.lineStrong, true: palette.signalSoft }}
            value={hookActive}
          />
        </View>
        {hookActive ? <HookKeepAwakeProbe /> : <Tag>Hook 已卸载</Tag>}
      </Panel>

      <Panel eyebrow="能力探测" title="官方可用性 API">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="检查可用性"
          onPress={() => void action.run(async () => `isAvailableAsync() → ${await isAvailableAsync()}`)}
        />
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  switchRow: { alignItems: 'center', flexDirection: 'row', gap: 16, justifyContent: 'space-between' },
  switchCopy: { flex: 1, gap: 4 },
  switchTitle: { color: palette.text, fontSize: 16, fontWeight: '700' },
  switchCaption: { color: palette.muted, fontSize: 12, lineHeight: 18 },
});
