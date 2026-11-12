/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { FileMode, Paths, type FileHandle } from 'expo-file-system';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { ActionRow, Field, Panel } from '../../ui';
import { childName, FileActions, firstChunk, localDirectory, localFile, sandbox, Toggle, WatchDemo } from './shared';

const platform = String(Platform.OS);

function previewBytes(bytes: Uint8Array) {
  return { byteLength: bytes.length, bytes: Array.from(bytes.subarray(0, 128)) };
}

export function FileSystemFileDemo() {
  const [path, setPath] = useState('sample.txt');
  const [destination, setDestination] = useState('copy.txt');
  const [directoryDestination, setDirectoryDestination] = useState(false);
  const [newName, setNewName] = useState('renamed.txt');
  const [intermediates, setIntermediates] = useState(true);
  const [overwrite, setOverwrite] = useState(false);
  const [append, setAppend] = useState(false);
  const [base64, setBase64] = useState(false);
  const [md5, setMD5] = useState(false);
  const [text, setText] = useState('你好，文件系统');
  const [start, setStart] = useState('0');
  const [end, setEnd] = useState('6');
  const [type, setType] = useState('text/plain');

  const file = () => localFile(path);
  const target = () => directoryDestination ? localDirectory(destination) : localFile(destination);
  const move = async (sync: boolean) => {
    const source = file();
    if (sync) source.moveSync(target(), { overwrite });
    else await source.move(target(), { overwrite });
    setPath(decodeURIComponent(Paths.relative(sandbox().uri, source.uri)));
    return source.uri;
  };

  return (
    <>
      <Panel title="文件路径">
        <Field label="缓存中的相对路径" onChangeText={setPath} value={path} />
        <ActionRow>
          <Toggle label="intermediates" value={intermediates} onChange={setIntermediates} />
          <Toggle label="overwrite" value={overwrite} onChange={setOverwrite} />
          <Toggle label="info 的 md5" value={md5} onChange={setMD5} />
        </ActionRow>
        <FileActions actions={[
          ['create()', () => {
            const value = file();
            value.create({ intermediates, overwrite });
            return value.uri;
          }],
          ['delete()', () => file().delete()],
          ['info()', () => file().info({ md5 })],
          ['文件属性', () => {
            const {
              uri, exists, size, name, extension, parentDirectory,
              type, lastModified, modificationTime, creationTime, md5,
            } = file();
            return {
              uri, exists, size, name, extension, parentDirectory: parentDirectory.uri,
              type, lastModified, modificationTime, creationTime, md5,
            };
          }],
          ['contentUri', () => file().contentUri, platform !== 'harmony' && platform !== 'android'],
        ]}
        />
      </Panel>

      <Panel title="读写文件">
        <Field label="写入内容" multiline onChangeText={setText} value={text} />
        <ActionRow>
          <Toggle label="append" value={append} onChange={setAppend} />
          <Toggle label={base64 ? 'encoding base64' : 'encoding utf8'} value={base64} onChange={setBase64} />
        </ActionRow>
        <FileActions actions={[
          ['write() 字符串', () => file().write(text, { encoding: base64 ? 'base64' : 'utf8', append })],
          ['write() 字节', () => file().write(new TextEncoder().encode(text), { append })],
          ['text()', async () => (await file().text()).slice(0, 4096)],
          ['textSync()', () => file().textSync().slice(0, 4096)],
          ['base64()', async () => (await file().base64()).slice(0, 4096)],
          ['base64Sync()', () => file().base64Sync().slice(0, 4096)],
          ['bytes()', async () => previewBytes(await file().bytes())],
          ['bytesSync()', () => previewBytes(file().bytesSync())],
          ['arrayBuffer()', async () => previewBytes(new Uint8Array(await file().arrayBuffer()))],
          ['json()', async () => JSON.stringify(await file().json()).slice(0, 4096)],
          ['formData()', async () => {
            const form = await file().formData();
            if ('getParts' in form && typeof form.getParts === 'function') return form.getParts();
            if ('entries' in form && typeof form.entries === 'function') return Array.from(form.entries());
            return form;
          }],
        ]}
        />
      </Panel>

      <Panel title="文件切片">
        <Field label="起始字节" onChangeText={setStart} value={start} />
        <Field label="结束字节" onChangeText={setEnd} value={end} />
        <Field label="MIME 类型" onChangeText={setType} value={type} />
        <FileActions actions={[
          ['slice()', async () => {
            const value = file().slice(
              start ? Number(start) : undefined,
              end ? Number(end) : undefined,
              type || undefined
            );
            return { size: value.size, type: value.type, text: (await value.text()).slice(0, 4096) };
          }],
        ]}
        />
      </Panel>

      <Panel title="文件流">
        <Field label="写入内容" multiline onChangeText={setText} value={text} />
        <FileActions actions={[
          ['readableStream() 首块', () => firstChunk(file().readableStream())],
          ['stream() 首块', () => firstChunk(file().stream())],
          ['writableStream()', async () => {
            const writer = file().writableStream().getWriter();
            try {
              await writer.write(new TextEncoder().encode(text));
              await writer.close();
            } catch (error) {
              await writer.abort(error).catch(() => undefined);
              throw error;
            } finally {
              writer.releaseLock();
            }
          }],
        ]}
        />
      </Panel>

      <Panel title="复制、移动和改名">
        <Field label="目标相对路径" onChangeText={setDestination} value={destination} />
        <Toggle label="目标为目录" value={directoryDestination} onChange={setDirectoryDestination} />
        <Toggle label="overwrite" value={overwrite} onChange={setOverwrite} />
        <Field label="新文件名" onChangeText={setNewName} value={newName} />
        <FileActions actions={[
          ['copy()', () => file().copy(target(), { overwrite })],
          ['copySync()', () => file().copySync(target(), { overwrite })],
          ['move()', () => move(false)],
          ['moveSync()', () => move(true)],
          ['rename()', () => {
            const source = file();
            source.rename(childName(newName));
            setPath(decodeURIComponent(Paths.relative(sandbox().uri, source.uri)));
            return source.uri;
          }],
        ]}
        />
      </Panel>

      <HandleDemo path={path} />
      <WatchDemo watch={(callback, options) => file().watch(callback, options)} />
    </>
  );
}

