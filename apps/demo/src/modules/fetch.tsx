/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { fetch as expoFetch, type FetchRequestInit } from 'expo/fetch';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

type FetchResponse = Awaited<ReturnType<typeof expoFetch>>;
const bodyTypes = ['无请求体', '文本', 'URLSearchParams', 'FormData', 'Blob', 'ArrayBuffer', 'Uint8Array', 'ReadableStream'] as const;
type BodyType = typeof bodyTypes[number];
const inputTypes = ['URL 字符串', 'URL 对象', 'RequestLike'] as const;
const responseModes = ['text()', 'json()', 'bytes()', 'arrayBuffer()', 'blob()', 'formData()', '读取首块'] as const;

function makeBody(type: BodyType, value: string): BodyInit | undefined {
  const bytes = new TextEncoder().encode(value);
  switch (type) {
    case '无请求体': return undefined;
    case '文本': return value;
    case 'URLSearchParams': return new URLSearchParams(value);
    case 'FormData': {
      const form = new FormData();
      new URLSearchParams(value).forEach((content, key) => form.append(key, content));
      return form;
    }
    case 'Blob': return new Blob([value], { type: 'text/plain' });
    case 'ArrayBuffer': return bytes.buffer;
    case 'Uint8Array': return bytes;
    case 'ReadableStream': return new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(bytes);
        controller.close();
      },
    });
  }
}

function responseInfo(response: FetchResponse) {
  const headers: Record<string, string> = {};
  response.headers.forEach((value, key) => {
    headers[key] = value;
  });
  const { status, statusText, ok, url, redirected, type, bodyUsed } = response;
  return { status, statusText, ok, url, redirected, type, bodyUsed, headers };
}

function formParts(form: FormData) {
  if ('getParts' in form && typeof form.getParts === 'function') return form.getParts();
  const parts: [string, unknown][] = [];
  if ('forEach' in form && typeof form.forEach === 'function') {
    form.forEach((value: unknown, key: string) => parts.push([key, value]));
  }
  return parts;
}

async function readResponse(response: FetchResponse, mode: typeof responseModes[number]): Promise<string> {
  switch (mode) {
    case 'text()': return (await response.text()).slice(0, 4096);
    case 'json()': return json(await response.json()).slice(0, 4096);
    case 'bytes()': {
      const bytes = typeof response.bytes === 'function' ? await response.bytes() : new Uint8Array(await response.arrayBuffer());
      return json({ size: bytes.length, bytes: Array.from(bytes.slice(0, 128)) });
    }
    case 'arrayBuffer()': {
      const buffer = await response.arrayBuffer();
      return json({ byteLength: buffer.byteLength, bytes: Array.from(new Uint8Array(buffer).slice(0, 128)) });
    }
    case 'blob()': {
      const blob = await response.blob();
      return json({ size: blob.size, type: blob.type });
    }
    case 'formData()': return json(formParts(await response.formData()));
    case '读取首块': {
      if (!response.body) return json(null);
      const reader = response.body.getReader();
      try {
        const { value, done } = await reader.read();
        return json({
          done,
          bytes: value?.length,
          text: value ? new TextDecoder().decode(value.slice(0, 4096)) : undefined,
        });
      } finally {
        void reader.cancel().catch(() => undefined);
        reader.releaseLock();
      }
    }
  }
}

