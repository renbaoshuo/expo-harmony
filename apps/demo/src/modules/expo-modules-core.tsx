import { EventEmitter, requireOptionalNativeModule } from 'expo-modules-core';
import { ActionButton, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

export function ModulesCoreDemo() {
  const registry = useAsyncResult();
  const events = useAsyncResult();

  const inspectRegistry = () => registry.run(() => {
    const expoRuntime = (globalThis as typeof globalThis & {
      expo?: { modules?: Record<string, unknown> };
    }).expo;
    if (!expoRuntime?.modules) throw new Error('globalThis.expo.modules 不可用。');

    const constants = requireOptionalNativeModule('ExponentConstants')
      ?? requireOptionalNativeModule('ExpoConstants');
    if (!constants) throw new Error('未能通过 requireOptionalNativeModule 找到 Constants。');

    return json({
      moduleCount: Object.keys(expoRuntime.modules).length,
      modules: Object.keys(expoRuntime.modules).sort(),
    });
  });

  const runEmitter = () => events.run(() => {
    type Events = { value: (value: number) => void };
    const emitter = new EventEmitter<Events>();
    let observed = 0;
    const subscription = emitter.addListener('value', (value) => {
      observed += value;
    });
    emitter.emit('value', 7);
    subscription.remove();
    emitter.emit('value', 5);
    if (observed !== 7 || emitter.listenerCount('value') !== 0) {
      throw new Error(`EventEmitter 清理失败：observed=${observed}。`);
    }
    return '监听器同步收到 7，并在 remove() 之后不再接收事件。';
  });

  return (
    <>
      <Panel eyebrow="原生注册表" title="检查由 Expo Modules Core 安装的模块">
        <ActionButton label="读取模块注册表" onPress={() => void inspectRegistry()} />
        <ResultPanel state={registry.state} />
      </Panel>
      <Panel eyebrow="C++ 事件发射器" title="添加、触发、计数并移除监听器">
        <ActionButton label="运行事件契约" onPress={() => void runEmitter()} />
        <ResultPanel state={events.state} />
      </Panel>
    </>
  );
}
