/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { fetch } from 'expo/fetch';
import { File, Paths } from 'expo-file-system';
import * as FileSystem from 'expo-file-system/legacy';
import { useEffect, useRef, useState } from 'react';
import { NativeModules } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const endpoints = ['text', 'empty', 'binary', 'limit', 'large', 'stream', 'slow', 'gzip', 'echo'];

export function DevToolsDemo() {
  const result = useAsyncResult();
  const [address, setAddress] = useState(() => {
    const bundle = NativeModules.SourceCode?.scriptURL as string | undefined;
    return bundle?.startsWith('http') ? new URL(bundle).origin : 'http://127.0.0.1:8088';
  });
  const [path, setPath] = useState('text');
  const [method, setMethod] = useState('GET');
  const [headers, setHeaders] = useState('{}');
  const [body, setBody] = useState('Expo Harmony 网络');
  const controller = useRef<AbortController | null>(null);
  const busy = result.state.phase === 'running';

  useEffect(() => () => controller.current?.abort(), []);

  const url = () => new URL(path, new URL('/__devtools__/', address)).href;

  function request() {
    void result.run(async () => {
      const pending = new AbortController();
      controller.current = pending;
      const timer = setTimeout(() => pending.abort(), 20000);

      try {
        const response = await fetch(url(), {
          method,
          headers: JSON.parse(headers),
          body: ['GET', 'HEAD'].includes(method.toUpperCase()) ? undefined : body,
          signal: pending.signal,
        });
        const bytes = new Uint8Array(await response.arrayBuffer());

        return json({
          status: response.status,
          headers: Object.fromEntries(response.headers.entries()),
          size: bytes.byteLength,
          body: response.headers.get('content-type')?.includes('text')
            ? new TextDecoder().decode(bytes.subarray(0, 256))
            : [...bytes.subarray(0, 32)],
        });
      } finally {
        clearTimeout(timer);
        if (controller.current === pending) controller.current = null;
      }
    });
  }

  function transfer(operation: (file: File) => Promise<string>) {
    void result.run(async () => {
      const file = new File(Paths.cache, `devtools-${Date.now()}.bin`);
      try {
        return await operation(file);
      } finally {
        if (file.exists) file.delete();
      }
    });
  }

  return (
    <Panel title="React Native DevTools Network">
      <Field label="Metro 地址" value={address} onChangeText={setAddress} />
      <Field label="响应路径" value={path} onChangeText={setPath} />
      <ActionRow>
        {endpoints.map(endpoint => (
          <ActionButton
            key={endpoint}
            label={endpoint}
            tone={endpoint === path ? 'primary' : 'secondary'}
            onPress={() => {
              setPath(endpoint);
              setMethod(endpoint === 'echo' ? 'POST' : 'GET');
            }}
          />
        ))}
      </ActionRow>
      <Field label="method" value={method} onChangeText={setMethod} />
      <Field label="headers（JSON 对象）" value={headers} onChangeText={setHeaders} />
      <Field label="body" value={body} onChangeText={setBody} multiline />
      <ActionRow>
        <ActionButton label="fetch()" testID="devtools-fetch" disabled={busy} onPress={request} />
        <ActionButton label="取消请求" testID="devtools-cancel" tone="secondary" disabled={!busy || controller.current === null} onPress={() => controller.current?.abort()} />
        <ActionButton
          label="downloadFileAsync()"
          testID="devtools-download"
          disabled={busy}
          onPress={() => transfer(async (file) => {
            const downloaded = await File.downloadFileAsync(url(), file, { headers: JSON.parse(headers) });
            return json({ size: downloaded.size, type: downloaded.type });
          })}
        />
        <ActionButton
          label="uploadAsync()"
          testID="devtools-upload"
          disabled={busy}
          onPress={() => transfer(async (file) => {
            file.write(body);
            return json(await FileSystem.uploadAsync(url(), file.uri, {
              httpMethod: method === 'PUT' || method === 'PATCH' ? method : 'POST',
              headers: JSON.parse(headers),
              uploadType: FileSystem.FileSystemUploadType.BINARY_CONTENT,
            }));
          })}
        />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}
