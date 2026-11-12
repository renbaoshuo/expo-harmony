/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as KeepAwake from 'expo-keep-awake';
import { useEffect, useRef, useState } from 'react';
import { Platform, Switch } from 'react-native';

import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

function Awake({ tag, options }: { tag?: string; options: KeepAwake.KeepAwakeOptions }) {
  KeepAwake.useKeepAwake(tag, options);
  return null;
}

export function KeepAwakeDemo() {
  const action = useAsyncResult();
  const [tag, setTag] = useState('expo-harmony-demo-manual');
  const [activeTags, setActiveTags] = useState<string[]>([]);
  const [hookTag, setHookTag] = useState('expo-harmony-demo-hook');
  const [hookActive, setHookActive] = useState(false);
  const [suppress, setSuppress] = useState(false);
  const [listen, setListen] = useState(false);
  const [lastEvent, setLastEvent] = useState('');
  const owned = useRef(new Set<string>());
  const mounted = useRef(false);
  const subscription = useRef<ReturnType<typeof KeepAwake.addListener> | null>(null);
  const busy = action.state.phase === 'running';
  const web = Platform.OS === 'web';
  const manualTag = tag || undefined;
  const resolvedTag = manualTag ?? KeepAwake.ExpoKeepAwakeTag;

  useEffect(() => {
    const tags = owned.current;
    mounted.current = true;

    return () => {
      mounted.current = false;
      subscription.current?.remove();
      for (const tag of tags) void KeepAwake.deactivateKeepAwake(tag).catch(() => {});
      tags.clear();
    };
  }, []);

  const activate = (operation: (tag?: string) => Promise<void>) => action.run(async () => {
    if (!owned.current.has(resolvedTag)) await operation(manualTag);
    if (mounted.current) {
      owned.current.add(resolvedTag);
      setActiveTags([...owned.current]);
    } else {
      await KeepAwake.deactivateKeepAwake(manualTag);
    }

    return `已请求常亮（${resolvedTag}）`;
  });

  const release = () => action.run(async () => {
    await KeepAwake.deactivateKeepAwake(manualTag);
    owned.current.delete(resolvedTag);
    setActiveTags([...owned.current]);
    return `已释放常亮（${resolvedTag}）`;
  });

  return (
    <>
      <Panel title="保持屏幕常亮">
        <DataRow label="默认标签" value={KeepAwake.ExpoKeepAwakeTag} />
        <Field label="标签" onChangeText={setTag} value={tag} />
        {activeTags.length > 0 ? <DataRow label="已激活标签" value={activeTags.join(', ')} /> : null}
        <ActionRow>
          <ActionButton disabled={busy || activeTags.includes(resolvedTag)} label="请求常亮" onPress={() => void activate(KeepAwake.activateKeepAwakeAsync)} />
          <ActionButton disabled={busy || activeTags.includes(resolvedTag)} label="请求常亮（旧版接口）" onPress={() => void activate(KeepAwake.activateKeepAwake)} tone="secondary" />
          <ActionButton disabled={busy || !activeTags.includes(resolvedTag)} label="释放常亮" onPress={() => void release()} tone="secondary" />
          <ActionButton disabled={busy} label="查询常亮是否可用" onPress={() => void action.run(async () => String(await KeepAwake.isAvailableAsync()))} tone="secondary" />
        </ActionRow>
        {web
          ? (
              <ActionRow>
                <ActionButton
                  disabled={busy || !activeTags.includes(resolvedTag)}
                  label="监听当前标签"
                  onPress={() => void action.run(() => {
                    subscription.current?.remove();
                    const listener = (event: KeepAwake.KeepAwakeEvent) => setLastEvent(event.state);
                    subscription.current = manualTag
                      ? KeepAwake.addListener(manualTag, listener)
                      : KeepAwake.addListener(listener);
                    return '已开始监听';
                  })}
                  tone="secondary"
                />
                <ActionButton
                  label="移除监听"
                  onPress={() => {
                    subscription.current?.remove();
                    subscription.current = null;
                  }}
                  tone="secondary"
                />
              </ActionRow>
            )
          : null}
        <ResultPanel state={action.state} />
      </Panel>

      <Panel title="组件挂载期间常亮">
        <Field editable={!hookActive} label="Hook 标签" onChangeText={setHookTag} value={hookTag} />
        <DataRow label="忽略释放失败警告" value={<Switch accessibilityLabel="忽略释放失败警告" disabled={hookActive} onValueChange={setSuppress} value={suppress} />} />
        {web ? <DataRow label="监听 Hook 标签" value={<Switch accessibilityLabel="监听 Hook 标签" disabled={hookActive} onValueChange={setListen} value={listen} />} /> : null}
        <DataRow label="挂载组件" value={<Switch accessibilityLabel="挂载组件" onValueChange={setHookActive} value={hookActive} />} />
        {hookActive
          ? <Awake
              tag={hookTag || undefined}
              options={{
                suppressDeactivateWarnings: suppress,
                listener: listen ? event => setLastEvent(event.state) : undefined,
              }}
            />
          : null}
        {lastEvent ? <DataRow label="最近常亮事件" value={lastEvent} /> : null}
      </Panel>
    </>
  );
}
