/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as ScreenCapture from 'expo-screen-capture';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { Cycle, optionalNumber } from './visual-controls';

function Protection({ captureKey }: { captureKey: string }) {
  ScreenCapture.usePreventScreenCapture(captureKey);
  return null;
}

function ScreenshotListener({ onScreenshot }: { onScreenshot: () => void }) {
  ScreenCapture.useScreenshotListener(onScreenshot);
  return null;
}

export function ScreenCaptureDemo() {
  const [permissionMode, setPermissionMode] = useState<'手动' | '查询' | '请求'>('查询');
  const [key, setKey] = useState('A');
  const [active, setActive] = useState<string[]>([]);
  const [hookKey, setHookKey] = useState<string | null>(null);
  const [listening, setListening] = useState(false);
  const [hook, setHook] = useState(false);
  const [events, setEvents] = useState(0);
  const [hookEvents, setHookEvents] = useState(0);
  const [blur, setBlur] = useState('0.5');
  const subscription = useRef<ScreenCapture.Subscription | null>(null);
  const keys = useRef(new Set<string>());
  const appSwitcher = useRef<Promise<void> | null>(null);
  const action = useAsyncResult();
  const switcher = useAsyncResult();
  const busy = action.state.phase === 'running' || switcher.state.phase === 'running';
  const screenshot = useCallback(() => setHookEvents(count => count + 1), []);

  useEffect(() => () => {
    subscription.current?.remove();
    for (const key of keys.current) {
      void ScreenCapture.allowScreenCaptureAsync(key).catch(console.warn);
    }
    if (appSwitcher.current) {
      void appSwitcher.current
        .catch(() => undefined)
        .then(ScreenCapture.disableAppSwitcherProtectionAsync)
        .catch(console.warn);
    }
  }, []);

  const protect = (prevent: boolean) => void action.run(async () => {
    const label = key.trim();
    if (!label) throw new Error('请输入保护标识。');
    const captureKey = `demo-screen-capture:${label}`;

    if (prevent) {
      keys.current.add(captureKey);
      await ScreenCapture.preventScreenCaptureAsync(captureKey);
      setActive(values => values.includes(label) ? values : [...values, label]);
    } else {
      await ScreenCapture.allowScreenCaptureAsync(captureKey);
      keys.current.delete(captureKey);
      setActive(values => values.filter(value => value !== label));
    }

    return prevent ? `已启用 ${label}` : `已解除 ${label}`;
  });

  return (
    <>
      <Panel title="截图保护">
        <Field editable={!busy} label="保护标识（key）" value={key} onChangeText={setKey} />
        <DataRow label="已启用的标识" value={active.join('、') || '无'} />
        <ActionRow>
          <ActionButton disabled={busy} label="禁止截图" onPress={() => protect(true)} testID="screen-capture-prevent" />
          <ActionButton disabled={busy} label="允许截图" onPress={() => protect(false)} testID="screen-capture-allow" tone="secondary" />
          <ActionButton disabled={busy || (!hookKey && !key.trim())} label={hookKey ? '移除保护 Hook' : '启用保护 Hook'} onPress={() => setHookKey(value => value ? null : `demo-screen-capture-hook:${key.trim()}`)} tone="secondary" />
          <ActionButton disabled={busy} label="查询可用性" onPress={() => void action.run(async () => json(await ScreenCapture.isAvailableAsync()))} tone="secondary" />
        </ActionRow>
        {hookKey ? <Protection captureKey={hookKey} /> : null}
        <ResultPanel state={action.state} />
      </Panel>
      <Panel title="截图事件">
        <DataRow label="手动监听收到的次数" value={events} />
        <DataRow label="Hook 收到的次数" value={hookEvents} />
        <ActionRow>
          <ActionButton
            label={listening ? '移除监听' : '监听截图'}
            onPress={() => {
              if (subscription.current) {
                ScreenCapture.removeScreenshotListener(subscription.current);
                subscription.current = null;
                setListening(false);
              } else {
                subscription.current = ScreenCapture.addScreenshotListener(() => setEvents(count => count + 1));
                setListening(true);
              }
            }}
          />
          <ActionButton label={hook ? '移除监听 Hook' : '启用监听 Hook'} onPress={() => setHook(value => !value)} tone="secondary" />
        </ActionRow>
        {hook ? <ScreenshotListener onScreenshot={screenshot} /> : null}
      </Panel>
      <Panel title="截图权限">
        <Cycle label="打开权限示例时" value={permissionMode} choices={['手动', '查询', '请求']} onChange={setPermissionMode} />
        <PermissionDemo key={permissionMode} getOnMount={permissionMode === '查询'} requestOnMount={permissionMode === '请求'} />
      </Panel>
      {Platform.OS === 'ios'
        ? (
            <Panel title="应用切换器保护">
              <Field label="模糊强度（0 到 1）" value={blur} onChangeText={setBlur} keyboardType="decimal-pad" />
              <ActionRow>
                <ActionButton
                  disabled={busy}
                  label="启用切换器保护"
                  onPress={() => void switcher.run(async () => {
                    appSwitcher.current = ScreenCapture.enableAppSwitcherProtectionAsync(optionalNumber(blur, '模糊强度'));
                    await appSwitcher.current;
                    return '已启用切换器保护';
                  })}
                />
                <ActionButton
                  disabled={busy}
                  label="关闭切换器保护"
                  onPress={() => void switcher.run(async () => {
                    await ScreenCapture.disableAppSwitcherProtectionAsync();
                    appSwitcher.current = null;
                    return '已关闭切换器保护';
                  })}
                  tone="secondary"
                />
              </ActionRow>
              <ResultPanel state={switcher.state} />
            </Panel>
          )
        : null}
    </>
  );
}

function PermissionDemo({ getOnMount, requestOnMount }: { getOnMount: boolean; requestOnMount: boolean }) {
  const [permission, request, get] = ScreenCapture.usePermissions({ get: getOnMount, request: requestOnMount });
  const result = useAsyncResult();
  const busy = result.state.phase === 'running';

  return (
    <>
      <DataRow label="usePermissions" value={permission?.status ?? '未读取'} />
      <ActionRow>
        <ActionButton disabled={busy} label="查询权限" onPress={() => void result.run(async () => json(await ScreenCapture.getPermissionsAsync()))} tone="secondary" />
        <ActionButton disabled={busy} label="请求权限" onPress={() => void result.run(async () => json(await ScreenCapture.requestPermissionsAsync()))} />
        <ActionButton disabled={busy} label="Hook 查询" onPress={() => void result.run(async () => json(await get()))} tone="secondary" />
        <ActionButton disabled={busy} label="Hook 请求" onPress={() => void result.run(async () => json(await request()))} tone="secondary" />
      </ActionRow>
      <ResultPanel state={result.state} />
    </>
  );
}