export function FetchDemo() {
  const request = useAsyncResult();
  const read = useAsyncResult();
  const [url, setUrl] = useState('https://example.com/');
  const [method, setMethod] = useState('GET');
  const [headers, setHeaders] = useState('{}');
  const [body, setBody] = useState('message=hello');
  const [bodyType, setBodyType] = useState<BodyType>('文本');
  const [input, setInput] = useState<typeof inputTypes[number]>('URL 字符串');
  const [credentials, setCredentials] = useState<FetchRequestInit['credentials']>('include');
  const [redirect, setRedirect] = useState<FetchRequestInit['redirect']>('follow');
  const [webOptions, setWebOptions] = useState('{}');
  const [response, setResponse] = useState<FetchResponse>();
  const [copy, setCopy] = useState<FetchResponse>();
  const [useCopy, setUseCopy] = useState(false);
  const controller = useRef<AbortController | null>(null);
  const isSending = request.state.phase === 'running';
  const isReading = read.state.phase === 'running';
  const activeResponse = useCopy ? copy : response;
  const sendBody = !['GET', 'HEAD'].includes(method.toUpperCase());
  const web = Platform.OS === 'web';

  useEffect(() => () => controller.current?.abort(), []);

  const send = () => request.run(async () => {
    controller.current?.abort();
    setResponse(undefined);
    setCopy(undefined);
    setUseCopy(false);
    read.clear();
    const nextController = new AbortController();
    controller.current = nextController;
    const init: FetchRequestInit = {
      ...(web ? JSON.parse(webOptions) as Pick<FetchRequestInit, 'integrity' | 'keepalive' | 'mode' | 'referrer' | 'window'> : {}),
      method,
      credentials,
      redirect,
      headers: JSON.parse(headers) as FetchRequestInit['headers'],
      body: sendBody ? makeBody(bodyType, body) : undefined,
      signal: nextController.signal,
    };
    const address = url.trim();
    const webInit = { ...init, duplex: 'half' };
    const value = input === 'RequestLike'
      ? await expoFetch(web
          ? new Request(address, webInit as RequestInit)
          : {
              url: address, body: init.body ?? null, method, headers: new Headers(init.headers),
              credentials, signal: nextController.signal, redirect,
            })
      : await expoFetch(input === 'URL 对象' ? new URL(address) : address, web ? webInit : init);
    setResponse(value);
    return json(responseInfo(value));
  });

  return (
    <>
      <Panel title="HTTP 请求">
        <Field label="URL" onChangeText={setUrl} value={url} />
        <Field label="HTTP 方法" onChangeText={setMethod} value={method} />
        <ActionRow>
          {inputTypes.map(value => <ActionButton key={value} label={value} onPress={() => setInput(value)} tone={input === value ? 'primary' : 'secondary'} />)}
        </ActionRow>
        <Field label="请求头 JSON" multiline onChangeText={setHeaders} value={headers} />
        <ActionRow>
          {(['include', 'omit', 'same-origin'] as const).map(value => (
            <ActionButton key={value} label={`credentials ${value}`} onPress={() => setCredentials(value)} tone={credentials === value ? 'primary' : 'secondary'} />
          ))}
        </ActionRow>
        <ActionRow>
          {(['follow', 'manual', 'error'] as const).map(value => (
            <ActionButton key={value} label={`redirect ${value}`} onPress={() => setRedirect(value)} tone={redirect === value ? 'primary' : 'secondary'} />
          ))}
        </ActionRow>
        {web ? <Field label="Web 选项 JSON" multiline placeholder={'{"mode":"cors","keepalive":false,"referrer":"","integrity":"","window":null}'} onChangeText={setWebOptions} value={webOptions} /> : null}
        {sendBody
          ? (
              <>
                <ActionRow>
                  {bodyTypes.map(value => <ActionButton key={value} label={value} onPress={() => setBodyType(value)} tone={bodyType === value ? 'primary' : 'secondary'} />)}
                </ActionRow>
                {bodyType !== '无请求体' ? <Field label="请求体" multiline onChangeText={setBody} value={body} /> : null}
              </>
            )
          : null}
        <ActionRow>
          <ActionButton disabled={isSending || isReading || !url.trim()} label="fetch()" onPress={() => void send()} />
          <ActionButton disabled={!isSending && !isReading && !response} label="AbortController.abort()" onPress={() => controller.current?.abort()} tone="danger" />
        </ActionRow>
        <ResultPanel state={request.state} />
      </Panel>
      <Panel title="HTTP 响应">
        <ActionRow>
          <ActionButton
            disabled={!response || !!copy || response.bodyUsed || isReading || isSending}
            label="clone()"
            onPress={() => response && void read.run(() => {
              const value = response.clone();
              setCopy(value);
              return json(responseInfo(value));
            })}
          />
          <ActionButton disabled={!copy || isReading} label={useCopy ? '读取原响应' : '读取副本'} onPress={() => setUseCopy(value => !value)} tone="secondary" />
          <ActionButton disabled={!activeResponse || isReading} label="响应属性" onPress={() => activeResponse && void read.run(() => json(responseInfo(activeResponse)))} tone="secondary" />
          {!web ? <ActionButton disabled={!activeResponse} label="response.abort()" onPress={() => activeResponse?.abort()} tone="danger" /> : null}
        </ActionRow>
        <ActionRow>
          {responseModes.map(value => (
            <ActionButton
              key={value}
              disabled={!activeResponse || activeResponse.bodyUsed || isReading || isSending}
              label={value}
              onPress={() => activeResponse && void read.run(() => readResponse(activeResponse, value))}
            />
          ))}
        </ActionRow>
        <ResultPanel state={read.state} />
      </Panel>
    </>
  );
}
