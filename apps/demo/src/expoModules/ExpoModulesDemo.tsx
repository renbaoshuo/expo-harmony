import { useEffect, useState } from 'react';

import { showcaseConsumer, showcaseModule, type ShowcaseEvent, type ShowcaseNativeModule } from '../../modules/expo-module-showcase';
import { ActionButton, ActionRow, DataRow, Field, Note, Panel, ResultPanel, Tag, useAsyncResult } from '../ui';
import { NativeViewCard } from './NativeViewCard';
import { SharedObjectsCard } from './SharedObjectsCard';

export function ExpoModulesDemo() {
  if (!showcaseModule || !showcaseConsumer) {
    return (
      <Panel title="本地模块尚未加载">
        <Note>请重新编译 Android、iOS 或 HarmonyOS 开发构建，再打开此页。Expo Go 不包含这个本地模块。</Note>
      </Panel>
    );
  }
  return <ModuleCards module={showcaseModule} />;
}

function ModuleCards({ module }: { module: ShowcaseNativeModule }) {
  const [input, setInput] = useState('Hello, Expo Modules!');
  const [listening, setListening] = useState(false);
  const [received, setReceived] = useState<ShowcaseEvent>();
  const [receivedCount, setReceivedCount] = useState(0);
  const calls = useAsyncResult();
  const events = useAsyncResult();
  const lifecycle = useAsyncResult();
  const page = useAsyncResult();
  const [pageValue, setPageValue] = useState(0);

  useEffect(() => {
    if (!listening) return;
    const subscription = module.addListener('onShowcaseEvent', (event) => {
      setReceived(event);
      setReceivedCount(count => count + 1);
    });
    return () => subscription.remove();
  }, [listening, module]);

  return (
    <>
      <Panel eyebrow="Local module" title="当前原生实现">
        <ActionRow><Tag tone="signal">{module.platform}</Tag><Tag>{module.nativeLanguage}</Tag></ActionRow>
        <DataRow label="测试平台" value="Android / iOS / HarmonyOS" />
        <Note>逐张卡片执行并查看结果。原生组件和页面还需要手动确认布局、点击响应及返回行为。</Note>
      </Panel>

      <Panel eyebrow="Functions" title="同步与异步调用">
        <Field label="传给原生模块的文本" onChangeText={setInput} value={input} />
        <ActionRow>
          <ActionButton disabled={calls.state.phase === 'running'} label="同步回显" onPress={() => void calls.run(() => module.echo(input))} />
          <ActionButton disabled={calls.state.phase === 'running'} label="异步回显" onPress={() => void calls.run(() => module.echoAsync(input))} tone="secondary" />
          <ActionButton
            disabled={calls.state.phase === 'running'}
            label="测试错误返回"
            onPress={() => void calls.run(async () => {
              try {
                await module.failAsync();
              } catch (error) {
                if (error && typeof error === 'object' && 'code' in error && error.code === 'ERR_SHOWCASE') {
                  return '已收到预期的原生错误：ERR_SHOWCASE';
                }
                throw error;
              }
              throw new Error('原生方法应拒绝 Promise，但实际返回成功。');
            })}
            tone="secondary"
          />
        </ActionRow>
        <ResultPanel state={calls.state} />
      </Panel>

      <Panel eyebrow="Events" title="订阅与取消订阅">
        <DataRow label="订阅状态" value={listening ? '已订阅' : '未订阅'} />
        <DataRow label="累计收到" value={receivedCount} />
        <DataRow label="最近事件" value={received ? `${received.platform} #${received.sequence} · ${received.value}` : '暂无'} />
        <ActionRow>
          <ActionButton label={listening ? '取消订阅' : '订阅事件'} onPress={() => setListening(value => !value)} />
          <ActionButton
            label="发送当前文本"
            onPress={() => void events.run(() => {
              module.emitEvent(input);
              return '已调用原生发送方法，请观察累计收到的事件数量。';
            })}
            tone="secondary"
          />
        </ActionRow>
        <Note>取消订阅后再次发送，收到的数量应保持不变。离开本页会自动移除订阅。</Note>
        <ResultPanel state={events.state} />
      </Panel>

      <SharedObjectsCard module={module} />
      <NativeViewCard />

      <Panel eyebrow="Native page" title="打开原生页面并接收结果">
        <DataRow label="传入计数" value={pageValue} />
        <ActionButton
          disabled={page.state.phase === 'running'}
          label="打开原生页面"
          onPress={() => void page.run(async () => {
            const result = await module.openNativePage(pageValue);
            if (result.action === 'done') setPageValue(result.value);
            return `${result.action === 'done' ? '完成并返回' : '已取消'}，原生页面计数：${result.value}`;
          })}
        />
        <Note>在原生页面内增加计数，然后完成或取消。完成时保存结果；取消时保留上一次传入值。</Note>
        <ResultPanel state={page.state} />
      </Panel>

      <Panel eyebrow="Lifecycle" title="模块生命周期">
        <ActionButton label="读取生命周期" onPress={() => void lifecycle.run(() => JSON.stringify(module.getLifecycleSnapshot(), null, 2))} />
        <Note>切换到后台再回到应用，重新读取以比较前后台次数。事件卡片的订阅变化也会记录在这里。</Note>
        <ResultPanel state={lifecycle.state} />
      </Panel>
    </>
  );
}
