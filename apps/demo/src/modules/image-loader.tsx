/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset } from 'expo-asset';
import { File } from 'expo-file-system';
import { useState } from 'react';
import { Image } from 'react-native';

import sample from '../../assets/image/sample.png';
import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { runtimeDemo } from './runtime-demo';

type Result = { width: number; height: number; editable: boolean; bytes: number; preview: string };

const fixture = 'rawfile://image-loader-fixture.png';

export function ImageLoaderDemo() {
  const action = useAsyncResult();
  const [uri, setUri] = useState(fixture);
  const [preview, setPreview] = useState<string>();
  const busy = action.state.phase === 'running';

  function preset(value: string) {
    setUri(value);
    setPreview(undefined);
    action.clear();
  }

  function load(editing: boolean, callback: boolean) {
    if (!runtimeDemo) return;

    const loader = runtimeDemo;
    setPreview(undefined);
    void action.run(async () => {
      const { preview, ...result }: Result = JSON.parse(await loader.readImage(uri, editing, callback));
      setPreview(preview);
      return json(result);
    });
  }

  if (!runtimeDemo) return null;

  return (
    <Panel title="原生图片加载">
      <Field editable={!busy} label="图片 URI" onChangeText={setUri} value={uri} testID="image-loader-uri" />
      <ActionRow>
        <ActionButton disabled={busy} label="打包资源" onPress={() => preset(fixture)} tone="secondary" testID="image-loader-fixture" />
        <ActionButton disabled={busy} label="相对资源路径" onPress={() => preset('image-loader-fixture.png')} tone="secondary" />
        <ActionButton
          disabled={busy}
          label="文件 URI"
          onPress={() => void action.run(async () => {
            const asset = await Asset.fromModule(sample).downloadAsync();
            if (!asset.localUri) throw new Error('未取得样图的本地地址。');
            setUri(asset.localUri);
            return asset.localUri;
          })}
          tone="secondary"
        />
        <ActionButton
          disabled={busy}
          label="data URI"
          onPress={() => void action.run(async () => {
            const asset = await Asset.fromModule(sample).downloadAsync();
            if (!asset.localUri) throw new Error('未取得样图的本地地址。');
            setUri(`data:image/png;base64,${await new File(asset.localUri).base64()}`);
            return '已载入样图地址';
          })}
          tone="secondary"
        />
      </ActionRow>
      <ActionRow>
        <ActionButton disabled={busy} label="加载展示图片（Promise）" onPress={() => load(false, false)} testID="image-loader-display" />
        <ActionButton disabled={busy} label="加载展示图片（回调）" onPress={() => load(false, true)} tone="secondary" testID="image-loader-display-callback" />
        <ActionButton disabled={busy} label="加载可编辑图片（Promise）" onPress={() => load(true, false)} testID="image-loader-edit" />
        <ActionButton disabled={busy} label="加载可编辑图片（回调）" onPress={() => load(true, true)} tone="secondary" testID="image-loader-edit-callback" />
      </ActionRow>
      {preview ? <Image accessibilityLabel="解码后的图片" resizeMode="contain" source={{ uri: preview }} style={{ height: 180, width: '100%' }} testID="image-loader-preview" /> : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}
