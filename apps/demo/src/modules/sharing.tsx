/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import { useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const ANCHOR_LABELS = { x: '横坐标', y: '纵坐标', width: '宽度', height: '高度' };
const ANCHOR_KEYS = ['x', 'y', 'width', 'height'] as const;

export function SharingDemo() {
  const action = useAsyncResult();
  const [uri, setUri] = useState(Platform.OS === 'web' ? 'https://example.com/' : '');
  const [mimeType, setMimeType] = useState('text/plain');
  const [uti, setUti] = useState('');
  const [title, setTitle] = useState('');
  const [anchor, setAnchor] = useState({ x: '', y: '', width: '', height: '' });
  const harmony = String(Platform.OS) === 'harmony';
  const ios = Platform.OS === 'ios';
  const web = Platform.OS === 'web';
  const busy = action.state.phase === 'running';

  const share = () => action.run(async () => {
    const options: Sharing.SharingOptions = {
      mimeType: harmony || Platform.OS === 'android' ? mimeType || undefined : undefined,
      UTI: ios ? uti || undefined : undefined,
      dialogTitle: Platform.OS === 'android' ? title || undefined : undefined,
    };

    if ((ios || harmony) && ANCHOR_KEYS.some(key => anchor[key].trim())) {
      options.anchor = {
        x: anchor.x.trim() ? Number(anchor.x) : undefined,
        y: anchor.y.trim() ? Number(anchor.y) : undefined,
        width: anchor.width.trim() ? Number(anchor.width) : undefined,
        height: anchor.height.trim() ? Number(anchor.height) : undefined,
      };
    }

    let fileUri = uri.trim();
    if (!fileUri && !web) {
      const file = new File(Paths.cache, 'expo-sharing-demo.txt');
      file.create({ overwrite: true });
      file.write('周六上午九点在公园门口集合。');
      fileUri = file.uri;
      setUri(fileUri);
    }

    await Sharing.shareAsync(fileUri, options);
    return '分享面板已关闭';
  });

  return (
    <>
      <Panel title={web ? '分享链接' : '分享文件'}>
        <Field label={web ? '链接 URL' : '本地文件 URI'} onChangeText={setUri} value={uri} />
        {harmony || Platform.OS === 'android' ? <Field label="MIME 类型" onChangeText={setMimeType} value={mimeType} /> : null}
        {ios ? <Field label="统一类型标识符（UTI）" onChangeText={setUti} value={uti} /> : null}
        {Platform.OS === 'android' ? <Field label="面板标题" onChangeText={setTitle} value={title} /> : null}
        {ios || harmony
          ? ANCHOR_KEYS.map(key => (
              <Field key={key} label={`面板锚点${ANCHOR_LABELS[key]}`} keyboardType="decimal-pad" value={anchor[key]} onChangeText={value => setAnchor(current => ({ ...current, [key]: value }))} />
            ))
          : null}
        <ActionRow>
          <ActionButton disabled={busy || (web && !uri.trim())} label={uri.trim() ? '打开分享面板' : '分享示例文件'} onPress={() => void share()} testID="sharing-open-panel" />
          <ActionButton disabled={busy} label="查询分享是否可用" onPress={() => void action.run(async () => String(await Sharing.isAvailableAsync()))} testID="sharing-check-availability" tone="secondary" />
        </ActionRow>
        <ResultPanel state={action.state} />
      </Panel>

      {harmony ? <IncomingSharePanel /> : null}
    </>
  );
}

function IncomingSharePanel() {
  const incoming = Sharing.useIncomingShare();
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="接收分享">
      <DataRow label="收到的内容" value={json(incoming.sharedPayloads)} />
      <DataRow label="解析结果" value={incoming.isResolving ? '正在解析' : json(incoming.resolvedSharedPayloads)} />
      {incoming.error ? <DataRow label="错误" value={incoming.error.message} /> : null}
      <ActionRow>
        <ActionButton label="刷新收到的内容" onPress={incoming.refreshSharePayloads} testID="sharing-refresh-payloads" />
        <ActionButton
          label="清空并更新页面"
          onPress={() => void action.run(() => {
            incoming.clearSharedPayloads();
            return '已清空';
          })}
          testID="sharing-clear-payloads"
          tone="secondary"
        />
      </ActionRow>
      <ActionRow>
        <ActionButton disabled={busy} label="读取原始内容" onPress={() => void action.run(() => json(Sharing.getSharedPayloads()))} tone="secondary" />
        <ActionButton disabled={busy} label="读取解析结果" onPress={() => void action.run(async () => json(await Sharing.getResolvedSharedPayloadsAsync()))} tone="secondary" />
        <ActionButton
          disabled={busy}
          label="清空收到的内容"
          onPress={() => void action.run(() => {
            Sharing.clearSharedPayloads();
            return '已清空';
          })}
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}
