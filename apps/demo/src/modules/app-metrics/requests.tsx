/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import AppMetrics, {
  type NetworkRequestCompletedEvent,
  type NetworkRequestFilter,
  type NetworkRequestStartedEvent,
  useNetworkRequestObserver,
} from 'expo-app-metrics';
import { useReleasingSharedObject } from 'expo-modules-core';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../../format';
import { ActionButton, ActionRow, DataRow, Field, Panel } from '../../ui';
import { SystemApiActions } from '../system-api-actions';

type ObserverProps = {
  filter: NetworkRequestFilter | null;
  onStarted: (event: NetworkRequestStartedEvent) => void;
  onCompleted: (event: NetworkRequestCompletedEvent) => void;
};

function HookObserver(props: ObserverProps) {
  useNetworkRequestObserver(props);
  return null;
}

function DirectObserver({ filter, onStarted, onCompleted }: ObserverProps) {
  const observer = useReleasingSharedObject(() => new AppMetrics.NetworkRequestObserver(filter), []);
  const initialFilter = useRef(filter);

  useEffect(() => {
    if (initialFilter.current !== filter) {
      observer.setFilter(filter);
      initialFilter.current = filter;
    }
  }, [observer, filter]);

  useEffect(() => {
    const started = observer.addListener('requestStarted', onStarted);
    const completed = observer.addListener('requestCompleted', onCompleted);
    return () => {
      started.remove();
      completed.remove();
    };
  }, [observer, onStarted, onCompleted]);

  return null;
}

function readList(input: string): string[] | null {
  if (!input.trim()) return null;
  const value: unknown = JSON.parse(input);
  if (value === null) return null;
  if (!Array.isArray(value) || value.some(entry => typeof entry !== 'string')) {
    throw new Error('请输入字符串数组或 null。');
  }
  return value;
}

type ObserverMode = 'hook' | 'instance';

export function MetricsRequestDemo() {
  const [mode, setMode] = useState<ObserverMode>();
  const [hosts, setHosts] = useState('["example.com"]');
  const [methods, setMethods] = useState('["GET"]');
  const [filter, setFilter] = useState<NetworkRequestFilter | null>({ hosts: ['example.com'], methods: ['GET'] });
  const [url, setURL] = useState('https://example.com/');
  const [method, setMethod] = useState('GET');
  const [started, setStarted] = useState<NetworkRequestStartedEvent>();
  const [completed, setCompleted] = useState<NetworkRequestCompletedEvent>();

  if (Platform.OS === 'web' || !AppMetrics.NetworkRequestObserver) return null;

  const changeObserver = (next?: ObserverMode) => {
    setStarted(undefined);
    setCompleted(undefined);
    setMode(next);
  };

  return (
    <Panel title="网络请求监听">
      <Field label="主机名（JSON 数组）" onChangeText={setHosts} placeholder="留空不限主机" value={hosts} />
      <Field label="请求方法（JSON 数组）" onChangeText={setMethods} placeholder="留空不限方法" value={methods} />
      <SystemApiActions
        actions={[
          ['应用筛选条件', () => {
            const next = { hosts: readList(hosts), methods: readList(methods) };
            setFilter(next);
            return next;
          }],
          ['清除筛选条件', () => {
            setFilter(null);
            setHosts('');
            setMethods('');
          }],
        ]}
      />
      <ActionRow>
        <ActionButton label="用 Hook 监听" onPress={() => changeObserver('hook')} tone={mode === 'hook' ? 'primary' : 'secondary'} />
        <ActionButton label="用观察器实例监听" onPress={() => changeObserver('instance')} tone={mode === 'instance' ? 'primary' : 'secondary'} />
        <ActionButton disabled={!mode} label="停止监听" onPress={() => changeObserver()} tone="secondary" />
      </ActionRow>
      {mode === 'hook' ? <HookObserver filter={filter} onStarted={setStarted} onCompleted={setCompleted} /> : null}
      {mode === 'instance' ? <DirectObserver filter={filter} onStarted={setStarted} onCompleted={setCompleted} /> : null}
      {mode
        ? (
            <>
              <DataRow label="最近一次请求开始" value={started ? json(started) : '等待事件'} />
              <DataRow label="最近一次请求结束" value={completed ? json(completed) : '等待事件'} />
            </>
          )
        : null}
      <Field keyboardType="url" label="请求地址" onChangeText={setURL} value={url} />
      <Field label="请求方法" onChangeText={setMethod} value={method} />
      <SystemApiActions
        actions={[
          ['发送请求', async () => {
            const response = await fetch(url, { method });
            await response.text();
            return { status: response.status, url: response.url };
          }, undefined, !url.trim() || !method.trim()],
        ]}
      />
    </Panel>
  );
}
