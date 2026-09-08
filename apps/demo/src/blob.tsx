import { Blob } from 'expo-blob';
import { useState } from 'react';

import { ActionButton, DataRow, Field, Note, Panel, ResultPanel, useAsyncResult } from './ui';

async function binary() {
  const views = [
    new Int8Array([-1, 0, 1]), new Uint8Array([0, 128, 255]),
    new Int16Array([-32768, 0, 32767]), new Uint16Array([0, 65535, 42]),
    new Int32Array([-2147483648, 0, 2147483647]), new Uint32Array([0, 4294967295, 42]),
    new Float32Array([1.5, -2.25, 0]), new Float64Array([Math.PI, -0, Infinity]),
    new BigInt64Array([-1n, 0n, 1n]), new BigUint64Array([0n, 1n, 2n]),
  ];
  const rows: string[] = [];

  for (const source of views) {
    const view = source.subarray(1);
    const expected = new Uint8Array(new Uint8Array(view.buffer, view.byteOffset, view.byteLength));
    const blob = new Blob([view]);
    new Uint8Array(source.buffer).fill(0);

    const bytes = await blob.bytes();
    if (blob.size !== expected.length || bytes.length !== expected.length
      || bytes.some((value, index) => value !== expected[index])) {
      throw new Error(`${source.constructor.name} 的偏移范围或输入快照不正确。`);
    }

    bytes.fill(0);
    const [first, second] = await Promise.all([blob.arrayBuffer(), blob.arrayBuffer()]);
    if (first === second || new Uint8Array(first).some((value, index) => value !== expected[index])) {
      throw new Error(`${source.constructor.name} 的读取结果未隔离。`);
    }

    rows.push(`${source.constructor.name}：通过`);
  }

  const source = new Uint8Array([0, 127, 255]);
  const blob = new Blob([source.buffer]);
  source.fill(0);
  const bytes = await blob.bytes();
  if (bytes.join(',') !== '0,127,255') throw new Error('ArrayBuffer 输入未保存快照。');

  return `${rows.join('\n')}\nArrayBuffer 输入与并发读取：通过`;
}

async function slices() {
  const blob = new Blob(['ab', new Blob(['cde']), new Uint8Array([102, 103]), 'h'], { type: 'TEXT/PLAIN' });
  const cases: [number | undefined, number | undefined, string][] = [
    [undefined, undefined, 'abcdefgh'], [1, 7, 'bcdefg'], [-3, -1, 'fg'],
    [-100, 100, 'abcdefgh'], [7, 2, ''], [100, undefined, ''], [1.9, 5.9, 'bcde'],
  ];

  for (const [start, end, expected] of cases) {
    const slice = blob.slice(start, end);
    const text = await slice.text();
    if (!(slice instanceof Blob) || slice.size !== expected.length || slice.type !== '' || text !== expected) {
      throw new Error(`slice(${start}, ${end}) 不符：${JSON.stringify({ text, size: slice.size, type: slice.type })}`);
    }
  }

  const typed = blob.slice(1, 5, 'TEXT/HTML');
  const nested = new Blob([typed.slice(1, 3), typed]);
  if (typed.type !== 'text/html' || await nested.text() !== 'cdbcde') {
    throw new Error('切片类型或嵌套切片内容不正确。');
  }
  if (blob.type !== 'text/plain' || new Blob([], { type: 'text/中文' }).type !== '') {
    throw new Error('MIME 类型规范化不正确。');
  }

  const large = new Blob([new Uint8Array(1024 * 1024).fill(97)]);
  const tiny = large.slice(1, 2);
  if (tiny.size !== 1 || await tiny.text() !== 'a') throw new Error('大 Blob 的小切片不正确。');

  return `${cases.length} 组切片边界、原型、MIME、嵌套切片和 1 MiB → 1 字节切片：通过`;
}

async function encoding() {
  const empty = new Blob();
  const [bytes, buffer, text] = await Promise.all([empty.bytes(), empty.arrayBuffer(), empty.text()]);
  if (empty.size !== 0 || empty.type !== '' || bytes.length !== 0 || buffer.byteLength !== 0 || text !== '') {
    throw new Error('空 Blob 返回值不正确。');
  }

  const parts = ['a\r\nb\rc\n', new Blob(['\r']), '\r', '\n'];
  const native = await new Blob(parts, { endings: 'native' }).text();
  const transparent = await new Blob(parts, { endings: 'transparent' }).text();
  if (native !== 'a\nb\nc\n\r\n\n' || transparent !== 'a\r\nb\rc\n\r\r\n') {
    throw new Error(`换行处理不正确：${JSON.stringify({ native, transparent })}`);
  }

  const unicode = new Blob([new Uint8Array([0xe4]), new Uint8Array([0xb8, 0x96, 0xe7]), new Uint8Array([0x95, 0x8c])]);
  if (await unicode.text() !== '世界') throw new Error('跨片段 UTF-8 解码失败。');

  const invalid = new Blob([new Uint8Array([192, 193, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255])]);
  if (await invalid.text() !== '\ufffd'.repeat(13)) throw new Error('损坏 UTF-8 的替换字符不正确。');

  const bom = await new Blob([new Uint8Array([0xef, 0xbb, 0xbf, 65])]).text();
  if (bom !== '\ufeffA') throw new Error(`原生 Blob 的 BOM 保留不正确：${JSON.stringify(bom)}`);

  const iterable = new Blob(new Set(['a', 'b']));
  if (await iterable.text() !== 'ab') throw new Error('Iterable 构造失败。');

  let rejected = false;
  try {
    new Blob([], { endings: 'invalid' as EndingType });
  } catch (error) {
    if (!(error instanceof TypeError)) throw new Error(`非法 endings 应抛出 TypeError：${String(error)}`);
    rejected = true;
  }
  if (!rejected) throw new Error('非法 endings 未被拒绝。');

  const surrogate = await new Blob(['\ud800']).bytes();

  return `空值、换行、跨片段 UTF-8、13 个损坏字节、BOM、Iterable 与非法选项：通过\n`
    + `未配对代理项的编码字节：${Array.from(surrogate).join(', ')}`;
}

