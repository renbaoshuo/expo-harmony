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

const readers = [
  { type: 'raw', required: 'require', nullable: 'getNullable', key: 'name' },
  { type: 'string', required: 'requireString', nullable: 'getNullableString', key: 'name' },
  { type: 'number', required: 'requireNumber', nullable: 'getNullableNumber', key: 'count' },
  { type: 'boolean', required: 'requireBoolean', nullable: 'getNullableBoolean', key: 'enabled' },
  { type: 'array', required: 'requireArray', nullable: 'getNullableArray', key: 'items' },
  { type: 'object', required: 'requireObject', nullable: 'getNullableObject', key: 'extra' },
] as const;
const sample = { name: 'HarmonyOS', count: ' 2.5 ', enabled: 'TRUE', items: [1, null], extra: {}, empty: null };

export function JSONUtilsDemo() {
  const [input, setInput] = useState(json(sample));
  const [key, setKey] = useState('name');
  const [reader, setReader] = useState<typeof readers[number]>(readers[0]);
  const result = useAsyncResult();

  if (!runtimeDemo) return <Panel title="此示例需要 HarmonyOS 原生模块" />;

  function read(type: typeof reader.type | 'hasValue', nullable = false) {
    void result.run(() => json(JSON.parse(runtimeDemo!.readJSON(input, key, type, nullable))));
  }

  return (
    <Panel title="JSONObjectUtils">
      <Field label="JSON 对象" multiline onChangeText={setInput} value={input} />
      <Field label="字段名" onChangeText={setKey} value={key} />
      <ActionRow>
        {readers.map(value => (
          <ActionButton
            key={value.type}
            label={value.type}
            onPress={() => {
              setReader(value);
              setKey(value.key);
              result.clear();
            }}
            tone={reader === value ? 'primary' : 'secondary'}
          />
        ))}
      </ActionRow>
      <ActionRow>
        <ActionButton label={`${reader.required}()`} onPress={() => read(reader.type)} testID="json-utils-required" />
        <ActionButton label={`${reader.nullable}()`} onPress={() => read(reader.type, true)} testID="json-utils-nullable" />
        <ActionButton label="hasValue()" onPress={() => read('hasValue')} tone="secondary" />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}
