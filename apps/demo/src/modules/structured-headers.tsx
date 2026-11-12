/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { useState } from 'react';

import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { runtimeDemo } from './runtime-demo';

const examples = {
  parseDictionary: 'signature=:aGVsbG8=:, keyid="main", enabled',
  parseList: '("harmony" 1.0);version=1, token;ready',
  parseItem: '1.0;key="value"',
  parseBareItem: '1.5',
  parseParameters: ';enabled;key="value"',
  parseKey: 'example-key',
  parseString: '"HarmonyOS";ready',
  parseToken: 'harmony;ready',
  parseByteSequence: ':aGVsbG8=:;encoding="base64"',
  parseBoolean: '?1;ready',
  parseIntegerOrDecimal: '2.50;unit="seconds"',
  parseInnerList: '("harmony" 1.0);version=1',
  parseItemOrInnerList: '(1 2 3);ready',
};

const objects = {
  dictionary: {
    signature: [{ base64: 'aGVsbG8=' }, {}],
    keyid: ['main', {}],
    enabled: [true, {}],
  },
  list: [
    [[['harmony', {}], [{ permille: 1000 }, {}]], { version: 1 }],
    [{ token: 'token' }, { ready: true }],
  ],
  item: [{ permille: 1000 }, { key: 'value' }],
};

export function StructuredHeadersDemo() {
  if (!runtimeDemo) return <Panel title="此示例需要 HarmonyOS 原生模块" />;

  return (
    <>
      <HeaderParser />
      <HeaderSerializer />
    </>
  );
}

function HeaderParser() {
  const result = useAsyncResult();
  const [method, setMethod] = useState<keyof typeof examples>('parseDictionary');
  const [input, setInput] = useState(examples.parseDictionary);
  const [multipleLines, setMultipleLines] = useState(false);
  const canSplit = method === 'parseDictionary' || method === 'parseList' || method === 'parseItem';

  return (
    <Panel title="解析结构化响应头">
      <ActionRow>
        {(Object.keys(examples) as (keyof typeof examples)[]).map(value => (
          <ActionButton
            key={value}
            label={value}
            tone={method === value ? 'primary' : 'secondary'}
            onPress={() => {
              setMethod(value);
              setInput(examples[value]);
              result.clear();
            }}
          />
        ))}
      </ActionRow>
      <Field label="响应头值" multiline onChangeText={setInput} value={input} />
      {canSplit
        ? (
            <ActionButton label={multipleLines ? '每行单独传入' : '作为一个字符串传入'} tone={multipleLines ? 'primary' : 'secondary'} onPress={() => setMultipleLines(value => !value)} />
          )
        : null}
      <ActionButton
        label={`${method}()`}
        onPress={() => void result.run(() =>
          json(JSON.parse(runtimeDemo!.parseHeader(method, input, canSplit && multipleLines))))}
      />
      <ResultPanel state={result.state} />
    </Panel>
  );
}

function HeaderSerializer() {
  const result = useAsyncResult();
  const [format, setFormat] = useState<keyof typeof objects>('item');
  const [input, setInput] = useState(json(objects.item));
  const methods = { dictionary: 'serializeDictionary()', list: 'serializeList()', item: 'serializeItem()' };

  return (
    <Panel title="序列化结构化响应头">
      <ActionRow>
        {(Object.keys(objects) as (keyof typeof objects)[]).map(value => (
          <ActionButton
            key={value}
            label={value}
            tone={format === value ? 'primary' : 'secondary'}
            onPress={() => {
              setFormat(value);
              setInput(json(objects[value]));
              result.clear();
            }}
          />
        ))}
      </ActionRow>
      <Field label="结构化数据（JSON）" multiline onChangeText={setInput} value={input} />
      <ActionButton label={methods[format]} onPress={() => void result.run(() => runtimeDemo!.serializeHeader(format, input))} testID="headers-serialize" />
      <ResultPanel state={result.state} />
    </Panel>
  );
}
