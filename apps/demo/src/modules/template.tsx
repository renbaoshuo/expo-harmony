import Constants from 'expo-constants';
import { Platform } from 'react-native';
import { ContractCard, type ContractDefinition } from '../build-contract';
import { json } from '../format';
import { configSnapshot } from '../config-snapshot';

const contracts: readonly ContractDefinition[] = [
  {
    description: '检查模板约定的 React Native、Expo 与 Harmony 运行时基线。',
    label: '检查模板运行时',
    title: '运行时基线',
    run: () => {
      const version = Platform.constants?.reactNativeVersion;
      if (!version) throw new Error('无法获取 React Native 版本。');
      return json({
        executionEnvironment: Constants.executionEnvironment,
        expo: Constants.expoVersion,
        reactNative: version,
      });
    },
  },
  {
    description: '确认模板的应用标识与 scheme 已内嵌。',
    label: '检查模板配置',
    title: '应用基线',
    run: () => {
      const config = configSnapshot();
      return json({ name: config.name, scheme: config.scheme, slug: config.slug, version: config.version });
    },
  },
];

export function TemplateDemo() {
  return <>{contracts.map(definition => <ContractCard definition={definition} key={definition.title} />)}</>;
}
