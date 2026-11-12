/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  Link, useFocusEffect, useGlobalSearchParams, useIsFocused, useLocalSearchParams, useNavigation,
  useNavigationContainerRef, usePathname, useRootNavigation, useRootNavigationState, useRouter, useSegments,
} from 'expo-router';
import { useCallback, useState } from 'react';

import { palette } from '../theme';
import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function RouterDemo() {
  const pathname = usePathname();
  const segments = useSegments();
  const localParams = useLocalSearchParams();
  const globalParams = useGlobalSearchParams();
  const router = useRouter();
  const [value, setValue] = useState('你好');
  const [source, setSource] = useState('expo-router');
  const [options, setOptions] = useState(() => json({
    relativeToDirectory: false,
    withAnchor: false,
    dangerouslySingular: false,
  }));
  const result = useAsyncResult();
  const href = { pathname: '/router-fixture/[value]' as const, params: { value, source } };

  function navigate(method: 'navigate' | 'push' | 'replace' | 'dismissTo') {
    void result.run(() => {
      router[method](href, JSON.parse(options));
      return json(href);
    });
  }

  return (
    <>
      <Panel title="当前路由">
        <DataRow label="usePathname()" value={pathname} />
        <DataRow label="useSegments()" value={json(segments)} />
        <DataRow label="useLocalSearchParams()" value={json(localParams)} />
        <DataRow label="useGlobalSearchParams()" value={json(globalParams)} />
      </Panel>
      <NavigationState />
      <Panel title="动态路由">
        <Field label="路径参数 value" value={value} onChangeText={setValue} />
        <Field label="查询参数 source" value={source} onChangeText={setSource} />
        <Field label="导航选项（JSON 对象）" value={options} onChangeText={setOptions} />
        <ActionRow>
          <ActionButton label="navigate()" onPress={() => navigate('navigate')} disabled={!value} />
          <ActionButton label="push()" onPress={() => navigate('push')} disabled={!value} testID="router-open-dynamic-fixture" />
          <ActionButton label="replace()" onPress={() => navigate('replace')} disabled={!value} />
          <ActionButton label="dismissTo()" onPress={() => navigate('dismissTo')} disabled={!value} />
          <ActionButton
            label="prefetch()"
            onPress={() => void result.run(() => {
              router.prefetch(href);
              return json(href);
            })}
            disabled={!value}
          />
          {value ? <Link href={href} style={{ color: palette.signal, padding: 12 }}>Link</Link> : null}
        </ActionRow>
        <ResultPanel state={result.state} />
      </Panel>
    </>
  );
}

function NavigationState() {
  const result = useAsyncResult();
  const navigation = useNavigation();
  const root = useRootNavigation();
  const ref = useNavigationContainerRef();
  const state = useRootNavigationState();
  const focused = useIsFocused();
  const [focusCount, setFocusCount] = useState(0);

  useFocusEffect(useCallback(() => setFocusCount(count => count + 1), []));

  return (
    <Panel title="导航状态">
      <DataRow label="useIsFocused()" value={String(focused)} />
      <DataRow label="useFocusEffect() 触发次数" value={focusCount} />
      <ActionRow>
        <ActionButton label="useNavigation()" onPress={() => void result.run(() => json(navigation.getState()))} />
        <ActionButton label="useRootNavigation()" onPress={() => void result.run(() => json(root?.getCurrentRoute()))} />
        <ActionButton label="useNavigationContainerRef()" onPress={() => void result.run(() => json(ref.isReady()))} />
        <ActionButton label="useRootNavigationState()" onPress={() => void result.run(() => json(state))} />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}
