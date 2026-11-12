/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Asset, type AssetMetadata, useAssets } from 'expo-asset';
import { useState } from 'react';

import animation from '../../assets/image/animation.gif';
import photo from '../../assets/image/sample.png';
import { json } from '../format';
import { antDesignFontAsset } from '../fixtures';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const defaultUrl = 'https://placehold.co/96x96.png';
const defaultMetadata = {
  httpServerLocation: '/assets',
  name: 'sample',
  hash: 'demo-image',
  type: 'png',
  width: 96,
  height: 96,
  scales: [1, 2],
  uri: defaultUrl,
};

function assetInfo({ downloaded, hash, height, localUri, name, type, uri, width }: Asset) {
  return { name, type, hash, uri, localUri, width, height, downloaded };
}

function AssetsHook({ multiple }: { multiple: boolean }) {
  const [assets, error] = useAssets(multiple ? [photo, animation] : photo);
  return <DataRow label="useAssets()" value={error?.message ?? (assets ? json(assets.map(assetInfo)) : '正在加载')} />;
}

export function AssetDemo() {
  const operation = useAsyncResult();
  const [uri, setUri] = useState(defaultUrl);
  const [secondUri, setSecondUri] = useState('https://placehold.co/192x192.png');
  const [name, setName] = useState('sample');
  const [type, setType] = useState('png');
  const [hash, setHash] = useState('');
  const [width, setWidth] = useState('96');
  const [height, setHeight] = useState('96');
  const [metadata, setMetadata] = useState(json(defaultMetadata));
  const [asset, setAsset] = useState<Asset>();
  const [hook, setHook] = useState<'single' | 'multiple'>();
  const busy = operation.state.phase === 'running';

  const inspect = (getAsset: () => Asset) => operation.run(() => {
    const value = getAsset();
    setAsset(value);
    return json(assetInfo(value));
  });
  const dimensions = () => ({ width: Number(width), height: Number(height) });

  return (
    <>
      <Panel title="资源引用">
        <Field label="资源 URI" onChangeText={setUri} value={uri} />
        <Field label="第二个资源 URI" onChangeText={setSecondUri} value={secondUri} />
        <Field label="名称" onChangeText={setName} value={name} />
        <Field label="文件类型" onChangeText={setType} value={type} />
        <Field label="哈希" onChangeText={setHash} value={hash} />
        <Field keyboardType="number-pad" label="宽度" onChangeText={setWidth} value={width} />
        <Field keyboardType="number-pad" label="高度" onChangeText={setHeight} value={height} />
        <ActionRow>
          <ActionButton disabled={busy} label="new Asset()" onPress={() => void inspect(() => new Asset({ uri, name, type, hash: hash || undefined, ...dimensions() }))} />
          <ActionButton disabled={busy} label="fromURI()" onPress={() => void inspect(() => Asset.fromURI(uri))} />
          <ActionButton disabled={busy} label="fromModule() 内置图片" onPress={() => void inspect(() => Asset.fromModule(photo))} />
          <ActionButton disabled={busy} label="fromModule() 内置字体" onPress={() => void inspect(() => Asset.fromModule(antDesignFontAsset()))} />
          <ActionButton disabled={busy} label="fromModule() URI" onPress={() => void inspect(() => Asset.fromModule(uri))} />
          <ActionButton disabled={busy} label="fromModule() 图片对象" onPress={() => void inspect(() => Asset.fromModule({ uri, ...dimensions() }))} />
        </ActionRow>
        <Field label="资源元数据 JSON" multiline onChangeText={setMetadata} value={metadata} />
        <ActionButton disabled={busy} label="fromMetadata()" onPress={() => void inspect(() => Asset.fromMetadata(JSON.parse(metadata) as AssetMetadata))} />
        <ActionRow>
          <ActionButton disabled={busy || !asset} label="downloadAsync()" onPress={() => asset && void operation.run(async () => json(assetInfo(await asset.downloadAsync())))} />
          <ActionButton disabled={busy} label="loadAsync() 单个模块" onPress={() => void operation.run(async () => json((await Asset.loadAsync(photo)).map(assetInfo)))} />
          <ActionButton disabled={busy} label="loadAsync() 模块列表" onPress={() => void operation.run(async () => json((await Asset.loadAsync([photo, animation])).map(assetInfo)))} />
          <ActionButton disabled={busy} label="loadAsync() URI" onPress={() => void operation.run(async () => json((await Asset.loadAsync(uri)).map(assetInfo)))} />
          <ActionButton disabled={busy} label="loadAsync() URI 列表" onPress={() => void operation.run(async () => json((await Asset.loadAsync([uri, secondUri])).map(assetInfo)))} />
        </ActionRow>
        <ResultPanel state={operation.state} />
      </Panel>

      <Panel title="useAssets()">
        <ActionRow>
          <ActionButton label="加载单个模块" onPress={() => setHook('single')} />
          <ActionButton label="加载模块列表" onPress={() => setHook('multiple')} />
          <ActionButton disabled={!hook} label="卸载示例" onPress={() => setHook(undefined)} tone="secondary" />
        </ActionRow>
        {hook ? <AssetsHook key={hook} multiple={hook === 'multiple'} /> : null}
      </Panel>
    </>
  );
}
