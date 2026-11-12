/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { useEffect, useState } from 'react';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Panel, ResultPanel, useAsyncResult } from '../ui';
import { runtimeDemo } from './runtime-demo';

const properties = ['isEnabled', 'runtimeVersion', 'updateUrl', 'requestHeaders', 'launchedUpdateId', 'embeddedUpdateId', 'launchAssetPath'];

export function UpdatesInterfaceDemo() {
  const result = useAsyncResult();
  const context = useAsyncResult();
  const [observing, setObserving] = useState(false);
  const [event, setEvent] = useState('');

  useEffect(() => {
    if (!observing || !runtimeDemo) return;

    const subscription = runtimeDemo.addListener('onUpdatesStateChange', value => setEvent(value.event));
    return () => subscription.remove();
  }, [observing]);

  if (!runtimeDemo) return <Panel title="此示例需要 HarmonyOS 原生模块" />;

  return (
    <>
      <Panel title="UpdatesControllerRegistry.controller">
        <ActionRow>
          {properties.map(property => (
            <ActionButton
              key={property}
              label={property}
              onPress={() => void result.run(() => json(JSON.parse(runtimeDemo!.readUpdates(property))))}
            />
          ))}
        </ActionRow>
        <ResultPanel state={result.state} />
      </Panel>
      <Panel title="更新状态事件">
        <ActionRow>
          <ActionButton label={observing ? 'subscription.remove()' : 'subscribeToUpdatesStateChanges()'} onPress={() => setObserving(value => !value)} />
          <ActionButton
            label="subscription.getContext()"
            disabled={!observing}
            onPress={() => void context.run(() =>
              json(JSON.parse(runtimeDemo!.readUpdates('getContext'))))}
          />
        </ActionRow>
        <DataRow label="最近的 updatesStateDidChange" value={event || '暂无'} />
        <ResultPanel state={context.state} />
      </Panel>
    </>
  );
}
