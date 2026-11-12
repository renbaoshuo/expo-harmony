/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { useRef, useState } from 'react';

import { ShowcaseView, type ShowcaseViewEvent, type ShowcaseViewRef } from '../../modules/expo-module-showcase';
import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function NativeViewCard() {
  const ref = useRef<ShowcaseViewRef>(null);
  const [mounted, setMounted] = useState(true);
  const [label, setLabel] = useState('原生计数器');
  const [input, setInput] = useState('1');
  const [value, setValue] = useState(1);
  const [delta, setDelta] = useState('1');
  const [event, setEvent] = useState<ShowcaseViewEvent>();
  const command = useAsyncResult();

  return (
    <Panel title="ShowcaseView">
      <Field label="label" onChangeText={setLabel} value={label} testID="showcase-view-label" />
      <Field label="value" onChangeText={setInput} value={input} keyboardType="number-pad" />
      <Field label="delta" onChangeText={setDelta} value={delta} keyboardType="number-pad" />
      <ActionRow>
        <ActionButton disabled={!mounted || !/^-?\d+$/.test(input)} label="设置 value" onPress={() => setValue(Number(input))} testID="showcase-view-prop" />
        <ActionButton
          disabled={!mounted || !/^-?\d+$/.test(delta) || command.state.phase === 'running'}
          label="ref.increment()"
          testID="showcase-view-ref"
          onPress={() => void command.run(async () => json(await ref.current?.increment(Number(delta))))}
        />
        <ActionButton
          disabled={command.state.phase === 'running'}
          label={mounted ? '卸载视图' : '挂载视图'}
          testID="showcase-view-mount"
          onPress={() => {
            setMounted(current => !current);
            setEvent(undefined);
            command.clear();
          }}
          tone="secondary"
        />
      </ActionRow>
      {mounted
        ? (
            <ShowcaseView
              label={label}
              onValueChanged={({ nativeEvent }) => {
                setEvent(nativeEvent);
                setValue(nativeEvent.value);
                setInput(String(nativeEvent.value));
              }}
              ref={ref}
              style={{ height: 164, width: '100%' }}
              value={value}
            />
          )
        : null}
      <DataRow label="onValueChanged" value={event ? json(event) : '暂无'} />
      <ResultPanel state={command.state} />
    </Panel>
  );
}
