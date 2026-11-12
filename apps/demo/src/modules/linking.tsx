/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Linking from 'expo-linking';
import { useEffect, useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function LinkingDemo() {
  const [url, setUrl] = useState('expoharmonydemo://module/linking');
  const [action, setAction] = useState('android.settings.SETTINGS');
  const [extras, setExtras] = useState('[]');
  const result = useAsyncResult();
  const busy = result.state.phase === 'running';

  return (
    <>
      <IncomingLinks />
      <Panel title="打开 URL">
        <Field label="url" onChangeText={setUrl} value={url} />
        <ActionRow>
          <ActionButton disabled={busy} label="parse()" onPress={() => void result.run(() => json(Linking.parse(url)))} />
          <ActionButton disabled={busy} label="canOpenURL()" onPress={() => void result.run(async () => json(await Linking.canOpenURL(url)))} />
          <ActionButton disabled={busy} label="openURL()" onPress={() => void result.run(async () => json(await Linking.openURL(url)))} />
          <ActionButton
            disabled={busy}
            label="openSettings()"
            onPress={() => void result.run(async () => {
              await Linking.openSettings();
              return '已打开应用设置';
            })}
          />
        </ActionRow>
        <ResultPanel state={result.state} />
      </Panel>
      <CreateURL />
      {Platform.OS === 'android'
        ? (
            <Panel title="Android Intent">
              <Field label="action" value={action} onChangeText={setAction} />
              <Field label="extras（JSON 数组）" value={extras} onChangeText={setExtras} />
              <ActionButton
                disabled={busy}
                label="sendIntent()"
                onPress={() => void result.run(async () => {
                  await Linking.sendIntent(action, JSON.parse(extras));
                  return '已发送 Intent';
                })}
              />
              <ResultPanel state={result.state} />
            </Panel>
          )
        : null}
    </>
  );
}

function IncomingLinks() {
  const latest = Linking.useLinkingURL();
  const url = Linking.useURL();
  const [observing, setObserving] = useState(false);
  const [received, setReceived] = useState('');
  const result = useAsyncResult();

  useEffect(() => {
    if (!observing) return;
    const listener = Linking.addEventListener('url', event => setReceived(event.url));
    return () => listener.remove();
  }, [observing]);

  return (
    <Panel title="接收链接">
      <DataRow label="useLinkingURL()" value={latest ?? 'null'} />
      <DataRow label="useURL()" value={url ?? 'null'} />
      <DataRow label="最近的 url 事件" value={received || '暂无'} />
      <ActionRow>
        <ActionButton label="getInitialURL()" onPress={() => void result.run(async () => json(await Linking.getInitialURL()))} />
        <ActionButton label="parseInitialURLAsync()" onPress={() => void result.run(async () => json(await Linking.parseInitialURLAsync()))} />
        <ActionButton label="getLinkingURL()" onPress={() => void result.run(() => json(Linking.getLinkingURL()))} />
        <ActionButton
          label="clearInitialURL()"
          onPress={() => void result.run(() => {
            Linking.clearInitialURL();
            return '已清除链接缓存';
          })}
          testID="linking-clear-initial-url"
        />
        <ActionButton label={observing ? '移除 url 监听' : '监听 url 事件'} onPress={() => setObserving(value => !value)} />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function CreateURL() {
  const [path, setPath] = useState('module/linking');
  const [scheme, setScheme] = useState('');
  const [queryParams, setQueryParams] = useState('{"source":"demo"}');
  const [isTripleSlashed, setTripleSlashed] = useState(false);
  const [isSilent, setSilent] = useState(false);
  const result = useAsyncResult();

  return (
    <Panel title="构造链接">
      <Field label="path" value={path} onChangeText={setPath} />
      <Field label="scheme" value={scheme} onChangeText={setScheme} />
      <Field label="queryParams（JSON 对象）" value={queryParams} onChangeText={setQueryParams} />
      <ActionRow>
        <ActionButton label={`isTripleSlashed = ${isTripleSlashed}`} tone={isTripleSlashed ? 'primary' : 'secondary'} onPress={() => setTripleSlashed(value => !value)} />
        <ActionButton label={`isSilent = ${isSilent}`} tone={isSilent ? 'primary' : 'secondary'} onPress={() => setSilent(value => !value)} />
      </ActionRow>
      <ActionRow>
        <ActionButton
          label="createURL()"
          onPress={() => void result.run(() => Linking.createURL(path, {
            scheme: scheme || undefined,
            queryParams: JSON.parse(queryParams),
            isTripleSlashed,
          }))}
        />
        <ActionButton label="resolveScheme()" onPress={() => void result.run(() => Linking.resolveScheme({ scheme: scheme || undefined, isSilent }))} />
        <ActionButton label="hasCustomScheme()" onPress={() => void result.run(() => json(Linking.hasCustomScheme()))} />
        <ActionButton label="hasConstantsManifest()" onPress={() => void result.run(() => json(Linking.hasConstantsManifest()))} />
        <ActionButton label="collectManifestSchemes()" onPress={() => void result.run(() => json(Linking.collectManifestSchemes()))} />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}
