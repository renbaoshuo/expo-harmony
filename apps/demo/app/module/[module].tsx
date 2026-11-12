/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { router, Stack, useLocalSearchParams } from 'expo-router';

import { findModule } from '../../src/catalog';
import { ModuleDemo } from '../../src/module-demo';
import { ActionButton, LabScreen } from '../../src/ui';

export default function ModuleScreen() {
  const params = useLocalSearchParams<{ module?: string | string[] }>();
  const module = findModule(params.module);

  if (!module) {
    return (
      <>
        <Stack.Screen options={{ title: '未找到模块' }} />
        <LabScreen>
          <ActionButton label="返回模块列表" onPress={() => router.replace('/')} />
        </LabScreen>
      </>
    );
  }

  return (
    <>
      <Stack.Screen options={{ title: module.title }} />
      <LabScreen testID={`module-${module.id}`}>
        <ModuleDemo key={module.id} id={module.id} />
      </LabScreen>
    </>
  );
}
