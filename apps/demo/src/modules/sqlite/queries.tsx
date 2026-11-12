/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type * as SQLite from 'expo-sqlite';
import { useState } from 'react';
import { Platform } from 'react-native';

import { Field, Panel } from '../../ui';
import { SQLiteActions, SQLiteMode, SQLiteSwitch, parseBytes, type Workspace, useSQLiteActions } from './workspace';

const QUERY = 'SELECT ? AS body UNION ALL SELECT \'第二行\'';
const CREATE_TABLE = 'CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, body TEXT)';
const DEFAULT_PARAMS = '["你好，SQLite"]';

export function QueryDemo({ workspace }: { workspace: Workspace }) {
  const [script, setScript] = useState(CREATE_TABLE);
  const [writeSql, setWriteSql] = useState('INSERT INTO notes (body) VALUES (?)');
  const [sql, setSql] = useState(QUERY);
  const [params, setParams] = useState(DEFAULT_PARAMS);
  const [variadic, setVariadic] = useState(false);
  const actions = useSQLiteActions(workspace);
  const db = workspace.connection?.db;
  const bind = <T,>(operation: BindCall<T>) => callWithParams(params, variadic, operation);

  return (
    <Panel title="执行 SQL">
      <Field label="SQL 脚本" multiline onChangeText={setScript} value={script} />
      <Field label="写入语句" multiline onChangeText={setWriteSql} value={writeSql} />
      <Field label="查询语句" multiline onChangeText={setSql} value={sql} />
      <ParameterField onChange={setParams} value={params} />
      <SQLiteSwitch label="逐个传入位置参数" onChange={setVariadic} value={variadic} />
      <SQLiteMode actions={actions} />
      <SQLiteActions
        actions={actions}
        items={[
          actions.variant('exec', sync => sync ? db?.execSync(script) : db?.execAsync(script), !db),
          actions.variant('run', sync => db && (sync
            ? bind(db.runSync.bind(db, writeSql) as BindCall<SQLite.SQLiteRunResult>)
            : bind(db.runAsync.bind(db, writeSql) as BindCall<Promise<SQLite.SQLiteRunResult>>)), !db),
          actions.variant('getFirst', sync => db && (sync
            ? bind(db.getFirstSync.bind(db, sql) as BindCall<unknown>)
            : bind(db.getFirstAsync.bind(db, sql) as BindCall<Promise<unknown>>)), !db),
          actions.variant('getAll', sync => db && (sync
            ? bind(db.getAllSync.bind(db, sql) as BindCall<unknown[]>)
            : bind(db.getAllAsync.bind(db, sql) as BindCall<Promise<unknown[]>>)), !db),
          actions.variant('getEach', sync => db && (sync
            ? Array.from(bind(db.getEachSync.bind(db, sql) as BindCall<IterableIterator<unknown>>))
            : collect(bind(db.getEachAsync.bind(db, sql) as BindCall<AsyncIterableIterator<unknown>>))), !db),
        ]}
      />
    </Panel>
  );
}

export function StatementDemo({ workspace }: { workspace: Workspace }) {
  const [sql, setSql] = useState(QUERY);
  const [params, setParams] = useState(DEFAULT_PARAMS);
  const [variadic, setVariadic] = useState(false);
  const actions = useSQLiteActions(workspace);
  const { connection, slot } = workspace;
  const { cursor, db, statement } = connection ?? {};
  const cursorUnavailable = cursor?.sync !== actions.sync;

  async function execute(sync: boolean, raw: boolean) {
    if (!connection || !statement) return;
    workspace.update({ [slot]: { ...connection, cursor: undefined } });
    const next = sync
      ? {
          sync: true as const,
          result: callWithParams(params, variadic, raw
            ? statement.executeForRawResultSync.bind(statement)
            : statement.executeSync.bind(statement)),
        }
      : {
          sync: false as const,
          result: await callWithParams(params, variadic, raw
            ? statement.executeForRawResultAsync.bind(statement)
            : statement.executeAsync.bind(statement)),
        };
    workspace.update({ [slot]: { ...connection, cursor: next } });
    const { changes, lastInsertRowId } = next.result;
    return { changes, lastInsertRowId };
  }

  return (
    <Panel title="预编译语句与游标">
      <Field
        label="SQL 语句"
        editable={!statement}
        multiline
        onChangeText={setSql}
        value={connection?.statementSource ?? sql}
      />
      <ParameterField onChange={setParams} value={params} />
      <SQLiteSwitch label="逐个传入位置参数" onChange={setVariadic} value={variadic} />
      <SQLiteMode actions={actions} />
      <SQLiteActions
        actions={actions}
        items={[
          actions.variant('prepare', async (sync) => {
            if (!connection) return;
            const prepared = sync ? connection.db.prepareSync(sql) : await connection.db.prepareAsync(sql);
            workspace.update({ [slot]: { ...connection, statement: prepared, statementSource: sql } });
          }, !db || Boolean(statement)),
          actions.variant('getColumnNames', sync => sync ? statement?.getColumnNamesSync() : statement?.getColumnNamesAsync(), !statement),
          actions.variant('execute', sync => execute(sync, false), !statement),
          actions.variant('executeForRawResult', sync => execute(sync, true), !statement),
          actions.variant('游标 getFirst', () => cursor?.sync ? cursor.result.getFirstSync() : cursor?.result.getFirstAsync(), cursorUnavailable),
          actions.variant('游标 getAll', () => cursor?.sync ? cursor.result.getAllSync() : cursor?.result.getAllAsync(), cursorUnavailable),
          ['游标 next', () => cursor?.result.next(), cursorUnavailable],
          actions.variant('游标 reset', () => cursor?.sync ? cursor.result.resetSync() : cursor?.result.resetAsync(), cursorUnavailable),
          actions.variant('finalize', async (sync) => {
            if (!connection || !statement) return;
            try {
              if (sync) statement.finalizeSync();
              else await statement.finalizeAsync();
            } finally {
              workspace.update({
                [slot]: { ...connection, statement: undefined, statementSource: undefined, cursor: undefined },
              });
            }
          }, !statement),
        ]}
      />
    </Panel>
  );
}

