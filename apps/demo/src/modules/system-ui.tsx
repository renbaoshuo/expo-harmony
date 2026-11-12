/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as SystemUI from 'expo-system-ui';
import { useEffect, useRef, useState } from 'react';
import { processColor, StyleSheet, View, type ColorValue } from 'react-native';

import { json } from '../format';
import { palette } from '../theme';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

export function SystemUIDemo() {
  const action = useAsyncResult();
  const initial = useRef<{ color: ColorValue | null } | null>(null);
  const mounted = useRef(true);
  const pending = useRef<Promise<void> | null>(null);
  const [color, setColor] = useState('#72D8FF');
  const [preview, setPreview] = useState<ColorValue | null>(palette.canvas);
  const busy = action.state.phase === 'running';

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      const restore = () => initial.current && SystemUI.setBackgroundColorAsync(initial.current.color);
      void Promise.resolve(pending.current).catch(() => undefined).then(restore).catch(console.warn);
    };
  }, []);

  const apply = (value: ColorValue | null) => void action.run(async () => {
    if (value !== null && processColor(value) == null) throw new Error('请输入有效颜色。');
    initial.current ??= { color: await SystemUI.getBackgroundColorAsync() };
    if (!mounted.current) return '';
    pending.current = SystemUI.setBackgroundColorAsync(value);
    await pending.current;
    setPreview(value);

    return json(value);
  });

  return (
    <Panel title="根视图背景色">
      <View accessibilityLabel="背景色预览" style={[styles.preview, { backgroundColor: preview ?? palette.surfaceRaised }]} />
      <Field label="颜色" value={color} onChangeText={setColor} />
      <ActionRow>
        <ActionButton disabled={busy} label="设置背景色" onPress={() => apply(color)} testID="system-ui-set-background" />
        <ActionButton disabled={busy} label="清除背景色" onPress={() => apply(null)} testID="system-ui-reset-background" tone="secondary" />
        <ActionButton
          disabled={busy}
          label="读取背景色"
          onPress={() => void action.run(async () => {
            const value = await SystemUI.getBackgroundColorAsync();
            setPreview(value);
            return json(value);
          })}
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

const styles = StyleSheet.create({
  preview: { borderColor: palette.line, borderRadius: 12, borderWidth: StyleSheet.hairlineWidth, height: 76 },
});
