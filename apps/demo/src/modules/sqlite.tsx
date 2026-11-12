/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as SQLite from 'expo-sqlite';
import { useEffect, useRef, useState } from 'react';

import { ActionButton, ActionRow, DataRow, Field, Panel } from '../ui';
import { ProviderDemo } from './sqlite/provider';
import { QueryDemo, StatementDemo, TaggedQueryDemo, TransactionDemo } from './sqlite/queries';
import { SessionDemo, SnapshotDemo } from './sqlite/snapshots';
import { KeyValueDemo, LocalStorageDemo } from './sqlite/storage';
import { SQLiteActions, SQLiteMode, SQLiteSwitch, type Workspace, useSQLiteActions, useSQLiteWorkspace } from './sqlite/workspace';

const DATABASE = 'expo-harmony-demo.db';

export function SQLiteDemo() {
  const workspace = useSQLiteWorkspace();
  const [directories, setDirectories] = useState({ source: '', destination: '' });
  const [name, setName] = useState(DATABASE);
  const [copyName, setCopyName] = useState('expo-harmony-demo-copy.db');
  const [enableChangeListener, setEnableChangeListener] = useState(false);
  const [useNewConnection, setUseNewConnection] = useState(false);
  const [finalizeUnusedStatementsBeforeClosing, setFinalizeUnusedStatementsBeforeClosing] = useState(true);
  const [url, setUrl] = useState('');
  const [authToken, setAuthToken] = useState('');
  const [remoteOnly, setRemoteOnly] = useState(false);
  const actions = useSQLiteActions(workspace);
  const { db, session, statement } = workspace.connection ?? {};
  const { slot } = workspace;
  const databaseName = slot === 'source' ? name : copyName;
  const directory = directories[slot];
  const options: SQLite.SQLiteOpenOptions = {
    enableChangeListener,
    useNewConnection,
    finalizeUnusedStatementsBeforeClosing,
    ...(url || authToken ? { libSQLOptions: { url, authToken, remoteOnly } } : {}),
  };

  async function open(sync: boolean) {
    const database = sync
      ? SQLite.openDatabaseSync(databaseName, options, directory || undefined)
      : await SQLite.openDatabaseAsync(databaseName, options, directory || undefined);
    workspace.update({ [slot]: { db: database } });
    return database.databasePath;
  }

  async function close(sync: boolean) {
    if (!db) return;
    if (session) {
      if (sync) session.closeSync();
      else await session.closeAsync();
    }
    try {
      if (sync) db.closeSync();
      else await db.closeAsync();
    } finally {
      workspace.update({ [slot]: undefined });
    }
  }

  return (
    <>
      <Panel title="数据库连接">
        <ActionRow>
          <ActionButton
            disabled={workspace.busy}
            label="源数据库"
            onPress={() => workspace.setSlot('source')}
            tone={slot === 'source' ? 'primary' : 'secondary'}
          />
          <ActionButton
            disabled={workspace.busy}
            label="目标数据库"
            onPress={() => workspace.setSlot('destination')}
            tone={slot === 'destination' ? 'primary' : 'secondary'}
          />
        </ActionRow>
        <Field
          editable={!db}
          label="数据库文件名"
          onChangeText={slot === 'source' ? setName : setCopyName}
          placeholder=":memory:"
          value={databaseName}
        />
        <Field
          editable={!db}
          label="目录"
          onChangeText={value => setDirectories(previous => ({ ...previous, [slot]: value }))}
          placeholder={String(SQLite.defaultDatabaseDirectory ?? '')}
          value={directory}
        />
        <DataRow label="当前数据库" value={db?.databasePath ?? databaseName} />
        <SQLiteSwitch label="enableChangeListener" onChange={setEnableChangeListener} value={enableChangeListener} />
        <SQLiteSwitch label="useNewConnection" onChange={setUseNewConnection} value={useNewConnection} />
        <SQLiteSwitch
          label="finalizeUnusedStatementsBeforeClosing"
          onChange={setFinalizeUnusedStatementsBeforeClosing}
          value={finalizeUnusedStatementsBeforeClosing}
        />
        <Field label="libSQL 服务地址" onChangeText={setUrl} placeholder="libsql://example.turso.io" value={url} />
        <Field label="libSQL 令牌" onChangeText={setAuthToken} secureTextEntry value={authToken} />
        <SQLiteSwitch label="remoteOnly" onChange={setRemoteOnly} value={remoteOnly} />
        <SQLiteMode actions={actions} />
        <SQLiteActions
          actions={actions}
          items={[
            actions.variant('openDatabase', open, Boolean(db) || !databaseName),
            actions.variant('close', close, !db || Boolean(statement && !db.options.finalizeUnusedStatementsBeforeClosing)),
            actions.variant('deleteDatabase', sync => sync
              ? SQLite.deleteDatabaseSync(databaseName, directory || undefined)
              : SQLite.deleteDatabaseAsync(databaseName, directory || undefined), Boolean(db) || !databaseName),
            ['defaultDatabaseDirectory', () => SQLite.defaultDatabaseDirectory],
            ['databasePath', () => db?.databasePath, !db],
            ['options', () => {
              const openOptions = db?.options;
              if (!openOptions?.libSQLOptions) return openOptions;
              const { authToken: _authToken, ...libSQLOptions } = openOptions.libSQLOptions;
              return { ...openOptions, libSQLOptions };
            }, !db],
            ['syncLibSQL', () => db?.syncLibSQL(), !db?.options.libSQLOptions],
          ]}
        />
      </Panel>
      <QueryDemo workspace={workspace} />
      <StatementDemo workspace={workspace} />
      <TaggedQueryDemo workspace={workspace} />
      <TransactionDemo workspace={workspace} />
      <ChangeListenerDemo />
      <SnapshotDemo options={options} workspace={workspace} />
      <SessionDemo workspace={workspace} />
      <ExtensionDemo workspace={workspace} />
      <ProviderDemo options={options} />
      <KeyValueDemo />
      <LocalStorageDemo />
    </>
  );
}

