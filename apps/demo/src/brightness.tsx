import * as Brightness from 'expo-brightness';
import { useEffect, useState } from 'react';
import { Platform } from 'react-native';

import { ActionButton, ActionRow, DataRow, Field, Note, Panel, ResultPanel, useAsyncResult } from './ui';

// Allow the rounding of a brightness value to the system's 0–255 scale.
const TOLERANCE = 1 / 255;

export function BrightnessDemo() {
  const [permission, request, get] = Brightness.usePermissions();
  const [input, setInput] = useState('0.5');
  const [level, setLevel] = useState<number | null>(null);
  const [saved, setSaved] = useState<number | null>(null);
  const [events, setEvents] = useState(0);
  const [listening, setListening] = useState(false);
  const access = useAsyncResult();
  const action = useAsyncResult();
  const checks = useAsyncResult();
  const busy = access.state.phase === 'running' || action.state.phase === 'running' || checks.state.phase === 'running';

  useEffect(() => {
    if (!listening) return;

    const subscription = Brightness.addBrightnessListener((event) => {
      setEvents(count => count + 1);
      setLevel(event.brightness);
    });

    return () => subscription.remove();
  }, [listening]);

  const read = () => action.run(async () => {
    const [available, value] = await Promise.all([
      Brightness.isAvailableAsync(),
      Brightness.getBrightnessAsync(),
    ]);
    setLevel(value);
    setSaved(previous => previous ?? value);

    return JSON.stringify({ available, brightness: value }, null, 2);
  });

  const write = (value: number) => action.run(async () => {
    await Brightness.setBrightnessAsync(value);

    const actual = await Brightness.getBrightnessAsync();
    setLevel(actual);

    return JSON.stringify({ requested: value, brightness: actual }, null, 2);
  });

  const restore = async (value: number) => {
    await Brightness.setBrightnessAsync(value);

    const actual = await Brightness.getBrightnessAsync();
    setLevel(actual);
    if (!Number.isFinite(actual) || Math.abs(actual - value) > TOLERANCE) {
      throw new Error(`恢复亮度失败：预期 ${value}，实际 ${actual}。`);
    }

    return actual;
  };

  const verify = () => checks.run(async () => {
    const initial = await Brightness.getBrightnessAsync();
    const rows: string[] = [];
    let restored: number;

    try {
      for (const value of [0, 0.25, 0.5, 0.75, 1, -1, 2]) {
        const expected = Math.max(0, Math.min(1, value));
        await Brightness.setBrightnessAsync(value);

        const actual = await Brightness.getBrightnessAsync();
        if (!Number.isFinite(actual) || Math.abs(actual - expected) > TOLERANCE) {
          throw new Error(`亮度 ${value}：预期 ${expected}，实际 ${actual}。`);
        }

        rows.push(`${value} → ${actual}：通过`);
      }

      for (const method of [Brightness.setBrightnessAsync, Brightness.setSystemBrightnessAsync]) {
        let rejected = false;
        try {
          await method(NaN);
        } catch (error) {
          if (!(error instanceof TypeError)) {
            throw new Error(`NaN 应被 TypeError 拒绝，实际为 ${String(error)}。`);
          }
          rejected = true;
        }

        if (!rejected) throw new Error('NaN 未被拒绝。');
      }
      rows.push('两个亮度 setter 均拒绝 NaN：通过');

      await Brightness.setBrightnessAsync(0.5);
      const recovered = await Brightness.getBrightnessAsync();
      if (!Number.isFinite(recovered) || Math.abs(recovered - 0.5) > TOLERANCE) {
        throw new Error(`非法输入后无法继续读写亮度：${recovered}。`);
      }
      rows.push('非法输入后继续读写：通过');
    } finally {
      restored = await restore(initial);
    }

    return `${rows.join('\n')}\n恢复后的亮度数值：${restored}`;
  });

  const system = () => checks.run(async () => {
    const initial = await Brightness.getBrightnessAsync();
    let output: string;
    let restored: number;

    try {
      await Brightness.setSystemBrightnessAsync(0.5);
      await Brightness.restoreSystemBrightnessAsync();
      await Brightness.setSystemBrightnessModeAsync(Brightness.BrightnessMode.MANUAL);

      const [value, using, mode] = await Promise.all([
        Brightness.getSystemBrightnessAsync(),
        Brightness.isUsingSystemBrightnessAsync(),
        Brightness.getSystemBrightnessModeAsync(),
      ]);
      if (!Number.isFinite(value) || Math.abs(value - 0.5) > TOLERANCE
        || using || mode !== Brightness.BrightnessMode.UNKNOWN) {
        throw new Error(`非 Android 兼容行为不符：${JSON.stringify({ value, using, mode })}`);
      }

      output = JSON.stringify({ brightness: value, usingSystemBrightness: using, mode }, null, 2);
    } finally {
      restored = await restore(initial);
    }

    return `${output}\n恢复后的亮度数值：${restored}`;
  });

  return (
    <>
      <Panel eyebrow="权限" title="查询与请求亮度权限">
        <DataRow label="授权状态" value={permission?.status ?? '加载中'} />
        <DataRow label="已授权" value={String(permission?.granted ?? false)} />
        <ActionRow>
          <ActionButton disabled={busy} label="查询权限" onPress={() => void access.run(async () => JSON.stringify(await get(), null, 2))} testID="brightness-permissions" />
          <ActionButton disabled={busy} label="请求权限" onPress={() => void access.run(async () => JSON.stringify(await request(), null, 2))} testID="brightness-request" tone="secondary" />
        </ActionRow>
        <Note>HarmonyOS 当前窗口亮度无需授权，不会弹出权限对话框。</Note>
        <ResultPanel state={access.state} />
      </Panel>

      <Panel eyebrow="窗口亮度" title="读取、设置与恢复数值">
        <DataRow label="当前亮度" value={level === null ? '尚未读取' : level.toFixed(4)} />
        <DataRow label="首次读取值" value={saved === null ? '尚未保存' : saved.toFixed(4)} />
        <Field label="亮度值（0–1）" onChangeText={setInput} testID="brightness-input" value={input} />
        <ActionRow>
          <ActionButton disabled={busy} label="读取亮度" onPress={() => void read()} testID="brightness-read" />
          <ActionButton disabled={busy} label="设置亮度" onPress={() => void write(Number(input))} testID="brightness-write" tone="secondary" />
          <ActionButton
            disabled={busy || saved === null}
            label="恢复保存值"
            onPress={() => {
              if (saved !== null) void write(saved);
            }}
            testID="brightness-restore"
            tone="secondary"
          />
        </ActionRow>
        <Note>先读取可保存当前数值。窗口亮度只在前台获焦时生效；恢复数值不会恢复“跟随系统”。模拟器读写成功不代表物理屏幕亮度发生变化。</Note>
        <ResultPanel state={action.state} />
      </Panel>

      <Panel eyebrow="接口验证" title="数值边界与平台兼容行为">
        <ActionRow>
          <ActionButton disabled={busy} label="验证读写与边界" onPress={() => void verify()} testID="brightness-verify" />
          <ActionButton disabled={busy || Platform.OS === 'android'} label="验证非 Android 行为" onPress={() => void system()} testID="brightness-system" tone="secondary" />
        </ActionRow>
        <Note>测试会短暂调整亮度，并在结束或失败后恢复原数值。HarmonyOS 系统亮度接口沿用官方非 Android 分支，不修改系统亮度模式。</Note>
        <ResultPanel state={checks.state} />
      </Panel>

      <Panel eyebrow="事件" title="订阅与移除亮度监听">
        <DataRow label="正在监听" value={listening ? '是' : '否'} />
        <DataRow label="事件次数" value={String(events)} />
        <ActionButton disabled={busy} label={listening ? '移除监听' : '开始监听'} onPress={() => setListening(value => !value)} testID="brightness-listen" tone="secondary" />
        <Note>该事件在上游仅由 iOS 发送；HarmonyOS 可以订阅和移除，但不会发送事件。离开页面会自动移除监听。</Note>
      </Panel>
    </>
  );
}
