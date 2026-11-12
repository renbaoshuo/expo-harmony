/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { router } from 'expo-router';
import {
  EventEmitter, installOnUIRuntime, requireNativeModule, requireOptionalNativeModule, uuid, type EventSubscription,
} from 'expo-modules-core';
import { useEffect, useRef, useState } from 'react';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function ModulesCoreDemo() {
  const registry = useAsyncResult();
  const [moduleName, setModuleName] = useState('ExpoModuleShowcase');

  function describeModule(module: object | null) {
    return json(module ? { name: moduleName, keys: Object.keys(module) } : null);
  }

  return (
    <>
      <Panel title="查找原生模块">
        <Field label="moduleName" value={moduleName} onChangeText={setModuleName} />
        <ActionRow>
          <ActionButton label="requireNativeModule()" onPress={() => void registry.run(() => describeModule(requireNativeModule(moduleName)))} />
          <ActionButton label="requireOptionalNativeModule()" onPress={() => void registry.run(() => describeModule(requireOptionalNativeModule(moduleName)))} />
          <ActionButton label="读取模块注册表" onPress={() => void registry.run(() => json(Object.keys(globalThis.expo?.modules ?? {}).sort()))} />
        </ActionRow>
        <ResultPanel state={registry.state} />
      </Panel>
      <EventEmitterDemo />
      <UUIDDemo />
      <WorkletDemo />
      <Panel title="原生视图和共享对象">
        <ActionButton label="打开原生模块示例" onPress={() => router.push('/module/expo-module-showcase')} />
      </Panel>
    </>
  );
}

function EventEmitterDemo() {
  const [emitter] = useState(() => new EventEmitter<Record<string, (value: string) => void>>());
  const [eventName, setEventName] = useState('message');
  const [payload, setPayload] = useState('你好');
  const [message, setMessage] = useState('');
  const result = useAsyncResult();
  const subscriptions = useRef(new Map<string, EventSubscription>());
  const listener = setMessage;

  useEffect(() => {
    const active = subscriptions.current;
    return () => {
      for (const subscription of active.values()) subscription.remove();
    };
  }, []);

  function invoke(operation: () => void) {
    void result.run(() => {
      operation();
      return json({ eventName, listenerCount: emitter.listenerCount(eventName) });
    });
  }

  return (
    <Panel title="EventEmitter">
      <Field label="eventName" value={eventName} onChangeText={setEventName} />
      <Field label="payload" value={payload} onChangeText={setPayload} />
      <ActionRow>
        <ActionButton
          label="addListener()"
          onPress={() => invoke(() => {
            subscriptions.current.get(eventName)?.remove();
            subscriptions.current.set(eventName, emitter.addListener(eventName, listener));
          })}
        />
        <ActionButton label="emit()" onPress={() => invoke(() => emitter.emit(eventName, payload))} />
        <ActionButton label="listenerCount()" onPress={() => invoke(() => {})} />
        <ActionButton
          label="subscription.remove()"
          onPress={() => invoke(() => {
            subscriptions.current.get(eventName)?.remove();
            subscriptions.current.delete(eventName);
          })}
        />
        <ActionButton
          label="removeListener()"
          onPress={() => invoke(() => {
            emitter.removeListener(eventName, listener);
            subscriptions.current.delete(eventName);
          })}
        />
        <ActionButton
          label="removeAllListeners()"
          onPress={() => invoke(() => {
            emitter.removeAllListeners(eventName);
            subscriptions.current.delete(eventName);
          })}
        />
      </ActionRow>
      <DataRow label="最近收到的数据" value={message || '暂无'} />
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function UUIDDemo() {
  const [name, setName] = useState('example.com');
  const [namespace, setNamespace] = useState<string>(uuid.namespace.dns);
  const result = useAsyncResult();

  return (
    <Panel title="UUID">
      <Field label="name" value={name} onChangeText={setName} />
      <Field label="namespace（UUID 或 JSON 字节数组）" value={namespace} onChangeText={setNamespace} />
      <ActionRow>
        {Object.entries(uuid.namespace).map(([key, value]) => (
          <ActionButton
            key={key}
            label={key}
            tone={namespace === value ? 'primary' : 'secondary'}
            onPress={() => setNamespace(value)}
          />
        ))}
      </ActionRow>
      <ActionRow>
        <ActionButton label="uuid.v4()" onPress={() => void result.run(() => uuid.v4())} />
        <ActionButton
          label="uuid.v5()"
          onPress={() => void result.run(() =>
            uuid.v5(name, namespace.trim().startsWith('[') ? JSON.parse(namespace) : namespace.trim()))}
        />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function WorkletDemo() {
  const result = useAsyncResult();

  return (
    <Panel title="Worklets UI 运行时">
      <ActionButton
        label="installOnUIRuntime()"
        disabled={result.state.phase === 'running'}
        onPress={() => void result.run(async () => {
          const { getUIRuntimeHolder } = await import('react-native-worklets');
          installOnUIRuntime(getUIRuntimeHolder());
          return 'Expo Modules 已安装到 UI 运行时';
        })}
      />
      <ResultPanel state={result.state} />
    </Panel>
  );
}
