/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { useEffect, useState } from 'react';
import { Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, ResultPanel, useAsyncResult } from '../ui';

type ApiAction = readonly [
  label: string,
  invoke: () => unknown,
  testID?: string,
  disabled?: boolean,
];

export function SystemApiActions({ actions }: { actions: readonly ApiAction[] }) {
  const result = useAsyncResult();
  const [selected, setSelected] = useState<string>();

  return (
    <>
      <ActionRow>
        {actions.map(([label, invoke, testID, disabled]) => (
          <ActionButton
            disabled={disabled || result.state.phase === 'running'}
            key={label}
            label={label}
            onPress={() => {
              setSelected(label);
              void result.run(async () => {
                const value = await invoke();
                if (value === undefined) return '已完成';
                return typeof value === 'string' && value ? value : json(value);
              });
            }}
            testID={testID}
            tone={selected === undefined || selected === label ? 'primary' : 'secondary'}
          />
        ))}
      </ActionRow>
      <ResultPanel state={result.state} />
    </>
  );
}

export function SystemEvent<Event>({ label, subscribe }: {
  label: string;
  subscribe: (listener: (event: Event) => void) => { remove(): void };
}) {
  const [watching, setWatching] = useState(false);
  const [payload, setPayload] = useState<string>();

  useEffect(() => {
    if (!watching) return;
    const subscription = subscribe(event => setPayload(json(event)));
    return () => subscription.remove();
  }, [subscribe, watching]);

  return (
    <>
      <DataRow
        label={label}
        value={(
          <Switch
            accessibilityLabel={label}
            onValueChange={(enabled) => {
              setWatching(enabled);
              if (enabled) setPayload(undefined);
            }}
            value={watching}
          />
        )}
      />
      {watching ? <DataRow label="最近一次事件" value={payload ?? '等待事件'} /> : null}
    </>
  );
}
