import { Directory, File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import { StyleSheet, Text } from 'react-native';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Note, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

export function SharingDemo() {
  const action = useAsyncResult();
  const incoming = Sharing.useIncomingShare();

  const shareFile = () => action.run(async () => {
    if (!await Sharing.isAvailableAsync()) throw new Error('Harmony 系统分享不可用。');

    const directory = new Directory(Paths.cache, 'expo-harmony-demo-sharing');
    try {
      directory.create({ idempotent: true, intermediates: true });
      const file = new File(directory, 'expo-sharing-check.txt');
      file.create({ overwrite: true });
      file.write('Expo Sharing on HarmonyOS\n本地文件 · text/plain · 系统分享面板\n');

      await Sharing.shareAsync(file.uri, {
        dialogTitle: 'Expo Harmony 分享检测',
        mimeType: 'text/plain',
      });

      return `系统分享面板已打开并关闭。\n${file.uri}`;
    } finally {
      if (directory.exists) directory.delete();
    }
  });

  const validateURL = () => action.run(async () => {
    try {
      await Sharing.shareAsync('https://example.com/not-a-local-file.txt', { mimeType: 'text/plain' });
    } catch (error) {
      const code = typeof error === 'object' && error !== null && 'code' in error
        ? String((error as { code: unknown }).code)
        : undefined;
      if (code !== 'ERR_SHARING_INVALID_URL') {
        throw new Error(`预期错误码 ERR_SHARING_INVALID_URL，实际为 ${code || '无错误码'}。`);
      }

      return code;
    }

    throw new Error('远程 HTTPS URL 不应进入系统分享面板。');
  });

  return (
    <>
      <Panel eyebrow="接收分享" title="检查发送到本应用的数据">
        <DataRow label="负载数量" value={String(incoming.sharedPayloads.length)} />
        <DataRow label="已解析数量" value={String(incoming.resolvedSharedPayloads.length)} />
        <DataRow label="是否解析中" value={String(incoming.isResolving)} />
        {incoming.error ? <Text selectable style={styles.compactCode}>{incoming.error.message}</Text> : null}
        {incoming.sharedPayloads.length > 0
          ? <Text selectable style={styles.compactCode}>{json(incoming.sharedPayloads)}</Text>
          : <Note>向本应用分享文本、网页链接或文件，即可验证接收链路。</Note>}
        {incoming.resolvedSharedPayloads.length > 0
          ? <Text selectable style={styles.compactCode}>{json(incoming.resolvedSharedPayloads)}</Text>
          : null}
        <ActionRow>
          <ActionButton
            label="刷新分享负载"
            onPress={() => void incoming.refreshSharePayloads()}
            testID="sharing-refresh-payloads"
          />
          <ActionButton
            label="清空分享负载"
            onPress={() => {
              incoming.clearSharedPayloads();
              void incoming.refreshSharePayloads();
            }}
            testID="sharing-clear-payloads"
            tone="secondary"
          />
        </ActionRow>
      </Panel>

      <Panel eyebrow="能力探测" title="Harmony 系统分享">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="检查可用性"
          onPress={() => void action.run(async () => `isAvailableAsync() → ${await Sharing.isAvailableAsync()}`)}
          testID="sharing-check-availability"
        />
      </Panel>

      <Panel eyebrow="本地文件" title="打开系统分享面板">
        <Note>
          会在应用缓存中创建一个临时的 UTF-8 文本文件，以 text/plain 分享，面板关闭后随即删除。
        </Note>
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="分享测试文件"
          onPress={() => void shareFile()}
          testID="sharing-open-panel"
        />
      </Panel>

      <Panel eyebrow="错误契约" title="拒绝非本地 URL">
        <ActionButton
          disabled={action.state.phase === 'running'}
          label="验证 URL 校验"
          onPress={() => void validateURL()}
          testID="sharing-invalid-url"
          tone="secondary"
        />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  compactCode: { backgroundColor: palette.canvas, borderRadius: 4, color: palette.muted, fontFamily: 'monospace', fontSize: 10, lineHeight: 16, padding: 12 },
});
