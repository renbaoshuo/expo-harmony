/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as SQLite from 'expo-sqlite';
import { useState } from 'react';

import { DataRow, Field, Panel } from '../../ui';
import { SQLiteActions, SQLiteMode, SQLiteSwitch, describeBytes, parseBytes, type Workspace, useSQLiteActions } from './workspace';

export function SnapshotDemo({ options, workspace }: { options: SQLite.SQLiteOpenOptions; workspace: Workspace }) {
  const [schema, setSchema] = useState('main');
  const [sourceSchema, setSourceSchema] = useState('main');
  const [destinationSchema, setDestinationSchema] = useState('main');
  const [inputBytes, setInputBytes] = useState('');
  const actions = useSQLiteActions(workspace);
  const backupActions = useSQLiteActions(workspace);
  const { connection, resources, slot } = workspace;
  const { destination, snapshot, source } = resources;

  async function serialize(sync: boolean) {
    if (!connection) return;
    const db = connection.db;
    const bytes = sync ? db.serializeSync(schema || undefined) : await db.serializeAsync(schema || undefined);
    workspace.update({ snapshot: bytes });
    return describeBytes(bytes);
  }

  async function deserialize(sync: boolean) {
    const bytes = inputBytes.trim() ? parseBytes(JSON.parse(inputBytes)) : snapshot;
    if (!bytes) return;
    const db = sync
      ? SQLite.deserializeDatabaseSync(bytes, options)
      : await SQLite.deserializeDatabaseAsync(bytes, options);
    workspace.update({ [slot]: { db } });
    return db.databasePath;
  }

  function backup(sync: boolean) {
    if (!source || !destination) return;
    const config = {
      sourceDatabase: source.db,
      sourceDatabaseName: sourceSchema || undefined,
      destDatabase: destination.db,
      destDatabaseName: destinationSchema || undefined,
    };
    return sync ? SQLite.backupDatabaseSync(config) : SQLite.backupDatabaseAsync(config);
  }

  return (
    <>
      <Panel title="数据库快照">
        <Field label="数据库别名" onChangeText={setSchema} value={schema} />
        <Field label="快照字节（JSON）" multiline onChangeText={setInputBytes} value={inputBytes} />
        {snapshot ? <DataRow label="已保存的快照" value={`${snapshot.byteLength} 字节`} /> : null}
        <SQLiteMode actions={actions} />
        <SQLiteActions
          actions={actions}
          items={[
            actions.variant('serialize', serialize, !connection),
            actions.variant('deserializeDatabase', deserialize, Boolean(connection) || (!inputBytes.trim() && !snapshot)),
          ]}
        />
      </Panel>
      <Panel title="数据库备份">
        <Field label="源数据库别名" onChangeText={setSourceSchema} value={sourceSchema} />
        <Field label="目标数据库别名" onChangeText={setDestinationSchema} value={destinationSchema} />
        <SQLiteMode actions={backupActions} />
        <SQLiteActions
          actions={backupActions}
          items={[
            backupActions.variant('backupDatabase', backup, !source || !destination),
          ]}
        />
      </Panel>
    </>
  );
}

export function SessionDemo({ workspace }: { workspace: Workspace }) {
  const [schema, setSchema] = useState('main');
  const [table, setTable] = useState('notes');
  const [allTables, setAllTables] = useState(false);
  const [enabled, setEnabled] = useState(true);
  const [inputBytes, setInputBytes] = useState('');
  const actions = useSQLiteActions(workspace);
  const { connection, resources: { changeset }, slot } = workspace;
  const session = connection?.session;
  const hasChangeset = Boolean(inputBytes.trim() || changeset);

  async function create(sync: boolean) {
    if (!connection) return;
    const next = sync
      ? connection.db.createSessionSync(schema || undefined)
      : await connection.db.createSessionAsync(schema || undefined);
    workspace.update({ [slot]: { ...connection, session: next } });
  }

  async function close(sync: boolean) {
    if (!connection || !session) return;
    if (sync) session.closeSync();
    else await session.closeAsync();
    workspace.update({ [slot]: { ...connection, session: undefined } });
  }

  function getChangeset() {
    return inputBytes.trim() ? parseBytes(JSON.parse(inputBytes)) : changeset;
  }

  async function generate(kind: 'regular' | 'inverted' | 'invert', sync: boolean) {
    if (!session) return;
    let bytes: Uint8Array;
    if (kind === 'invert') {
      const input = getChangeset();
      if (!input) return;
      bytes = sync ? session.invertChangesetSync(input) : await session.invertChangesetAsync(input);
    } else if (kind === 'inverted') {
      bytes = sync ? session.createInvertedChangesetSync() : await session.createInvertedChangesetAsync();
    } else {
      bytes = sync ? session.createChangesetSync() : await session.createChangesetAsync();
    }
    workspace.update({ changeset: bytes });
    return describeBytes(bytes);
  }

  return (
    <Panel title="SQLite Session">
      <Field label="数据库别名" onChangeText={setSchema} value={schema} />
      <Field editable={!allTables} label="表名" onChangeText={setTable} value={table} />
      <SQLiteSwitch label="跟踪所有表" onChange={setAllTables} value={allTables} />
      <SQLiteSwitch label="记录变更" onChange={setEnabled} value={enabled} />
      <Field label="变更集字节（JSON）" multiline onChangeText={setInputBytes} value={inputBytes} />
      {changeset ? <DataRow label="已保存的变更集" value={`${changeset.byteLength} 字节`} /> : null}
      <SQLiteMode actions={actions} />
      <SQLiteActions
        actions={actions}
        items={[
          actions.variant('createSession', create, !connection || Boolean(session)),
          actions.variant('attach', sync => sync
            ? session?.attachSync(allTables ? null : table)
            : session?.attachAsync(allTables ? null : table), !session || (!allTables && !table)),
          actions.variant('enable', sync => sync ? session?.enableSync(enabled) : session?.enableAsync(enabled), !session),
          actions.variant('createChangeset', sync => generate('regular', sync), !session),
          actions.variant('createInvertedChangeset', sync => generate('inverted', sync), !session),
          actions.variant('invertChangeset', sync => generate('invert', sync), !session || !hasChangeset),
          actions.variant('applyChangeset', (sync) => {
            const bytes = getChangeset();
            if (bytes) return sync ? session?.applyChangesetSync(bytes) : session?.applyChangesetAsync(bytes);
          }, !session || !hasChangeset),
          actions.variant('close', close, !session),
        ]}
      />
    </Panel>
  );
}
