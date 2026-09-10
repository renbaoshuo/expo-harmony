import { Asset } from 'expo-asset';
import { useState } from 'react';
import { antDesignFontAsset } from '../fixtures';
import { ActionButton, Field, Note, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

export function AssetDemo() {
  const bundled = useAsyncResult();
  const remote = useAsyncResult();
  const [url, setUrl] = useState('https://example.com');

  return (
    <>
      <Panel eyebrow="内置资源" title="解析内置的 AntDesign 字体">
        <Note>这里使用与 Font 载体在运行时注册时相同的静态 Metro 资源。</Note>
        <ActionButton
          disabled={bundled.state.phase === 'running'}
          label="解析内置资源"
          onPress={() => void bundled.run(async () => {
            const asset = Asset.fromModule(antDesignFontAsset());
            await asset.downloadAsync();
            return json({
              downloaded: asset.downloaded,
              hash: asset.hash,
              localUri: asset.localUri,
              type: asset.type,
              uri: asset.uri,
            });
          })}
        />
        <ResultPanel state={bundled.state} />
      </Panel>

      <Panel eyebrow="远程缓存" title="下载任意 URL">
        <Field label="资源 URL" onChangeText={setUrl} value={url} />
        <ActionButton
          disabled={!url.trim() || remote.state.phase === 'running'}
          label="下载到资源缓存"
          onPress={() => void remote.run(async () => {
            const asset = Asset.fromURI(url.trim());
            await asset.downloadAsync();
            return json({ downloaded: asset.downloaded, localUri: asset.localUri, type: asset.type, uri: asset.uri });
          })}
        />
        <ResultPanel state={remote.state} />
      </Panel>
    </>
  );
}