async function streams() {
  const source = Uint8Array.from({ length: 131073 }, (_, index) => index % 251);
  const blob = new Blob([source]);
  const rows: string[] = [];

  for (const byob of [false, true]) {
    const reader = byob ? blob.stream().getReader({ mode: 'byob' }) : blob.stream().getReader();
    let offset = 0;
    let chunks = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;

    try {
      while (true) {
        const next = byob
          ? (reader as ReadableStreamBYOBReader).read(new Uint8Array(8192))
          : (reader as ReadableStreamDefaultReader<Uint8Array>).read();
        const result = await Promise.race([
          next,
          new Promise<never>((_, reject) => {
            timer = setTimeout(() => reject(new Error('流读取超过 5 秒。')), 5000);
          }),
        ]);
        clearTimeout(timer);

        if (result.value) {
          const bytes = result.value as Uint8Array;
          if (bytes.some((value, index) => value !== source[offset + index])) {
            throw new Error(`${byob ? 'BYOB' : '默认'}流在 ${offset} 字节处内容不符。`);
          }
          offset += bytes.length;
          chunks += 1;
        }
        if (result.done) break;
      }

      if (offset !== source.length) throw new Error(`流读取长度不符：${offset} / ${source.length}`);
      rows.push(`${byob ? 'BYOB' : '默认'}流：${offset} 字节 / ${chunks} 次读取，通过`);
    } finally {
      clearTimeout(timer);
      await reader.cancel();
      reader.releaseLock();
    }
  }

  return rows.join('\n');
}

export function BlobDemo() {
  const [input, setInput] = useState('Hello 世界 🌍');
  const [type, setType] = useState('TEXT/PLAIN');
  const [size, setSize] = useState<number>();
  const value = useAsyncResult();
  const bytes = useAsyncResult();
  const slice = useAsyncResult();
  const text = useAsyncResult();
  const stream = useAsyncResult();
  const busy = [value, bytes, slice, text, stream].some(result => result.state.phase === 'running');

  const create = () => value.run(async () => {
    const blob = new Blob([input], { type });
    const [text, bytes, buffer] = await Promise.all([blob.text(), blob.bytes(), blob.arrayBuffer()]);
    setSize(blob.size);

    return JSON.stringify({
      text, size: blob.size, type: blob.type, bytes: Array.from(bytes), arrayBufferLength: buffer.byteLength,
    }, null, 2);
  });

  return (
    <>
      <Panel eyebrow="创建与读取" title="把文本保存为二进制数据">
        <Field label="文本" onChangeText={setInput} testID="blob-input" value={input} />
        <Field label="MIME 类型" onChangeText={setType} testID="blob-type" value={type} />
        <DataRow label="字节数" value={size === undefined ? '尚未创建' : String(size)} />
        <ActionButton disabled={busy} label="创建并读取 Blob" onPress={() => void create()} testID="blob-create" />
        <ResultPanel state={value.state} />
      </Panel>

      <Panel eyebrow="二进制" title="验证类型、偏移与数据隔离">
        <ActionButton disabled={busy} label="验证二进制读写" onPress={() => void bytes.run(binary)} testID="blob-binary" />
        <Note>覆盖 10 种 TypedArray、ArrayBuffer、输入快照与并发读取。修改输入或读取结果不应改变 Blob 内容。</Note>
        <ResultPanel state={bytes.state} />
      </Panel>

      <Panel eyebrow="切片" title="验证边界与嵌套 Blob">
        <ActionButton disabled={busy} label="验证切片" onPress={() => void slice.run(slices)} testID="blob-slices" />
        <ResultPanel state={slice.state} />
      </Panel>

      <Panel eyebrow="文本" title="验证编码、换行与构造参数">
        <ActionButton disabled={busy} label="验证文本与参数" onPress={() => void text.run(encoding)} testID="blob-encoding" />
        <Note>按 Expo 原生行为检查 BOM 保留，并展示平台对未配对代理项的编码结果。</Note>
        <ResultPanel state={text.state} />
      </Panel>

      <Panel eyebrow="流读取" title="完整读取超过 64 KiB 的 Blob">
        <ActionButton disabled={busy} label="验证默认流与 BYOB" onPress={() => void stream.run(streams)} testID="blob-streams" />
        <Note>分别读取 128 KiB + 1 字节并逐字节校验。官方 stream() 会先将整个 Blob 读入内存。</Note>
        <ResultPanel state={stream.state} />
      </Panel>
    </>
  );
}
