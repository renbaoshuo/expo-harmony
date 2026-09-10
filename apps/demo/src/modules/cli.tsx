import Constants from 'expo-constants';
import { Platform } from 'react-native';
import { ContractCard, type ContractDefinition } from '../build-contract';
import { json } from '../format';
import { configSnapshot } from '../config-snapshot';

const contracts: readonly ContractDefinition[] = [
  {
    description: '确认 CLI 的准备与构建管线产出了 bare 模式的 Harmony 应用。',
    label: '验证构建目标',
    title: 'Harmony 构建目标',
    run: () => {
      const platform = String(Platform.OS);
      const executionEnvironment = String(Constants.executionEnvironment);
      if (platform !== 'harmony') throw new Error(`预期 Harmony 目标，实际为 ${platform}。`);
      if (executionEnvironment !== 'bare') {
        throw new Error(`预期 bare 运行时，实际为 ${executionEnvironment}。`);
      }
      return json({ executionEnvironment, platform });
    },
  },
  {
    description: '读取由 CLI/prebuild 管线内嵌的应用标识与 Harmony 配置。',
    label: '读取构建配置',
    title: '内嵌的项目配置',
    run: () => {
      const config = configSnapshot();
      return json({
        harmony: config.harmony,
        name: config.name,
        scheme: config.scheme,
        slug: config.slug,
        version: config.version,
      });
    },
  },
];

export function CliDemo() {
  return <>{contracts.map(definition => <ContractCard definition={definition} key={definition.title} />)}</>;
}
