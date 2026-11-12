/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { router, useLocalSearchParams, usePathname, useSegments } from 'expo-router';
import { useState } from 'react';

import { json } from '../../src/format';
import { ActionButton, ActionRow, DataRow, Field, LabScreen, Panel } from '../../src/ui';

export default function RouterFixture() {
  const params = useLocalSearchParams<{ value?: string; source?: string }>();
  const pathname = usePathname();
  const segments = useSegments();
  const [source, setSource] = useState(params.source ?? '');
  const [count, setCount] = useState('1');
  const canGoBack = router.canGoBack();
  const canDismiss = router.canDismiss();

  return (
    <LabScreen>
      <Panel title="路由参数">
        <DataRow label="usePathname()" value={pathname} />
        <DataRow label="useSegments()" value={json(segments)} />
        <DataRow label="useLocalSearchParams()" value={json(params)} />
        <Field label="source" value={source} onChangeText={setSource} />
        <ActionButton label="setParams()" onPress={() => router.setParams({ source })} />
      </Panel>
      <Panel title="返回上一层">
        <DataRow label="canGoBack()" value={String(canGoBack)} />
        <DataRow label="canDismiss()" value={String(canDismiss)} />
        <Field label="要关闭的页面数" value={count} onChangeText={setCount} keyboardType="number-pad" />
        <ActionRow>
          <ActionButton label="back()" onPress={() => router.back()} disabled={!canGoBack} testID="router-fixture-back" />
          <ActionButton label="dismiss()" onPress={() => router.dismiss(Number(count))} disabled={!canDismiss || !/^[1-9]\d*$/.test(count)} />
          <ActionButton label="dismissAll()" onPress={() => router.dismissAll()} disabled={!canDismiss} />
          <ActionButton label="回到路由示例" onPress={() => router.dismissTo('/module/expo-router')} tone="secondary" />
        </ActionRow>
      </Panel>
    </LabScreen>
  );
}
