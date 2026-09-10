import { Platform } from 'react-native';
// @ts-expect-error Metro resolves bundled project assets to numeric asset IDs.
import bundledIcon from '../../assets/app-icon.svg';
import { ContractCard, type ContractDefinition } from '../build-contract';
import { json } from '../format';

const contracts: readonly ContractDefinition[] = [
  {
    description: '确认 Metro 已转换并注册项目的 SVG 资源。',
    label: '检查打包资源',
    title: '资源转换',
    run: () => {
      if (typeof bundledIcon !== 'number') throw new Error(`预期数值型 Metro 资源 ID，实际为 ${typeof bundledIcon}。`);
      return json({ assetId: bundledIcon, dev: __DEV__, platform: Platform.OS });
    },
  },
  {
    description: '确认模块重定向后 Harmony 运行时与 Expo 桥接仍可用。',
    label: '检查 Harmony 目标',
    title: '解析器目标',
    run: () => json({ expoRuntime: typeof globalThis.expo, platform: Platform.OS }),
  },
];

export function MetroConfigDemo() {
  return <>{contracts.map(definition => <ContractCard definition={definition} key={definition.title} />)}</>;
}
