/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { EventEmitter, getExpoGoProjectConfig, isRunningInExpoGo, reloadAppAsync, useEvent, useEventListener } from 'expo';
import { router } from 'expo-router';
import { useState } from 'react';

import { json } from '../format';
import { ActionButton, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

type Events = { message: (value: string) => void };

export function ExpoDemo() {
  const action = useAsyncResult();
  const reload = useAsyncResult();
  const [reason, setReason] = useState('Expo demo');
  const [initialValue, setInitialValue] = useState('等待消息');
  const [message, setMessage] = useState('你好');
  const [emitter] = useState(() => new EventEmitter<Events>());

  return (
    <>
      <Panel title="Expo Go">
        <DataRow label="isRunningInExpoGo()" value={String(isRunningInExpoGo())} />
        <ActionButton label="getExpoGoProjectConfig()" onPress={() => void action.run(() => json(getExpoGoProjectConfig()))} />
        <ResultPanel state={action.state} />
      </Panel>
      <Panel title="事件 Hooks">
        <Field label="initialValue" value={initialValue} onChangeText={setInitialValue} />
        <Field label="message" value={message} onChangeText={setMessage} />
        <ActionButton label="发送 message 事件" onPress={() => emitter.emit('message', message)} />
        <EventValues key={initialValue} emitter={emitter} initialValue={initialValue} />
      </Panel>
      <Panel title="重新加载应用">
        <Field label="reason" value={reason} onChangeText={setReason} />
        <ActionButton
          label="reloadAppAsync()"
          disabled={reload.state.phase === 'running'}
          onPress={() => void reload.run(async () => {
            await reloadAppAsync(reason || undefined);
            return '正在重新加载';
          })}
          testID="expo-reload"
        />
        <ResultPanel state={reload.state} />
      </Panel>
      <Panel title="expo/fetch">
        <ActionButton label="打开网络请求示例" onPress={() => router.push('/module/fetch')} tone="secondary" />
      </Panel>
    </>
  );
}

function EventValues({ emitter, initialValue }: {
  emitter: InstanceType<typeof EventEmitter<Events>>;
  initialValue: string;
}) {
  const message = useEvent(emitter, 'message', initialValue);
  const [count, setCount] = useState(0);
  useEventListener(emitter, 'message', () => setCount(value => value + 1));

  return (
    <>
      <DataRow label="useEvent()" value={message} />
      <DataRow label="useEventListener() 收到的次数" value={count} />
    </>
  );
}
