/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Directory, File, Paths } from 'expo-file-system';
import { useState } from 'react';
import { Platform } from 'react-native';

import { ActionRow, Field, Panel } from '../../ui';
import { childName, FileActions, localDirectory, sandbox, Toggle, WatchDemo } from './shared';

export function FileSystemDirectoryDemo() {
  const [path, setPath] = useState('documents');
  const [destination, setDestination] = useState('documents-copy');
  const [newName, setNewName] = useState('renamed');
  const [entryName, setEntryName] = useState('sample.txt');
  const [mimeType, setMimeType] = useState('text/plain');
  const [intermediates, setIntermediates] = useState(true);
  const [overwrite, setOverwrite] = useState(false);
  const [idempotent, setIdempotent] = useState(false);
  const [first, setFirst] = useState('documents');
  const [second, setSecond] = useState('documents/sample.txt');
  const [extension, setExtension] = useState('.txt');

  const directory = () => localDirectory(path);
  const target = () => localDirectory(destination);
  const move = async (sync: boolean) => {
    const value = directory();
    if (sync) value.moveSync(target(), { overwrite });
    else await value.move(target(), { overwrite });
    setPath(decodeURIComponent(Paths.relative(sandbox().uri, value.uri)));
    return value.uri;
  };

  return (
    <>
      <Panel title="目录">
        <Field label="缓存中的相对路径" onChangeText={setPath} value={path} />
        <ActionRow>
          <Toggle label="intermediates" value={intermediates} onChange={setIntermediates} />
          <Toggle label="overwrite" value={overwrite} onChange={setOverwrite} />
          <Toggle label="idempotent" value={idempotent} onChange={setIdempotent} />
        </ActionRow>
        <FileActions actions={[
          ['create()', () => {
            const value = directory();
            value.create({ intermediates, overwrite, idempotent });
            return value.uri;
          }],
          ['delete()', () => directory().delete()],
          ['info()', () => directory().info()],
          ['list()', () => directory().list().map(value => value.uri)],
          ['目录属性', () => {
            const { uri, exists, name, size, parentDirectory } = directory();
            return { uri, exists, name, size, parentDirectory: parentDirectory.uri };
          }],
        ]}
        />
      </Panel>
      <Panel title="新建子项">
        <Field label="子项名称" onChangeText={setEntryName} value={entryName} />
        <Field label="文件 MIME 类型" onChangeText={setMimeType} value={mimeType} />
        <FileActions actions={[
          ['createFile()', () => directory().createFile(childName(entryName), mimeType || null).uri],
          ['createDirectory()', () => directory().createDirectory(childName(entryName)).uri],
        ]}
        />
      </Panel>
      <Panel title="复制、移动和改名">
        <Field label="目标相对路径" onChangeText={setDestination} value={destination} />
        <Field label="新目录名" onChangeText={setNewName} value={newName} />
        <Toggle label="overwrite" value={overwrite} onChange={setOverwrite} />
        <FileActions actions={[
          ['copy()', () => directory().copy(target(), { overwrite })],
          ['copySync()', () => directory().copySync(target(), { overwrite })],
          ['move()', () => move(false)],
          ['moveSync()', () => move(true)],
          ['rename()', () => {
            const value = directory();
            value.rename(childName(newName));
            setPath(decodeURIComponent(Paths.relative(sandbox().uri, value.uri)));
            return value.uri;
          }],
        ]}
        />
      </Panel>
      <WatchDemo watch={(callback, options) => directory().watch(callback, options)} />
      <Panel title="内置目录与磁盘空间">
        <FileActions actions={[
          ['Paths.cache', () => Paths.cache.uri],
          ['Paths.bundle', () => Paths.bundle.uri],
          ['Paths.document', () => Paths.document.uri],
          ['Paths.appleSharedContainers', () => Object.fromEntries(Object.entries(Paths.appleSharedContainers).map(([key, value]) => [key, value.uri])), Platform.OS !== 'ios'],
          ['Paths.totalDiskSpace', () => Paths.totalDiskSpace],
          ['Paths.availableDiskSpace', () => Paths.availableDiskSpace],
        ]}
        />
      </Panel>
      {String(Platform.OS) === 'harmony' ? <BundledDirectory /> : null}
      <Panel title="路径工具">
        <Field label="路径 1" onChangeText={setFirst} value={first} />
        <Field label="路径 2" onChangeText={setSecond} value={second} />
        <Field label="basename 忽略的后缀" onChangeText={setExtension} value={extension} />
        <FileActions actions={[
          ['info()', () => Paths.info(sandbox().uri, first, second)],
          ['join()', () => Paths.join(first, second)],
          ['relative()', () => Paths.relative(first, second)],
          ['isAbsolute()', () => Paths.isAbsolute(second)],
          ['normalize()', () => Paths.normalize(second)],
          ['dirname()', () => Paths.dirname(second)],
          ['basename()', () => Paths.basename(second, extension || undefined)],
          ['extname()', () => Paths.extname(second)],
          ['parse()', () => Paths.parse(second)],
        ]}
        />
      </Panel>
    </>
  );
}

function BundledDirectory() {
  const [uri, setUri] = useState('asset:///audio');
  const [entryName, setEntryName] = useState('probe.wav');
  const directory = () => {
    if (!/^(asset|rawfile|resource):\/\//.test(uri)) throw new Error('请输入应用资源 URI。');
    return new Directory(uri);
  };
  return (
    <Panel title="应用资源目录">
      <Field label="资源目录 URI" onChangeText={setUri} value={uri} />
      <Field label="资源文件名" onChangeText={setEntryName} value={entryName} />
      <FileActions actions={[
        ['info()', () => directory().info()],
        ['list()', () => directory().list().map(entry => entry.uri)],
        ['bytes()', async () => {
          const bytes = await new File(directory(), childName(entryName)).bytes();
          return { byteLength: bytes.length, bytes: Array.from(bytes.subarray(0, 32)) };
        }],
      ]}
      />
    </Panel>
  );
}