function ChangeListenerDemo() {
  const [event, setEvent] = useState<SQLite.DatabaseChangeEvent>();
  const [listening, setListening] = useState(false);
  const listener = useRef<ReturnType<typeof SQLite.addDatabaseChangeListener> | null>(null);
  const actions = useSQLiteActions();

  useEffect(() => () => listener.current?.remove(), []);

  return (
    <Panel title="数据库变更">
      <SQLiteActions
        actions={actions}
        items={[
          ['addDatabaseChangeListener', () => {
            listener.current = SQLite.addDatabaseChangeListener(setEvent);
            setListening(true);
            return '正在监听';
          }, listening],
          ['remove', () => {
            listener.current?.remove();
            listener.current = null;
            setListening(false);
            return '已停止监听';
          }, !listening],
        ]}
      />
      {event
        ? Object.entries(event).map(([key, value]) => (
            <DataRow key={key} label={key} value={String(value)} />
          ))
        : null}
    </Panel>
  );
}

function ExtensionDemo({ workspace }: { workspace: Workspace }) {
  const bundled = SQLite.bundledExtensions?.['sqlite-vec'];
  const [libPath, setLibPath] = useState(bundled?.libPath ?? '');
  const [entryPoint, setEntryPoint] = useState(bundled?.entryPoint ?? '');
  const actions = useSQLiteActions(workspace);
  const db = workspace.connection?.db;
  return (
    <Panel title="SQLite 扩展">
      <Field label="扩展路径" onChangeText={setLibPath} value={libPath} />
      <Field label="入口函数" onChangeText={setEntryPoint} value={entryPoint} />
      <SQLiteMode actions={actions} />
      <SQLiteActions
        actions={actions}
        items={[
          ['bundledExtensions', () => SQLite.bundledExtensions],
          actions.variant('loadExtension', sync => sync
            ? db?.loadExtensionSync(libPath, entryPoint || undefined)
            : db?.loadExtensionAsync(libPath, entryPoint || undefined), !db || !libPath),
        ]}
      />
    </Panel>
  );
}
