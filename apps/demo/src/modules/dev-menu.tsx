/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { closeMenu, hideMenu, openMenu, registerDevMenuItems } from 'expo-dev-menu';
import { requireOptionalNativeModule } from 'expo-modules-core';
import { useEffect, useRef, useState } from 'react';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

interface Preferences {
  getPreferencesAsync(): Promise<Record<string, boolean>>;
  setPreferencesAsync(values: Record<string, unknown>): Promise<void>;
}

const callbacks = ['回调计数', 'closeMenu()', 'hideMenu()'] as const;

export function DevMenuDemo() {
  const result = useAsyncResult();
  const [name, setName] = useState('Demo 菜单项');
  const [collapse, setCollapse] = useState(false);
  const [callback, setCallback] = useState<typeof callbacks[number]>('回调计数');
  const [count, setCount] = useState(0);
  const registered = useRef(false);
  const busy = result.state.phase === 'running';

  useEffect(() => () => {
    if (registered.current) void registerDevMenuItems([]).catch(() => {});
  }, []);

  if (!__DEV__) return <Panel title="开发菜单仅在开发版本中可用" />;

  return (
    <>
      <Panel title="菜单项">
        <Field label="name" value={name} onChangeText={setName} />
        <ActionButton label={`shouldCollapse = ${collapse}`} tone={collapse ? 'primary' : 'secondary'} onPress={() => setCollapse(value => !value)} />
        <ActionRow>
          {callbacks.map(value => <ActionButton key={value} label={value} tone={callback === value ? 'primary' : 'secondary'} onPress={() => setCallback(value)} />)}
        </ActionRow>
        <ActionRow>
          <ActionButton
            label="registerDevMenuItems()"
            testID="menu-register"
            disabled={busy}
            onPress={() => void result.run(async () => {
              await registerDevMenuItems([{
                name,
                shouldCollapse: collapse,
                callback: () => {
                  setCount(value => value + 1);
                  if (callback === 'closeMenu()') closeMenu();
                  if (callback === 'hideMenu()') hideMenu();
                },
              }]);
              registered.current = true;
              return name;
            })}
          />
          <ActionButton
            label="移除自定义菜单项"
            testID="menu-clear"
            disabled={busy}
            onPress={() => void result.run(async () => {
              await registerDevMenuItems([]);
              registered.current = false;
              return '已移除自定义菜单项';
            })}
          />
          <ActionButton label="openMenu()" testID="devtools-open-menu" onPress={openMenu} />
        </ActionRow>
        <DataRow label="回调次数" value={count} />
        <ResultPanel state={result.state} />
      </Panel>
      <MenuPreferences />
    </>
  );
}

function MenuPreferences() {
  const preferences = requireOptionalNativeModule<Preferences>('DevMenuPreferences');
  const result = useAsyncResult();
  const [values, setValues] = useState('{"showFloatingActionButton": true}');
  const disabled = !preferences || result.state.phase === 'running';

  return (
    <Panel title="菜单偏好">
      <Field label="要更新的设置（JSON 对象）" value={values} onChangeText={setValues} multiline />
      <ActionRow>
        <ActionButton label="getPreferencesAsync()" disabled={disabled} onPress={() => void result.run(async () => json(await preferences?.getPreferencesAsync()))} />
        <ActionButton
          label="setPreferencesAsync()"
          disabled={disabled}
          onPress={() => void result.run(async () => {
            await preferences?.setPreferencesAsync(JSON.parse(values));
            return '已保存设置';
          })}
        />
      </ActionRow>
      <ResultPanel state={result.state} />
    </Panel>
  );
}
