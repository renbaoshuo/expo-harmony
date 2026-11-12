/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { SQLiteProvider, deepEqual, type SQLiteDatabase, type SQLiteOpenOptions, useSQLiteContext } from 'expo-sqlite';
import { Component, type PropsWithChildren, Suspense, useCallback, useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import notesAsset from '../../../assets/sqlite/notes.db';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, formatError } from '../../ui';
import { SQLiteActions, SQLiteSwitch, useSQLiteActions } from './workspace';

type ProviderConfig = {
  name: string;
  directory?: string;
  options?: SQLiteOpenOptions;
  assetSource?: { assetId: number; forceOverwrite: boolean };
  sql: string;
  useSuspense: boolean;
};

export function ProviderDemo({ options }: { options: SQLiteOpenOptions }) {
  const [name, setName] = useState('expo-harmony-provider.db');
  const [directory, setDirectory] = useState('');
  const [useAsset, setUseAsset] = useState(Platform.OS !== 'web');
  const [forceOverwrite, setForceOverwrite] = useState(false);
  const [useOptions, setUseOptions] = useState(false);
  const [suspense, setSuspense] = useState(false);
  const [sql, setSql] = useState('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, body TEXT)');
  const [config, setConfig] = useState<ProviderConfig>();
  const [left, setLeft] = useState('{"notes":{"count":1}}');
  const [right, setRight] = useState('{"notes":{"count":1}}');
  const comparison = useSQLiteActions();

  return (
    <>
      <Panel title="SQLiteProvider">
        <Field editable={!config} label="databaseName" onChangeText={setName} value={name} />
        <Field editable={!config} label="directory" onChangeText={setDirectory} value={directory} />
        <Field editable={!config} label="onInit 执行的 SQL" multiline onChangeText={setSql} value={sql} />
        <SQLiteSwitch disabled={Boolean(config)} label="沿用连接选项" onChange={setUseOptions} value={useOptions} />
        <SQLiteSwitch disabled={Boolean(config)} label="导入内置数据库" onChange={setUseAsset} value={useAsset} />
        <SQLiteSwitch disabled={Boolean(config) || !useAsset} label="forceOverwrite" onChange={setForceOverwrite} value={forceOverwrite} />
        <SQLiteSwitch disabled={Boolean(config)} label="useSuspense" onChange={setSuspense} value={suspense} />
        <ActionRow>
          <ActionButton
            disabled={Boolean(config) || !name}
            label="挂载 Provider"
            onPress={() => setConfig({
              name,
              directory: directory || undefined,
              options: useOptions ? options : undefined,
              assetSource: useAsset ? { assetId: notesAsset, forceOverwrite } : undefined,
              sql,
              useSuspense: suspense,
            })}
          />
          <ActionButton disabled={!config} label="卸载 Provider" onPress={() => setConfig(undefined)} tone="secondary" />
        </ActionRow>
        {config ? <ProviderConnection config={config} /> : null}
      </Panel>
      <Panel title="对象比较">
        <Field label="对象 A（JSON）" multiline onChangeText={setLeft} value={left} />
        <Field label="对象 B（JSON）" multiline onChangeText={setRight} value={right} />
        <SQLiteActions
          actions={comparison}
          items={[
            ['deepEqual', () => deepEqual(readObject(left), readObject(right))],
          ]}
        />
      </Panel>
    </>
  );
}

function ProviderConnection({ config }: { config: ProviderConfig }) {
  const [error, setError] = useState<Error>();
  const reportedError = useRef<Error>(undefined);
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  const onInit = useCallback(async (db: SQLiteDatabase) => {
    try {
      if (config.sql.trim()) await db.execAsync(config.sql);
    } catch (error) {
      await db.closeAsync();
      throw error;
    }
    if (!mounted.current && !config.useSuspense) await db.closeAsync();
  }, [config.sql, config.useSuspense]);

  const onError = useCallback((next: Error) => {
    if (reportedError.current === next) return;
    reportedError.current = next;
    // SQLiteProvider invokes onError during rendering.
    queueMicrotask(() => {
      if (mounted.current) setError(next);
    });
  }, []);

  if (error) return <ResultPanel state={{ phase: 'error', output: formatError(error) }} />;

  return (
    <ProviderBoundary>
      <Suspense fallback={<ResultPanel state={{ phase: 'running' }} />}>
        <SQLiteProvider
          assetSource={config.assetSource}
          databaseName={config.name}
          directory={config.directory}
          onError={config.useSuspense ? undefined : onError}
          onInit={onInit}
          options={config.options}
          useSuspense={config.useSuspense}
        >
          <ContextDemo />
        </SQLiteProvider>
      </Suspense>
    </ProviderBoundary>
  );
}

class ProviderBoundary extends Component<PropsWithChildren, { error?: Error }> {
  state = { error: undefined as Error | undefined };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  render() {
    const { error } = this.state;
    if (error) return <ResultPanel state={{ phase: 'error', output: formatError(error) }} />;
    return this.props.children;
  }
}

function ContextDemo() {
  const db = useSQLiteContext();
  const [sql, setSql] = useState('SELECT * FROM notes ORDER BY id');
  const actions = useSQLiteActions();

  return (
    <>
      <DataRow label="useSQLiteContext" value={db.databasePath} />
      <Field label="查询语句" multiline onChangeText={setSql} value={sql} />
      <SQLiteActions
        actions={actions}
        items={[
          ['getAllAsync', () => db.getAllAsync(sql)],
        ]}
      />
    </>
  );
}

function readObject(input: string): Record<string, unknown> | undefined {
  if (!input.trim()) return undefined;
  const parsed: unknown = JSON.parse(input);
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new Error('请填写 JSON 对象。');
  }
  return parsed as Record<string, unknown>;
}