function HandleDemo({ path }: { path: string }) {
  const handle = useRef<FileHandle | null>(null);
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<FileMode>(FileMode.ReadWrite);
  const [offset, setOffset] = useState('0');
  const [length, setLength] = useState('8');
  const [text, setText] = useState('Hello');
  useEffect(() => () => handle.current?.close(), []);

  return (
    <Panel title="文件句柄">
      <ActionRow>
        {Object.values(FileMode).map(value => (
          <Toggle key={value} label={value} value={mode === value} onChange={() => setMode(value)} />
        ))}
      </ActionRow>
      <Field label="偏移字节数" keyboardType="number-pad" onChangeText={setOffset} value={offset} />
      <Field label="读取字节数" keyboardType="number-pad" onChangeText={setLength} value={length} />
      <Field label="写入内容" onChangeText={setText} value={text} />
      <FileActions actions={[
        ['open()', () => {
          handle.current = localFile(path).open(mode);
          setOpen(true);
          return { path, mode, offset: handle.current.offset, size: handle.current.size };
        }, open],
        ['offset / size', () => ({ offset: handle.current?.offset, size: handle.current?.size }), !open],
        ['设置 offset', () => {
          if (handle.current) handle.current.offset = Number(offset);
        }, !open],
        ['readBytes()', () => previewBytes(handle.current?.readBytes(Number(length)) ?? new Uint8Array()), !open],
        ['writeBytes()', () => handle.current?.writeBytes(new TextEncoder().encode(text)), !open],
        ['close()', () => {
          handle.current?.close();
          handle.current = null;
          setOpen(false);
        }, !open],
      ]}
      />
    </Panel>
  );
}
