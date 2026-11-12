/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as DocumentPicker from 'expo-document-picker';
import { useState } from 'react';
import { Platform, Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function DocumentPickerDemo() {
  const [type, setType] = useState('*/*');
  const [multiple, setMultiple] = useState(false);
  const [copy, setCopy] = useState(true);
  const [base64, setBase64] = useState(true);
  const picker = useAsyncResult();
  const busy = picker.state.phase === 'running';
  const isWeb = Platform.OS === 'web';

  const pick = (options?: DocumentPicker.DocumentPickerOptions) => picker.run(async () => {
    const result = await DocumentPicker.getDocumentAsync(options);
    if (result.canceled) return json(result);

    return json({
      ...result,
      assets: result.assets.map(({ base64, file, uri, ...asset }) => ({
        ...asset,
        uri: uri.startsWith('data:') ? `${uri.slice(0, 80)}…` : uri,
        ...(base64 === undefined ? {} : { base64: `${base64.length} 字符` }),
        ...(file === undefined ? {} : { file: file.name }),
      })),
    });
  });

  const types = type.split(',').map(value => value.trim()).filter(Boolean);

  return (
    <Panel title="选择文档">
      <Field label="MIME 类型（多个用逗号分隔）" onChangeText={setType} testID="document-picker-type" value={type} />
      <DataRow label="多选" value={<Switch accessibilityLabel="多选" onValueChange={setMultiple} testID="document-picker-multiple" value={multiple} />} />
      {isWeb
        ? <DataRow label="读取 Base64" value={<Switch accessibilityLabel="读取 Base64" onValueChange={setBase64} value={base64} />} />
        : <DataRow label="复制到缓存" value={<Switch accessibilityLabel="复制到缓存" onValueChange={setCopy} testID="document-picker-copy" value={copy} />} />}
      <ActionRow>
        <ActionButton
          disabled={busy}
          label="选择文档"
          onPress={() => void pick({
            type: types.length === 1 ? types[0] : types,
            multiple,
            ...(isWeb ? { base64 } : { copyToCacheDirectory: copy }),
          })}
          testID="document-picker-select"
        />
        <ActionButton disabled={busy} label="使用默认参数" onPress={() => void pick()} testID="document-picker-default" tone="secondary" />
      </ActionRow>
      <ResultPanel state={picker.state} />
    </Panel>
  );
}
