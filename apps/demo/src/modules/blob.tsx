/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { Blob } from 'expo-blob';
import { useState } from 'react';

import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const partTypes = {
  文本: (input: string) => input.replaceAll('\\r', '\r').replaceAll('\\n', '\n'),
  ArrayBuffer: (input: string) => new TextEncoder().encode(input).buffer,
  Uint8Array: (input: string) => new TextEncoder().encode(input),
  DataView: (input: string) => new DataView(new TextEncoder().encode(input).buffer),
  Blob: (input: string) => new Blob([input]),
};

export function BlobDemo() {
  const [input, setInput] = useState('Hello 世界');
  const [extraPart, setExtraPart] = useState('');
  const [partType, setPartType] = useState<keyof typeof partTypes>('文本');
  const [type, setType] = useState('TEXT/PLAIN');
  const [endings, setEndings] = useState<EndingType>('transparent');
  const [blob, setBlob] = useState<Blob>();
  const [start, setStart] = useState('0');
  const [end, setEnd] = useState('5');
  const [sliceType, setSliceType] = useState('text/plain');
  const [chunkSize, setChunkSize] = useState('4');
  const create = useAsyncResult();
  const read = useAsyncResult();
  const slice = useAsyncResult();
  const stream = useAsyncResult();

  const construct = (empty: boolean) => create.run(() => {
    const parts = [partTypes[partType](input)];
    if (extraPart) parts.push(extraPart);
    const value = empty ? new Blob() : new Blob(parts, { type, endings });
    setBlob(value);
    return json({ size: value.size, type: value.type });
  });

  const readStream = (byob: boolean) => stream.run(async () => {
    if (!blob) return '';
    const source = blob.stream();
    const reader = byob ? source.getReader({ mode: 'byob' }) : source.getReader();
    try {
      const length = Number(chunkSize);
      if (byob && (!Number.isInteger(length) || length < 1 || length > 65536)) {
        throw new Error('缓冲区大小须为 1 到 65536 字节。');
      }
      const result = byob
        ? await (reader as ReadableStreamBYOBReader).read(new Uint8Array(length))
        : await (reader as ReadableStreamDefaultReader<Uint8Array>).read();
      return json({ done: result.done, bytes: Array.from(result.value ?? []) });
    } finally {
      try {
        await reader.cancel();
      } finally {
        reader.releaseLock();
      }
    }
  });

  return (
    <>
      <Panel title="创建 Blob">
        <ActionRow>
          {(Object.keys(partTypes) as (keyof typeof partTypes)[]).map(value => (
            <ActionButton key={value} label={value} onPress={() => setPartType(value)} tone={partType === value ? 'primary' : 'secondary'} />
          ))}
        </ActionRow>
        <Field label="内容" multiline onChangeText={setInput} value={input} />
        <Field label="附加文本片段" onChangeText={setExtraPart} value={extraPart} />
        <Field label="MIME 类型" onChangeText={setType} value={type} />
        <ActionRow>
          {(['transparent', 'native'] as const).map(value => (
            <ActionButton key={value} label={`endings ${value}`} onPress={() => setEndings(value)} tone={endings === value ? 'primary' : 'secondary'} />
          ))}
        </ActionRow>
        <ActionRow>
          <ActionButton label="创建 Blob" onPress={() => void construct(false)} testID="blob-create" />
          <ActionButton label="创建空 Blob" onPress={() => void construct(true)} tone="secondary" />
        </ActionRow>
        <ResultPanel state={create.state} />
      </Panel>

      <Panel title="读取 Blob">
        <ActionRow>
          <ActionButton disabled={!blob} label="text()" onPress={() => blob && void read.run(async () => json(await blob.text()))} />
          <ActionButton disabled={!blob} label="bytes()" onPress={() => blob && void read.run(async () => json(Array.from(await blob.bytes())))} />
          <ActionButton disabled={!blob} label="arrayBuffer()" onPress={() => blob && void read.run(async () => json(Array.from(new Uint8Array(await blob.arrayBuffer()))))} />
        </ActionRow>
        <ResultPanel state={read.state} />
      </Panel>

      <Panel title="Blob 切片">
        <Field keyboardType="numbers-and-punctuation" label="起始字节" onChangeText={setStart} value={start} />
        <Field keyboardType="numbers-and-punctuation" label="结束字节" onChangeText={setEnd} value={end} />
        <Field label="切片 MIME 类型" onChangeText={setSliceType} value={sliceType} />
        <ActionButton
          disabled={!blob}
          label="slice()"
          onPress={() => blob && void slice.run(async () => {
            const value = blob.slice(
              start.trim() ? Number(start) : undefined,
              end.trim() ? Number(end) : undefined,
              sliceType || undefined
            );
            return json({ size: value.size, type: value.type, text: await value.text() });
          })}
        />
        <ResultPanel state={slice.state} />
      </Panel>

      <Panel title="流式读取首块">
        <Field keyboardType="number-pad" label="BYOB 缓冲区字节数" onChangeText={setChunkSize} value={chunkSize} />
        <ActionRow>
          <ActionButton disabled={!blob || stream.state.phase === 'running'} label="默认读取器" onPress={() => void readStream(false)} />
          <ActionButton disabled={!blob || stream.state.phase === 'running'} label="BYOB 读取器" onPress={() => void readStream(true)} tone="secondary" />
        </ActionRow>
        <ResultPanel state={stream.state} />
      </Panel>
    </>
  );
}
