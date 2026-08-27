import { router, Stack, useLocalSearchParams, usePathname, useSegments } from 'expo-router';
import { Text } from 'react-native';

import { ActionButton, DataRow, LabScreen, Panel } from '../../src/ui';

export default function RouterFixture() {
  const params = useLocalSearchParams<{ value?: string; source?: string }>();
  const pathname = usePathname();
  const segments = useSegments();

  return (
    <>
      <Stack.Screen options={{ title: '路由测试' }} />
      <LabScreen description="仅由 Expo Router 演示页使用的包内专属目标页。" kicker="@expo-harmony/expo-router" title="动态路由">
        <Panel eyebrow="路由状态" title="解码后的路径与查询参数">
          <DataRow label="pathname" value={pathname} />
          <DataRow label="segments" value={segments.join(' / ')} />
          <DataRow label="value" value={params.value ?? '缺失'} />
          <DataRow label="source" value={params.source ?? '缺失'} />
          <Text selectable>{JSON.stringify(params, null, 2)}</Text>
          <ActionButton label="返回" onPress={() => router.back()} />
        </Panel>
      </LabScreen>
    </>
  );
}
