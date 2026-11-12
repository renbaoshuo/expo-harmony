/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type * as SQLite from 'expo-sqlite';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Switch } from 'react-native';

import { ActionButton, ActionRow, DataRow, ResultPanel, useAsyncResult } from '../../ui';

export type Slot = 'source' | 'destination';

type Cursor
  = | { sync: false; result: SQLite.SQLiteExecuteAsyncResult<unknown> }
    | { sync: true; result: SQLite.SQLiteExecuteSyncResult<unknown> };

export type Connection = {
  db: SQLite.SQLiteDatabase;
  statement?: SQLite.SQLiteStatement;
  statementSource?: string;
  cursor?: Cursor;
  session?: SQLite.SQLiteSession;
};

type Resources = Partial<Record<Slot, Connection>> & {
  snapshot?: Uint8Array;
  changeset?: Uint8Array;
};

export function useSQLiteWorkspace() {
  const current = useRef<Resources>({});
  const pending = useRef<Promise<string> | null>(null);
  const mounted = useRef(true);
  const [resources, setResources] = useState<Resources>({});
  const [busy, setBusy] = useState(false);
  const [slot, setSlot] = useState<Slot>('source');

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      async function release() {
        await pending.current?.catch(() => undefined);
        const { source, destination } = current.current;
        const connections = [source, destination].filter(connection => connection !== undefined);
        await Promise.allSettled(connections.map(async ({ session, statement, db }) => {
          await Promise.allSettled([session?.closeAsync(), statement?.finalizeAsync()]);
          await db.closeAsync();
        }));
      }
      void release();
    };
  }, []);

  function update(patch: Partial<Resources>) {
    current.current = { ...current.current, ...patch };
    if (mounted.current) setResources(current.current);
  }

  async function run(operation: () => unknown) {
    if (pending.current) throw new Error('请等当前 SQLite 操作完成。');
    const task = Promise.resolve().then(operation).then(displayValue);
    pending.current = task;
    setBusy(true);
    try {
      return await task;
    } finally {
      pending.current = null;
      if (mounted.current) setBusy(false);
    }
  }

  return { busy, resources, run, setSlot, slot, update, connection: resources[slot] };
}

export type Workspace = ReturnType<typeof useSQLiteWorkspace>;

type Operation = readonly [label: string, call: () => unknown, disabled?: boolean];

export function useSQLiteActions(workspace?: Workspace) {
  const result = useAsyncResult();
  const [sync, setSync] = useState(false);
  const pending = useRef<Promise<string | undefined>>(undefined);
  const settle = useCallback(() => pending.current, []);
  return {
    busy: workspace?.busy || result.state.phase === 'running',
    state: result.state,
    sync,
    setSync,
    settle,
    variant(name: string, operation: (sync: boolean) => unknown, disabled?: boolean): Operation {
      return [name + (sync ? 'Sync' : 'Async'), () => operation(sync), disabled];
    },
    run(operation: () => unknown) {
      pending.current = result.run(() => workspace
        ? workspace.run(operation)
        : Promise.resolve().then(operation).then(displayValue));
    },
  };
}

type Actions = ReturnType<typeof useSQLiteActions>;

export function SQLiteActions({ actions, items }: { actions: Actions; items: readonly Operation[] }) {
  return (
    <>
      <ActionRow>
        {items.map(([label, run, disabled]) => (
          <ActionButton
            key={label}
            disabled={actions.busy || disabled}
            label={label}
            onPress={() => actions.run(run)}
            tone="secondary"
          />
        ))}
      </ActionRow>
      <ResultPanel state={actions.state} />
    </>
  );
}

export function SQLiteSwitch({
  disabled, label, onChange, value,
}: {
  disabled?: boolean;
  label: string;
  onChange: (value: boolean) => void;
  value: boolean;
}) {
  return (
    <DataRow
      label={label}
      value={<Switch accessibilityLabel={label} disabled={disabled} onValueChange={onChange} value={value} />}
    />
  );
}

export function SQLiteMode({ actions }: { actions: Actions }) {
  return <SQLiteSwitch disabled={actions.busy} label="使用同步接口" onChange={actions.setSync} value={actions.sync} />;
}

export function describeBytes(bytes: Uint8Array) {
  return { byteLength: bytes.byteLength, firstBytes: Array.from(bytes.subarray(0, 24)) };
}

export function parseBytes(value: unknown): Uint8Array {
  if (!Array.isArray(value) || value.some(byte => !Number.isInteger(byte) || byte < 0 || byte > 255)) {
    throw new Error('字节请填写 0 到 255 的整数数组。');
  }
  return Uint8Array.from(value);
}

function displayValue(value: unknown): string {
  if (typeof value === 'string') return value;
  return JSON.stringify(value, (_, item) => item instanceof Uint8Array ? Array.from(item) : item, 2) ?? '已完成';
}
