import { ContractCard, type ContractDefinition } from '../build-contract';
import { json } from '../format';
import { configSnapshot } from '../config-snapshot';

const contracts: readonly ContractDefinition[] = [
  {
    description: '读取配置插件全部执行完毕后内嵌的应用配置。',
    label: '读取生成的配置',
    title: '内嵌的 Harmony 配置',
    run: () => json(configSnapshot()),
  },
  {
    description: '验证当前包集合所需的插件均已声明。',
    label: '检查插件归属',
    title: '已配置的插件',
    run: () => {
      const plugins = configSnapshot().plugins ?? [];
      if (plugins.length === 0) throw new Error('未内嵌任何配置插件。');
      return json(plugins);
    },
  },
];

export function ConfigPluginsDemo() {
  return <>{contracts.map(definition => <ContractCard definition={definition} key={definition.title} />)}</>;
}
