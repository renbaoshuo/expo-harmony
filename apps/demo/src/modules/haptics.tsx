/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Haptics from 'expo-haptics';
import { Platform } from 'react-native';

import { ActionButton, ActionRow, Panel, ResultPanel, useAsyncResult } from '../ui';

const impacts = {
  [Haptics.ImpactFeedbackStyle.Light]: '轻',
  [Haptics.ImpactFeedbackStyle.Medium]: '中',
  [Haptics.ImpactFeedbackStyle.Heavy]: '重',
  [Haptics.ImpactFeedbackStyle.Soft]: '柔和',
  [Haptics.ImpactFeedbackStyle.Rigid]: '硬朗',
};

const notifications = {
  [Haptics.NotificationFeedbackType.Success]: '成功',
  [Haptics.NotificationFeedbackType.Warning]: '警告',
  [Haptics.NotificationFeedbackType.Error]: '错误',
};

export function HapticsDemo() {
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  const trigger = (label: string, run: () => Promise<void>) => void action.run(async () => {
    await run();
    return label;
  });

  return (
    <>
      <Panel title="碰撞反馈">
        <ActionRow>
          <ActionButton disabled={busy} label="默认强度" onPress={() => trigger('默认碰撞反馈', () => Haptics.impactAsync())} />
          {Object.values(Haptics.ImpactFeedbackStyle).map(style => (
            <ActionButton key={style} disabled={busy} label={impacts[style]} onPress={() => trigger(style, () => Haptics.impactAsync(style))} tone="secondary" />
          ))}
        </ActionRow>
      </Panel>
      <Panel title="通知反馈">
        <ActionRow>
          <ActionButton disabled={busy} label="默认反馈" onPress={() => trigger('默认通知反馈', () => Haptics.notificationAsync())} />
          {Object.values(Haptics.NotificationFeedbackType).map(type => (
            <ActionButton key={type} disabled={busy} label={notifications[type]} onPress={() => trigger(type, () => Haptics.notificationAsync(type))} tone="secondary" />
          ))}
        </ActionRow>
      </Panel>
      <Panel title="选择反馈">
        <ActionButton disabled={busy} label="触发选择反馈" onPress={() => trigger('选择反馈', Haptics.selectionAsync)} />
      </Panel>
      {Platform.OS === 'android'
        ? (
            <Panel title="Android 触感反馈">
              <ActionRow>
                {Object.values(Haptics.AndroidHaptics).map(type => (
                  <ActionButton key={type} disabled={busy} label={type} onPress={() => trigger(type, () => Haptics.performAndroidHapticsAsync(type))} tone="secondary" />
                ))}
              </ActionRow>
            </Panel>
          )
        : null}
      <ResultPanel state={action.state} />
    </>
  );
}
