/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { SQLiteStorage } from 'expo-sqlite/kv-store';
import { useEffect, useState } from 'react';

import { Field, Panel } from '../../ui';
import { SQLiteActions, SQLiteMode, SQLiteSwitch, useSQLiteActions } from './workspace';

const KEY_PREFIX = 'expo-harmony-demo.sqlite.';
const VALUE = '{"body":"你好，SQLite"}';

export function KeyValueDemo() {
  const [databaseName, setDatabaseName] = useState('notes');
  const [storage, setStorage] = useState(() => new SQLiteStorage('expo-harmony-demo-kv-notes.db'));
  const [key, setKey] = useState('note');
  const [value, setValue] = useState(VALUE);
  const [index, setIndex] = useState('0');
  const [append, setAppend] = useState(false);
  const [keys, setKeys] = useState('["note"]');
  const [pairs, setPairs] = useState(() => JSON.stringify([['note', VALUE]]));
  const actions = useSQLiteActions();
  const compatibility = useSQLiteActions();
  const direct = { ...actions, busy: actions.busy || compatibility.busy };
  const nextValue = append ? (previous: string | null) => (previous ?? '') + value : value;
  const { settle } = actions;
  const { settle: settleCompatibility } = compatibility;

  useEffect(() => () => {
    void Promise.allSettled([settle(), settleCompatibility()])
      .then(() => storage.closeAsync())
      .catch(() => undefined);
  }, [settle, settleCompatibility, storage]);

  return (
    <>
      <Panel title="SQLite 键值存储">
        <Field label="存储名称" onChangeText={setDatabaseName} value={databaseName} />
        <Field label="键" onChangeText={setKey} value={key} />
        <Field label="值" multiline onChangeText={setValue} value={value} />
        <Field keyboardType="numeric" label="键索引" onChangeText={setIndex} value={index} />
        <SQLiteSwitch label="在原值后追加" onChange={setAppend} value={append} />
        <SQLiteMode actions={direct} />
        <SQLiteActions
          actions={direct}
          items={[
            ['new SQLiteStorage', async () => {
              const name = databaseName.trim();
              if (!/^[\p{L}\p{N}_-]+$/u.test(name)) throw new Error('存储名称可使用字母、数字、下划线和连字符。');
              const path = `expo-harmony-demo-kv-${name}.db`;
              await storage.closeAsync();
              setStorage(new SQLiteStorage(path));
              return path;
            }, !databaseName.trim()],
            actions.variant('getItem', sync => sync ? storage.getItemSync(key) : storage.getItemAsync(key)),
            actions.variant('setItem', sync => sync ? storage.setItemSync(key, nextValue) : storage.setItemAsync(key, nextValue)),
            actions.variant('removeItem', sync => sync ? storage.removeItemSync(key) : storage.removeItemAsync(key)),
            actions.variant('getAllKeys', sync => sync ? storage.getAllKeysSync() : storage.getAllKeysAsync()),
            actions.variant('getLength', sync => sync ? storage.getLengthSync() : storage.getLengthAsync()),
            actions.variant('getKeyByIndex', sync => sync
              ? storage.getKeyByIndexSync(Number(index))
              : storage.getKeyByIndexAsync(Number(index))),
            actions.variant('clear', sync => sync ? storage.clearSync() : storage.clearAsync()),
            actions.variant('close', sync => sync ? storage.closeSync() : storage.closeAsync()),
          ]}
        />
      </Panel>
      <Panel title="AsyncStorage 接口">
        <Field label="键" onChangeText={setKey} value={key} />
        <Field label="值" multiline onChangeText={setValue} value={value} />
        <Field label="键列表（JSON）" multiline onChangeText={setKeys} value={keys} />
        <Field label="键值对列表（JSON）" multiline onChangeText={setPairs} value={pairs} />
        <SQLiteActions
          actions={compatibility}
          items={[
            ['getItem', () => storage.getItem(key), actions.busy],
            ['setItem', () => storage.setItem(key, nextValue), actions.busy],
            ['removeItem', () => storage.removeItem(key), actions.busy],
            ['getAllKeys', () => storage.getAllKeys(), actions.busy],
            ['mergeItem', () => storage.mergeItem(key, value), actions.busy],
            ['multiGet', () => storage.multiGet(parseKeys(keys)), actions.busy],
            ['multiSet', () => storage.multiSet(parsePairs(pairs)), actions.busy],
            ['multiRemove', () => storage.multiRemove(parseKeys(keys)), actions.busy],
            ['multiMerge', () => storage.multiMerge(parsePairs(pairs)), actions.busy],
            ['clear', () => storage.clear(), actions.busy],
            ['close', () => storage.close(), actions.busy],
          ]}
        />
      </Panel>
    </>
  );
}

export function LocalStorageDemo() {
  const [key, setKey] = useState('note');
  const [value, setValue] = useState('你好，SQLite');
  const [index, setIndex] = useState('0');
  const [installed, setInstalled] = useState(false);
  const actions = useSQLiteActions();
  const demoKey = KEY_PREFIX + key;

  return (
    <Panel title="localStorage">
      <Field label="键" onChangeText={setKey} value={key} />
      <Field label="值" onChangeText={setValue} value={value} />
      <Field keyboardType="numeric" label="键索引" onChangeText={setIndex} value={index} />
      <SQLiteActions
        actions={actions}
        items={[
          ['安装 localStorage', async () => {
            await import('expo-sqlite/localStorage/install');
            setInstalled(true);
            return String(globalThis.localStorage);
          }, installed],
          ['getItem', () => globalThis.localStorage.getItem(demoKey), !installed],
          ['setItem', () => globalThis.localStorage.setItem(demoKey, value), !installed],
          ['removeItem', () => globalThis.localStorage.removeItem(demoKey), !installed],
          ['key', () => globalThis.localStorage.key(Number(index)), !installed],
          ['length', () => globalThis.localStorage.length, !installed],
          ['clear', () => {
            const storage = globalThis.localStorage;
            for (let i = 0; i < storage.length; i++) {
              if (!storage.key(i)?.startsWith(KEY_PREFIX)) {
                throw new Error('清空会移除其他页面的数据，请按键删除本页的数据。');
              }
            }
            storage.clear();
          }, !installed],
        ]}
      />
    </Panel>
  );
}

function parseKeys(input: string): string[] {
  const parsed: unknown = JSON.parse(input);
  if (!Array.isArray(parsed) || parsed.some(key => typeof key !== 'string')) {
    throw new Error('请填写 JSON 字符串数组。');
  }
  return parsed;
}

function parsePairs(input: string): [string, string][] {
  const parsed: unknown = JSON.parse(input);
  if (!Array.isArray(parsed) || parsed.some(pair =>
    !Array.isArray(pair) || pair.length !== 2 || pair.some(value => typeof value !== 'string')
  )) {
    throw new Error('每一组请填写键和值，两个都用字符串。');
  }
  return parsed;
}
