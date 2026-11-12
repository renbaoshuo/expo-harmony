/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { useEffect, useState } from 'react';

import type { ShowcaseConsumerModule, ShowcaseNativeModule, ShowcaseSharedCounter, ShowcaseTextRef } from '../../modules/expo-module-showcase';
import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

type Props = { module: ShowcaseNativeModule; consumer: ShowcaseConsumerModule };

export function SharedObjectsCard(props: Props) {
  return (
    <>
      <SharedCounterCard {...props} />
      <SharedTextCard {...props} />
    </>
  );
}

function SharedCounterCard({ module, consumer }: Props) {
  const [counter, setCounter] = useState<ShowcaseSharedCounter>();
  const [value, setValue] = useState('1');
  const [delta, setDelta] = useState('1');
  const [listening, setListening] = useState(false);
  const [eventValue, setEventValue] = useState<number>();
  const operation = useAsyncResult();
  const busy = operation.state.phase === 'running';

  useEffect(() => {
    if (!counter || !listening) return;
    const subscription = counter.addListener('onValueChanged', event => setEventValue(event.value));
    return () => subscription.remove();
  }, [counter, listening]);
  useEffect(() => () => counter?.release(), [counter]);

  function invoke(action: (current: ShowcaseSharedCounter) => unknown | Promise<unknown>) {
    if (counter) void operation.run(async () => json(await action(counter)));
  }

  return (
    <Panel title="ShowcaseSharedCounter">
      <Field label="value" value={value} onChangeText={setValue} keyboardType="number-pad" />
      <Field label="delta" value={delta} onChangeText={setDelta} keyboardType="number-pad" />
      <ActionRow>
        <ActionButton
          disabled={!!counter || busy || !/^-?\d+$/.test(value)}
          label="创建计数器"
          testID="showcase-shared-counter-create"
          onPress={() => void operation.run(() => {
            setCounter(new module.ShowcaseSharedCounter(Number(value)));
            return '已创建计数器';
          })}
        />
        <ActionButton disabled={!counter || busy} label="读取 value" onPress={() => invoke(current => current.value)} />
        <ActionButton
          disabled={!counter || busy || !/^-?\d+$/.test(value)}
          label="设置 value"
          onPress={() => invoke((current) => {
            current.value = Number(value);
            return current.value;
          })}
        />
        <ActionButton disabled={!counter || busy || !/^-?\d+$/.test(delta)} label="increment()" onPress={() => invoke(current => current.increment(Number(delta)))} />
        <ActionButton disabled={!counter || busy || !/^-?\d+$/.test(delta)} label="incrementAsync()" onPress={() => invoke(current => current.incrementAsync(Number(delta)))} />
        <ActionButton disabled={!counter || busy} label="returnSameSharedCounter()" onPress={() => invoke(current => ({ sameObject: module.returnSameSharedCounter(current) === current }))} />
        <ActionButton disabled={!counter || busy} label="readSharedCounter()" onPress={() => invoke(current => consumer.readSharedCounter(current))} />
        <ActionButton disabled={!counter || busy} label="forwardSharedCounter()" onPress={() => invoke(current => ({ sameObject: consumer.forwardSharedCounter(current) === current }))} />
        <ActionButton disabled={!counter || busy} label={listening ? '移除监听' : '监听计数变化'} onPress={() => setListening(value => !value)} />
        <ActionButton
          disabled={!counter || busy}
          label="emitValueChanged()"
          onPress={() => {
            counter?.emitValueChanged();
          }}
        />
        <ActionButton
          disabled={!counter || busy}
          label="release()"
          testID="showcase-shared-counter-release"
          onPress={() => {
            setCounter(undefined);
            setListening(false);
            setEventValue(undefined);
            operation.clear();
          }}
          tone="secondary"
        />
      </ActionRow>
      <DataRow label="onValueChanged" value={eventValue ?? '暂无'} />
      <ResultPanel state={operation.state} />
    </Panel>
  );
}

function SharedTextCard({ module, consumer }: Props) {
  const [text, setText] = useState('你好，SharedRef');
  const [ref, setRef] = useState<ShowcaseTextRef>();
  const operation = useAsyncResult();

  useEffect(() => () => ref?.release(), [ref]);

  return (
    <Panel title="ShowcaseTextRef">
      <Field label="value" value={text} onChangeText={setText} />
      <ActionRow>
        <ActionButton
          disabled={!!ref}
          label="createSharedTextRef()"
          onPress={() => void operation.run(() => {
            setRef(module.createSharedTextRef(text));
            return '已创建文本引用';
          })}
        />
        <ActionButton disabled={!ref} label="读取 value" onPress={() => void operation.run(() => json(ref?.value))} />
        <ActionButton disabled={!ref} label="读取 nativeRefType" onPress={() => void operation.run(() => json(ref?.nativeRefType))} />
        <ActionButton disabled={!ref} label="readSharedTextRef()" onPress={() => void operation.run(() => json(consumer.readSharedTextRef(ref!)))} />
        <ActionButton disabled={!ref} label="forwardSharedTextRef()" onPress={() => void operation.run(() => json({ sameObject: consumer.forwardSharedTextRef(ref!) === ref }))} />
        <ActionButton
          disabled={!ref}
          label="release()"
          tone="secondary"
          onPress={() => {
            setRef(undefined);
            operation.clear();
          }}
        />
      </ActionRow>
      <ResultPanel state={operation.state} />
    </Panel>
  );
}
