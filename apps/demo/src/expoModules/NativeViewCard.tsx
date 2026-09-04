import { useRef, useState } from 'react';

import { ShowcaseView, type ShowcaseViewEvent, type ShowcaseViewRef } from '../../modules/expo-module-showcase';
import { ActionButton, ActionRow, DataRow, Field, Note, Panel, ResultPanel, useAsyncResult } from '../ui';

export function NativeViewCard() {
  const ref = useRef<ShowcaseViewRef>(null);
  const [mounted, setMounted] = useState(true);
  const [label, setLabel] = useState('原生计数器');
  const [value, setValue] = useState(1);
  const [event, setEvent] = useState<ShowcaseViewEvent>();
  const command = useAsyncResult();

  return (
    <Panel eyebrow="Native view" title="原生组件交互">
      <Field label="组件标题（实时更新 prop）" onChangeText={setLabel} value={label} />
      {mounted
        ? (
            <ShowcaseView
              label={label}
              onValueChanged={({ nativeEvent }) => {
                setEvent(nativeEvent);
                setValue(nativeEvent.value);
              }}
              ref={ref}
              style={{ height: 164, width: '100%' }}
              value={value}
            />
          )
        : <Note>组件已卸载。重新挂载后会使用当前标题和计数。</Note>}
      <ActionRow>
        <ActionButton disabled={!mounted} label="通过 prop +1" onPress={() => setValue(current => current + 1)} />
        <ActionButton
          disabled={!mounted || command.state.phase === 'running'}
          label="通过 ref +1"
          onPress={() => void command.run(async () => {
            if (!ref.current) throw new Error('原生组件尚未挂载。');
            return `原生方法返回：${await ref.current.increment(1)}`;
          })}
          tone="secondary"
        />
        <ActionButton
          disabled={command.state.phase === 'running'}
          label={mounted ? '卸载组件' : '重新挂载'}
          onPress={() => {
            setMounted(current => !current);
            setEvent(undefined);
            command.clear();
          }}
          tone="secondary"
        />
      </ActionRow>
      <DataRow label="最近的原生事件" value={event ? `${event.source} · ${event.label} · ${event.value}` : '等待点击组件或调用 ref'} />
      <Note>点击组件内的蓝色按钮由原生 UI 处理。prop 更新不发送事件；原生点击和 ref 调用会回传计数。</Note>
      <ResultPanel state={command.state} />
    </Panel>
  );
}
