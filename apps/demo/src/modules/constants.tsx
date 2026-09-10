import Constants from 'expo-constants';
import { StyleSheet, Text } from 'react-native';
import { palette } from '../theme';
import { ActionButton, DataRow, Panel, ResultPanel, useAsyncResult } from '../ui';

type HarmonyPlatformConstants = {
  apiVersion?: number;
  bundleName?: string;
  deviceType?: string;
  osFullName?: string;
  versionCode?: number;
  versionName?: string;
};

export function ConstantsDemo() {
  const userAgent = useAsyncResult();
  const harmony = (Constants.platform as { harmony?: HarmonyPlatformConstants } | undefined)?.harmony;
  const harmonyConfig = (Constants.expoConfig as typeof Constants.expoConfig & {
    harmony?: { bundleName?: string; targetApiVersion?: number };
  } | null)?.harmony;

  return (
    <>
      <Panel eyebrow="运行时" title="Expo 常量">
        <DataRow label="executionEnvironment" value={Constants.executionEnvironment} />
        <DataRow label="sessionId" value={Constants.sessionId} />
        <DataRow label="deviceName" value={Constants.deviceName || '不可用'} />
        <DataRow label="systemVersion" value={String(Constants.systemVersion ?? '不可用')} />
        <DataRow label="statusBarHeight" value={`${Constants.statusBarHeight}px`} />
        <DataRow label="debugMode" value={String(Constants.debugMode)} />
      </Panel>

      <Panel eyebrow="HARMONY 清单" title="原生与内嵌信息">
        <DataRow label="bundleName" value={harmony?.bundleName || harmonyConfig?.bundleName || '缺失'} />
        <DataRow label="version" value={harmony ? `${harmony.versionName ?? '?'} (${harmony.versionCode ?? '?'})` : '缺失'} />
        <DataRow label="设备 / API" value={harmony ? `${harmony.deviceType ?? '?'} · API ${harmony.apiVersion ?? '?'}` : '缺失'} />
        <DataRow label="系统全名" value={harmony?.osFullName || '不可用'} />
        <DataRow label="系统字体数量" value={String(Constants.systemFonts.length)} />
        <Text selectable style={styles.compactCode}>{Constants.systemFonts.slice(0, 12).join('\n') || '未上报系统字体。'}</Text>
      </Panel>

      <Panel eyebrow="平台服务" title="WebView 用户代理">
        <ActionButton
          disabled={userAgent.state.phase === 'running'}
          label="读取 User Agent"
          onPress={() => void userAgent.run(async () => (await Constants.getWebViewUserAgentAsync()) || '平台返回了 null。')}
        />
        <ResultPanel state={userAgent.state} />
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  compactCode: { backgroundColor: palette.canvas, borderRadius: 4, color: palette.muted, fontFamily: 'monospace', fontSize: 10, lineHeight: 16, padding: 12 },
});
