import { ContractCard, type ContractDefinition } from '../build-contract';
import { json } from '../format';
import { configSnapshot } from '../config-snapshot';

const contracts: readonly ContractDefinition[] = [
  {
    description: '检查写入原生 Harmony 工程的关键值。',
    label: '验证 prebuild 值',
    title: '原生工程描述',
    run: () => {
      const config = configSnapshot();
      const harmony = config.harmony as Record<string, unknown>;
      if (harmony.bundleName !== 'com.expo.harmony.demo') throw new Error(`应用包名不符合预期：${String(harmony.bundleName)}`);
      return json(harmony);
    },
  },
  {
    description: '确认启动屏、导航栏、音频与后台插件已进入应用配置。',
    label: '读取 prebuild 输入',
    title: '插件输入',
    run: () => json(configSnapshot().plugins ?? []),
  },
];

export function PrebuildConfigDemo() {
  return <>{contracts.map(definition => <ContractCard definition={definition} key={definition.title} />)}</>;
}
