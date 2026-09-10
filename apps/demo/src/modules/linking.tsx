import * as Linking from 'expo-linking';
import { useState } from 'react';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

export function LinkingDemo() {
  const action = useAsyncResult();
  const linkingURL = Linking.useLinkingURL();
  const [url, setUrl] = useState(linkingURL || 'expoharmonydemo://module/linking');

  return (
    <>
      <Panel eyebrow="原生生命周期" title="当前链接 URL">
        <DataRow label="getLinkingURL()" value={Linking.getLinkingURL() || 'null'} />
        <DataRow label="useLinkingURL()" value={linkingURL || 'null'} />
        <ActionButton
          label="清除缓存的初始 URL"
          onPress={() => void action.run(async () => {
            const initialURL = await Linking.getInitialURL();
            Linking.clearInitialURL();
            const next = Linking.getLinkingURL();
            if (next !== null) throw new Error(`清除后应为 null，实际为 ${next}。`);
            const retainedInitialURL = await Linking.getInitialURL();
            if (retainedInitialURL !== initialURL) {
              throw new Error(
                `React Native 初始 URL 由 ${String(initialURL)} 变为 ${String(retainedInitialURL)}。`
              );
            }
            return 'Expo 缓存已清除，React Native 冷启动 URL 保持不变。';
          })}
          testID="linking-clear-initial-url"
          tone="secondary"
        />
        <ResultPanel state={action.state} />
      </Panel>

      <Panel eyebrow="纯 URL API" title="解析任意深链接">
        <Field label="URL" onChangeText={setUrl} value={url} />
        <ActionRow>
          <ActionButton
            disabled={!url.trim()}
            label="解析 URL"
            onPress={() => void action.run(() => json(Linking.parse(url.trim())))}
          />
          <ActionButton
            disabled={!url.trim() || action.state.phase === 'running'}
            label="检测能否打开"
            onPress={() => void action.run(async () => `canOpenURL() → ${await Linking.canOpenURL(url.trim())}`)}
            tone="secondary"
          />
          <ActionButton
            disabled={!url.trim() || action.state.phase === 'running'}
            label="打开 URL"
            onPress={() => void action.run(async () => `openURL() → ${await Linking.openURL(url.trim())}`)}
            tone="secondary"
          />
        </ActionRow>
      </Panel>
    </>
  );
}
