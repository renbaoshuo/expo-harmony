/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { useEffect, useState } from 'react';

import { showcaseConsumer, showcaseModule, type ShowcaseEvent, type ShowcaseNativeModule } from '../../modules/expo-module-showcase';
import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { NativeViewCard } from './NativeViewCard';
import { SharedObjectsCard } from './SharedObjectsCard';

export function ExpoModulesDemo() {
  if (!showcaseModule || !showcaseConsumer) return <Panel title="ExpoModuleShowcase 尚未加载" />;

  return <ModuleCards module={showcaseModule} consumer={showcaseConsumer} />;
}

function ModuleCards({ module, consumer }: {
  module: ShowcaseNativeModule;
  consumer: NonNullable<typeof showcaseConsumer>;
}) {
  const [input, setInput] = useState('Hello, Expo Modules!');
  const [eventValue, setEventValue] = useState('你好');
  const [listening, setListening] = useState(false);
  const [received, setReceived] = useState<ShowcaseEvent>();
  const calls = useAsyncResult();
  const events = useAsyncResult();
  const lifecycle = useAsyncResult();
  const page = useAsyncResult();
  const [pageValue, setPageValue] = useState('0');
  const busy = calls.state.phase === 'running';

  useEffect(() => {
    if (!listening) return;
    const subscription = module.addListener('onShowcaseEvent', setReceived);
    return () => subscription.remove();
  }, [listening, module]);

  return (
    <>
      <Panel title="ExpoModuleShowcase">
        <DataRow label="platform" value={module.platform} />
        <DataRow label="nativeLanguage" value={module.nativeLanguage} />
        <Field label="value" onChangeText={setInput} value={input} />
        <ActionRow>
          <ActionButton disabled={busy} label="echo()" onPress={() => void calls.run(() => module.echo(input))} testID="showcase-echo" />
          <ActionButton disabled={busy} label="echoAsync()" onPress={() => void calls.run(() => module.echoAsync(input))} testID="showcase-echo-async" />
          <ActionButton disabled={busy} label="failAsync()" testID="showcase-error" onPress={() => void calls.run(() => module.failAsync())} tone="secondary" />
        </ActionRow>
        <ResultPanel state={calls.state} />
      </Panel>
      <Panel title="onShowcaseEvent">
        <Field label="value" value={eventValue} onChangeText={setEventValue} />
        <ActionRow>
          <ActionButton label={listening ? '移除监听' : '添加监听'} onPress={() => setListening(value => !value)} />
          <ActionButton
            label="emitEvent()"
            onPress={() => void events.run(() => {
              module.emitEvent(eventValue);
              return '已发送事件';
            })}
          />
        </ActionRow>
        <DataRow label="最近收到的事件" value={received ? json(received) : '暂无'} />
        <ResultPanel state={events.state} />
      </Panel>
      <SharedObjectsCard module={module} consumer={consumer} />
      <NativeViewCard />
      <Panel title="原生页面">
        <Field label="initialValue" value={pageValue} onChangeText={setPageValue} keyboardType="number-pad" />
        <ActionButton
          disabled={page.state.phase === 'running' || !/^-?\d+$/.test(pageValue)}
          label="openNativePage()"
          testID="showcase-open-native-page"
          onPress={() => void page.run(async () => json(await module.openNativePage(Number(pageValue))))}
        />
        <ResultPanel state={page.state} />
      </Panel>
      <Panel title="模块生命周期">
        <ActionButton label="getLifecycleSnapshot()" onPress={() => void lifecycle.run(() => json(module.getLifecycleSnapshot()))} />
        <ResultPanel state={lifecycle.state} />
      </Panel>
    </>
  );
}
