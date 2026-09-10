import { requireOptionalNativeModule } from 'expo-modules-core';
import { ContractCard, type ContractDefinition } from '../build-contract';
import { json } from '../format';

const contracts: readonly ContractDefinition[] = [
  {
    description: '检查 prebuild 期间由自动链接生成的原生注册表。',
    label: '读取已链接模块',
    title: '运行时注册表输出',
    run: () => {
      const modules = (
        globalThis as typeof globalThis & { expo?: { modules?: Record<string, unknown> } }
      ).expo?.modules;
      if (!modules || Object.keys(modules).length === 0) throw new Error('没有注册任何自动链接的 Expo 模块。');
      return json(Object.keys(modules).sort());
    },
  },
  {
    description: '通过注册表直接获取已知模块，而非导入其 JavaScript 门面。',
    label: '获取已知模块',
    title: '已知模块解析',
    run: () => {
      const module = requireOptionalNativeModule('ExponentConstants') ?? requireOptionalNativeModule('ExpoConstants');
      if (!module) throw new Error('未能从原生注册表解析到 Constants。');
      return '已从自动链接的 Expo 模块注册表解析到 Constants。';
    },
  },
];

export function ModulesAutolinkingDemo() {
  return <>{contracts.map(definition => <ContractCard definition={definition} key={definition.title} />)}</>;
}
