import { router, usePathname, useSegments } from 'expo-router';
import { ActionButton, DataRow, Note, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

export function RouterDemo() {
  const pathname = usePathname();
  const segments = useSegments();
  const state = useAsyncResult();

  return (
    <>
      <Panel eyebrow="当前路由" title="读取基于文件的路由状态">
        <DataRow label="pathname" value={pathname} />
        <DataRow label="segments" value={segments.join(' / ')} />
        <ActionButton
          label="校验路由状态"
          onPress={() => void state.run(() => {
            if (pathname !== '/module/expo-router') throw new Error(`路径不符合预期：${pathname}`);
            if (!segments.includes('[module]')) throw new Error(`缺少动态路由分段：${segments.join('/')}`);
            return json({ pathname, segments });
          })}
        />
        <ResultPanel state={state.state} />
      </Panel>
      <Panel eyebrow="动态目标页" title="推送 Unicode 路径与查询参数">
        <ActionButton
          label="打开动态路由"
          onPress={() => router.push('/router-fixture/中文?source=expo-router')}
          testID="router-open-dynamic-fixture"
        />
        <Note>该目标页仅限本包使用，不会出现在首页。</Note>
      </Panel>
    </>
  );
}
