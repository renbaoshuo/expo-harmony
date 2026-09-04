import { useEffect, useState } from 'react';

import { showcaseConsumer, type ShowcaseNativeModule, type ShowcaseSharedCounter } from '../../modules/expo-module-showcase';
import { ActionButton, ActionRow, DataRow, Note, Panel, ResultPanel, useAsyncResult } from '../ui';

export function SharedObjectsCard({ module }: { module: ShowcaseNativeModule }) {
  const [counter, setCounter] = useState<ShowcaseSharedCounter>();
  const [value, setValue] = useState(0);
  const [eventValue, setEventValue] = useState<number>();
  const operation = useAsyncResult();
  const busy = operation.state.phase === 'running';

  useEffect(() => {
    if (!counter) return;
    const subscription = counter.addListener('onValueChanged', event => setEventValue(event.value));
    return () => {
      subscription.remove();
      counter.release();
    };
  }, [counter]);

  return (
    <Panel eyebrow="SharedObject / SharedRef" title="共享原生对象">
      <DataRow label="对象状态" value={counter ? `已创建 · value = ${value}` : '未创建 / 已释放'} />
      <DataRow label="对象事件" value={eventValue === undefined ? '暂无' : String(eventValue)} />
      <ActionRow>
        <ActionButton
          disabled={!!counter || busy}
          label="创建计数器"
          onPress={() => void operation.run(() => {
            setCounter(new module.ShowcaseSharedCounter(1));
            setValue(1);
            setEventValue(undefined);
            return '已创建原生 SharedObject，初始值为 1。';
          })}
        />
        <ActionButton
          disabled={!counter || busy}
          label="同步 +1"
          onPress={() => void operation.run(() => {
            const next = counter!.increment(1);
            setValue(next);
            return `同步返回：${next}`;
          })}
          tone="secondary"
        />
        <ActionButton
          disabled={!counter || busy}
          label="异步 +1"
          onPress={() => void operation.run(async () => {
            const next = await counter!.incrementAsync(1);
            setValue(next);
            return `异步返回：${next}`;
          })}
          tone="secondary"
        />
        <ActionButton
          disabled={!counter || busy}
          label="通过属性归零"
          onPress={() => void operation.run(() => {
            counter!.value = 0;
            setValue(counter!.value);
            if (counter!.value !== 0) throw new Error('原生属性写入后未返回预期值。');
            return '已写入 value = 0，并从原生对象读回。';
          })}
          tone="secondary"
        />
        <ActionButton
          disabled={!counter || busy}
          label="发送对象事件"
          onPress={() => void operation.run(() => {
            counter!.emitValueChanged();
            return '已发送 onValueChanged，请查看对象事件。';
          })}
          tone="secondary"
        />
        <ActionButton
          disabled={!counter || busy}
          label="验证对象身份"
          onPress={() => void operation.run(() => {
            if (module.returnSameSharedCounter(counter!) !== counter
              || showcaseConsumer!.forwardSharedCounter(counter!) !== counter) {
              throw new Error('跨模块传递后对象身份发生变化。');
            }
            const received = showcaseConsumer!.readSharedCounter(counter!);
            if (received !== counter!.value) throw new Error('跨模块读取的计数不一致。');
            return `同模块 / 跨模块均保留对象身份，读取值：${received}`;
          })}
          tone="secondary"
        />
        <ActionButton
          disabled={!counter || busy}
          label="释放对象"
          onPress={() => {
            setCounter(undefined);
            setEventValue(undefined);
            operation.clear();
          }}
          tone="secondary"
        />
        <ActionButton
          disabled={busy}
          label="传递文本 SharedRef"
          onPress={() => void operation.run(() => {
            const ref = module.createSharedTextRef('Hello, SharedRef!');
            try {
              if (showcaseConsumer!.forwardSharedTextRef(ref) !== ref) throw new Error('SharedRef 身份发生变化。');
              const text = showcaseConsumer!.readSharedTextRef(ref);
              if (text !== ref.value) throw new Error('跨模块读取的文本与原始值不一致。');
              return `${ref.nativeRefType}\n${text}`;
            } finally {
              ref.release();
            }
          })}
          tone="secondary"
        />
      </ActionRow>
      <Note>释放后可重新创建；离开页面会清理对象订阅并释放对象。文本引用在每次测试结束时释放。</Note>
      <ResultPanel state={operation.state} />
    </Panel>
  );
}