export function TaggedQueryDemo({ workspace }: { workspace: Workspace }) {
  const [value, setValue] = useState('你好，SQLite');
  const actions = useSQLiteActions(workspace);
  const db = workspace.connection?.db;
  const query = () => db ? db.sql`SELECT ${value} AS body UNION ALL SELECT '第二行'` : undefined;
  const { sync } = actions;

  return (
    <Panel title="SQL 模板字符串">
      <Field label="插值" onChangeText={setValue} value={value} />
      <SQLiteMode actions={actions} />
      <SQLiteActions
        actions={actions}
        items={[
          [sync ? 'sql.allSync' : 'await sql', () => sync ? query()?.allSync() : query(), !db],
          [sync ? 'sql.firstSync' : 'sql.first', () => sync ? query()?.firstSync() : query()?.first(), !db],
          [sync ? 'sql.valuesSync' : 'sql.values', () => sync ? query()?.valuesSync() : query()?.values(), !db],
          [sync ? 'sql.eachSync' : 'sql.each', () => {
            const result = query();
            if (result) return sync ? Array.from(result.eachSync()) : collect(result.each());
          }, !db],
        ]}
      />
    </Panel>
  );
}

export function TransactionDemo({ workspace }: { workspace: Workspace }) {
  const [sql, setSql] = useState(CREATE_TABLE);
  const [rollback, setRollback] = useState(false);
  const actions = useSQLiteActions(workspace);
  const db = workspace.connection?.db;

  async function transact(kind: 'async' | 'sync' | 'exclusive') {
    if (!db) return;
    const cancel = new Error('取消事务');
    try {
      if (kind === 'sync') {
        db.withTransactionSync(() => {
          db.execSync(sql);
          if (rollback) throw cancel;
        });
      } else {
        const task = async (transaction: SQLite.SQLiteDatabase) => {
          await transaction.execAsync(sql);
          if (rollback) throw cancel;
        };
        if (kind === 'exclusive') await db.withExclusiveTransactionAsync(task);
        else await db.withTransactionAsync(() => task(db));
      }
      return '事务已提交';
    } catch (error) {
      if (error !== cancel) throw error;
      return '事务已回滚';
    }
  }

  return (
    <Panel title="事务">
      <Field label="事务内执行的 SQL" multiline onChangeText={setSql} value={sql} />
      <SQLiteSwitch label="执行后回滚" onChange={setRollback} value={rollback} />
      <SQLiteMode actions={actions} />
      <SQLiteActions
        actions={actions}
        items={[
          actions.variant('withTransaction', sync => transact(sync ? 'sync' : 'async'), !db),
          ['withExclusiveTransactionAsync', () => transact('exclusive'), !db || Platform.OS === 'web'],
          actions.variant('isInTransaction', sync => sync ? db?.isInTransactionSync() : db?.isInTransactionAsync(), !db),
        ]}
      />
    </Panel>
  );
}

function ParameterField({ onChange, value }: { onChange: (value: string) => void; value: string }) {
  return (
    <Field
      label="绑定参数（JSON）"
      multiline
      onChangeText={onChange}
      placeholder='{"$text":"你好","$blob":{"bytes":[0,255],"arrayBuffer":false}}'
      value={value}
    />
  );
}

type BindCall<T> = {
  (params: SQLite.SQLiteBindParams): T;
  (...params: SQLite.SQLiteVariadicBindParams): T;
};

function callWithParams<T>(input: string, variadic: boolean, operation: BindCall<T>): T {
  const parsed: unknown = input.trim() ? JSON.parse(input) : [];
  if (Array.isArray(parsed)) {
    const params = parsed.map(bindValue);
    return variadic ? operation(...params) : operation(params);
  }
  if (!parsed || typeof parsed !== 'object' || variadic) {
    throw new Error(variadic ? '位置参数请填写 JSON 数组。' : '绑定参数请填写 JSON 对象或数组。');
  }
  return operation(Object.fromEntries(Object.entries(parsed).map(([key, value]) => [key, bindValue(value)])));
}

function bindValue(value: unknown): SQLite.SQLiteBindValue {
  if (value === null || typeof value === 'string' || typeof value === 'boolean' || typeof value === 'number') {
    return value;
  }
  if (typeof value === 'object' && value && 'bytes' in value) {
    const bytes = parseBytes(value.bytes);
    return 'arrayBuffer' in value && value.arrayBuffer === true ? bytes.buffer as ArrayBuffer : bytes;
  }
  throw new Error('参数可以是文本、数字、布尔值、null，或包含 bytes 数组的对象。');
}

async function collect<T>(iterator: AsyncIterable<T>): Promise<T[]> {
  const rows: T[] = [];
  for await (const row of iterator) rows.push(row);
  return rows;
}
