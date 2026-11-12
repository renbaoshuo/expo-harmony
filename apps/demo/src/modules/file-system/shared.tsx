/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Directory, File, Paths, type WatchEvent, type WatchEventType, type WatchOptions, type WatchSubscription } from 'expo-file-system';
import { useEffect, useRef, useState } from 'react';

import { json } from '../../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../../ui';

export function sandbox() {
  const directory = new Directory(Paths.cache, 'expo-harmony-demo-files');
  directory.create({ idempotent: true });
  return directory;
}

export function childName(value: string) {
  if (!/^[\p{L}\p{N}_. -]+$/u.test(value) || value === '.' || value === '..' || !value.trim()) {
    throw new Error('请输入有效的文件名或目录名。');
  }
  return value;
}

export function localFile(path: string) {
  return new File(sandbox(), ...path.split('/').map(childName));
}

export function localDirectory(path: string) {
  return new Directory(sandbox(), ...path.split('/').map(childName));
}

export function Toggle({ label, value, onChange }: {
  label: string;
  value: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <ActionButton label={`${label} ${value ? '✓' : '○'}`} onPress={() => onChange(!value)} tone={value ? 'primary' : 'secondary'} />
  );
}

type FileAction = [label: string, operation: () => unknown, disabled?: boolean];

export function FileActions({ actions, disabled }: { actions: FileAction[]; disabled?: boolean }) {
  const result = useAsyncResult();
  return (
    <>
      <ActionRow>
        {actions.map(([label, operation, blocked]) => (
          <ActionButton
            key={label}
            label={label}
            disabled={disabled || blocked || result.state.phase === 'running'}
            onPress={() => void result.run(async () => {
              const value = await operation();
              return value === undefined ? '已完成' : json(value);
            })}
          />
        ))}
      </ActionRow>
      <ResultPanel state={result.state} />
    </>
  );
}

const watchTypes: WatchEventType[] = ['created', 'modified', 'deleted', 'renamed'];

export function WatchDemo({ watch }: {
  watch: (callback: (event: WatchEvent<File | Directory>) => void, options: WatchOptions) => WatchSubscription;
}) {
  const subscription = useRef<WatchSubscription | null>(null);
  const [active, setActive] = useState(false);
  const [debounce, setDebounce] = useState('100');
  const [events, setEvents] = useState(watchTypes);
  const [lastEvent, setLastEvent] = useState<object>();
  useEffect(() => () => subscription.current?.remove(), []);

  return (
    <Panel title="监听文件变化">
      <Field label="debounce 毫秒" keyboardType="number-pad" onChangeText={setDebounce} value={debounce} />
      <ActionRow>
        {watchTypes.map(type => (
          <Toggle
            key={type}
            label={type}
            value={events.includes(type)}
            onChange={enabled => setEvents(current => (
              enabled ? [...current, type] : current.filter(value => value !== type)
            ))}
          />
        ))}
      </ActionRow>
      <FileActions actions={[
        ['watch()', () => {
          subscription.current = watch(event => setLastEvent({
            type: event.type,
            target: event.target.uri,
            newTarget: event.newTarget?.uri,
            nativeEventFlags: event.nativeEventFlags,
          }), { debounce: debounce ? Number(debounce) : undefined, events });
          setActive(true);
          setLastEvent(undefined);
        }, active],
        ['remove()', () => {
          subscription.current?.remove();
          subscription.current = null;
          setActive(false);
        }, !active],
      ]}
      />
      {lastEvent ? <DataRow label="最近一次变化" value={json(lastEvent)} /> : null}
    </Panel>
  );
}

export async function firstChunk(stream: ReadableStream<Uint8Array>) {
  const reader = stream.getReader();
  try {
    const item = await reader.read();
    return { done: item.done, bytes: Array.from(item.value ?? []) };
  } finally {
    try {
      await reader.cancel();
    } finally {
      reader.releaseLock();
    }
  }
}
