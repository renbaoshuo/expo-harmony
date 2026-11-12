/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Brightness from 'expo-brightness';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { Cycle, optionalNumber } from './visual-controls';

const { AUTOMATIC, MANUAL } = Brightness.BrightnessMode;
const modes = { 自动: AUTOMATIC, 手动: MANUAL } as const;

export function BrightnessDemo() {
  const [askOnMount, setAskOnMount] = useState<'手动' | '查询' | '请求'>('查询');
  const [input, setInput] = useState('0.5');
  const [listening, setListening] = useState(false);
  const [event, setEvent] = useState<Brightness.BrightnessEvent>();
  const [mode, setMode] = useState<keyof typeof modes>('手动');
  const [saved, setSaved] = useState<number>();
  const initial = useRef<number | undefined>(undefined);
  const pending = useRef<Promise<void> | undefined>(undefined);
  const mounted = useRef(true);
  const action = useAsyncResult();
  const system = useAsyncResult();
  const busy = action.state.phase === 'running' || system.state.phase === 'running';

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      const restore = async () => {
        if (initial.current === undefined) return;
        if (Platform.OS === 'android') await Brightness.restoreSystemBrightnessAsync();
        else await Brightness.setBrightnessAsync(initial.current);
      };
      void Promise.resolve(pending.current).catch(() => undefined).then(restore).catch(console.warn);
    };
  }, []);

  useEffect(() => {
    if (!listening) return;

    const subscription = Brightness.addBrightnessListener(setEvent);
    return () => subscription.remove();
  }, [listening]);

  const value = () => {
    const brightness = optionalNumber(input, '亮度');
    if (brightness === undefined) throw new Error('请输入亮度。');
    return brightness;
  };

  const write = (readValue: () => number, setter = Brightness.setBrightnessAsync) => action.run(async () => {
    const brightness = readValue();
    if (initial.current === undefined) {
      initial.current = await Brightness.getBrightnessAsync();
      if (!mounted.current) return '';
      setSaved(initial.current);
    }
    pending.current = setter(brightness);
    await pending.current;

    return json(brightness);
  });

  return (
    <>
      <Panel title="应用亮度">
        <Field label="亮度（0 到 1）" keyboardType="decimal-pad" value={input} onChangeText={setInput} />
        <ActionRow>
          <ActionButton disabled={busy} label="查询可用性" onPress={() => void action.run(async () => json(await Brightness.isAvailableAsync()))} tone="secondary" />
          <ActionButton disabled={busy} label="读取亮度" onPress={() => void action.run(async () => json(await Brightness.getBrightnessAsync()))} testID="brightness-read" tone="secondary" />
          <ActionButton disabled={busy} label="设置亮度" onPress={() => void write(value)} testID="brightness-write" />
          <ActionButton
            disabled={busy || saved === undefined}
            label="恢复原亮度"
            onPress={() => {
              if (saved !== undefined) void write(() => saved);
            }}
            tone="secondary"
          />
        </ActionRow>
        {String(Platform.OS) === 'harmony'
          ? (
              <ActionRow>
                <ActionButton
                  disabled={busy}
                  label="getSystemBrightnessAsync"
                  onPress={() => void action.run(async () => json(await Brightness.getSystemBrightnessAsync()))}
                  tone="secondary"
                />
                <ActionButton
                  disabled={busy}
                  label="setSystemBrightnessAsync"
                  onPress={() => void write(value, Brightness.setSystemBrightnessAsync)}
                  tone="secondary"
                />
              </ActionRow>
            )
          : null}
        {saved === undefined ? null : <DataRow label="原亮度" value={saved} />}
        <ResultPanel state={action.state} />
      </Panel>
      {Platform.OS === 'android'
        ? (
            <Panel title="系统亮度">
              <Cycle label="调节方式" value={mode} choices={['手动', '自动']} onChange={setMode} />
              <ActionRow>
                <ActionButton disabled={busy} label="读取系统亮度" onPress={() => void system.run(async () => json(await Brightness.getSystemBrightnessAsync()))} tone="secondary" />
                <ActionButton
                  disabled={busy}
                  label="设置系统亮度"
                  onPress={() => void system.run(async () => {
                    const brightness = value();
                    await Brightness.setSystemBrightnessAsync(brightness);
                    return json(brightness);
                  })}
                />
                <ActionButton
                  disabled={busy}
                  label="恢复使用系统亮度"
                  onPress={() => void system.run(async () => {
                    await Brightness.restoreSystemBrightnessAsync();
                    return '已恢复使用系统亮度';
                  })}
                  tone="secondary"
                />
                <ActionButton disabled={busy} label="查询是否使用系统亮度" onPress={() => void system.run(async () => json(await Brightness.isUsingSystemBrightnessAsync()))} tone="secondary" />
                <ActionButton disabled={busy} label="读取调节方式" onPress={() => void system.run(async () => Brightness.BrightnessMode[await Brightness.getSystemBrightnessModeAsync()] ?? '')} tone="secondary" />
                <ActionButton
                  disabled={busy}
                  label="设置调节方式"
                  onPress={() => void system.run(async () => {
                    await Brightness.setSystemBrightnessModeAsync(modes[mode]);
                    return mode;
                  })}
                />
              </ActionRow>
              <ResultPanel state={system.state} />
            </Panel>
          )
        : null}
      <Panel title="亮度权限">
        <Cycle label="打开权限示例时" value={askOnMount} choices={['手动', '查询', '请求']} onChange={setAskOnMount} />
        <PermissionDemo key={askOnMount} getOnMount={askOnMount === '查询'} requestOnMount={askOnMount === '请求'} />
      </Panel>
      {Platform.OS === 'ios'
        ? (
            <Panel title="亮度变化">
              <ActionButton label={listening ? '移除监听' : '监听亮度变化'} onPress={() => setListening(value => !value)} tone="secondary" />
              {event ? <DataRow label="最近亮度" value={event.brightness} /> : null}
            </Panel>
          )
        : null}
    </>
  );
}

function PermissionDemo({ getOnMount, requestOnMount }: { getOnMount: boolean; requestOnMount: boolean }) {
  const [permission, request, get] = Brightness.usePermissions({ get: getOnMount, request: requestOnMount });
  const result = useAsyncResult();
  const busy = result.state.phase === 'running';

  return (
    <>
      <DataRow label="usePermissions" value={permission?.status ?? '未读取'} />
      <ActionRow>
        <ActionButton disabled={busy} label="查询权限" onPress={() => void result.run(async () => json(await Brightness.getPermissionsAsync()))} tone="secondary" />
        <ActionButton disabled={busy} label="请求权限" onPress={() => void result.run(async () => json(await Brightness.requestPermissionsAsync()))} />
        <ActionButton disabled={busy} label="Hook 查询" onPress={() => void result.run(async () => json(await get()))} tone="secondary" />
        <ActionButton disabled={busy} label="Hook 请求" onPress={() => void result.run(async () => json(await request()))} tone="secondary" />
      </ActionRow>
      <ResultPanel state={result.state} />
    </>
  );
}
