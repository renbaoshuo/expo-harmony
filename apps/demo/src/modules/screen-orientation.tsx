/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { deviceType, DeviceType } from 'expo-device';
import * as ScreenOrientation from 'expo-screen-orientation';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { Cycle } from './visual-controls';

const { Orientation, OrientationLock, WebOrientationLock } = ScreenOrientation;
const locks = [
  'DEFAULT', 'ALL', 'PORTRAIT', 'PORTRAIT_UP', 'PORTRAIT_DOWN', 'LANDSCAPE', 'LANDSCAPE_LEFT', 'LANDSCAPE_RIGHT',
] as const;
const desktop = String(Platform.OS) === 'harmony' && deviceType === DeviceType.DESKTOP;

export function ScreenOrientationDemo() {
  const [lock, setLock] = useState<(typeof locks)[number]>('PORTRAIT_UP');
  const [platformValue, setPlatformValue] = useState(Platform.OS === 'ios' ? '[1]' : '1');
  const [webLock, setWebLock] = useState(WebOrientationLock.PORTRAIT);
  const [listening, setListening] = useState(false);
  const [event, setEvent] = useState<ScreenOrientation.OrientationChangeEvent>();
  const subscription = useRef<ScreenOrientation.Subscription | null>(null);
  const pending = useRef<Promise<void> | null>(null);
  const changed = useRef(false);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  useEffect(() => () => {
    if (subscription.current) ScreenOrientation.removeOrientationChangeListener(subscription.current);
    if (changed.current) {
      void Promise.resolve(pending.current)
        .catch(() => undefined)
        .then(() => ScreenOrientation.unlockAsync())
        .catch(console.warn);
    }
  }, []);

  const apply = (operation: () => Promise<void>, output: string) => void action.run(async () => {
    pending.current = operation();
    changed.current = true;
    await pending.current;

    return output;
  });

  const lockPlatform = () => apply(() => {
    if (Platform.OS === 'ios') return ScreenOrientation.lockPlatformAsync({ screenOrientationArrayIOS: JSON.parse(platformValue) });
    if (Platform.OS === 'android') return ScreenOrientation.lockPlatformAsync({ screenOrientationConstantAndroid: Number(platformValue) });
    return ScreenOrientation.lockPlatformAsync({ screenOrientationLockWeb: webLock });
  }, '已应用方向设置');

  return (
    <>
      <Panel title="屏幕方向">
        <ActionRow>
          <ActionButton disabled={busy} label="读取当前方向" onPress={() => void action.run(async () => Orientation[await ScreenOrientation.getOrientationAsync()] ?? '')} testID="screen-orientation-read" />
          <ActionButton disabled={busy} label="读取锁定策略" onPress={() => void action.run(async () => OrientationLock[await ScreenOrientation.getOrientationLockAsync()] ?? '')} tone="secondary" />
          <ActionButton disabled={busy} label="读取平台方向设置" onPress={() => void action.run(async () => json(await ScreenOrientation.getPlatformOrientationLockAsync()))} tone="secondary" />
        </ActionRow>
        <Cycle label="方向" value={lock} choices={locks} onChange={setLock} />
        <ActionRow>
          <ActionButton disabled={busy || desktop} label="锁定方向" onPress={() => apply(() => ScreenOrientation.lockAsync(OrientationLock[lock]), lock)} testID="screen-orientation-lock" />
          <ActionButton disabled={busy || desktop} label="解除锁定" onPress={() => apply(ScreenOrientation.unlockAsync, '已解除方向锁定')} tone="secondary" />
          <ActionButton disabled={busy} label="查询是否支持" onPress={() => void action.run(async () => json(await ScreenOrientation.supportsOrientationLockAsync(OrientationLock[lock])))} tone="secondary" />
        </ActionRow>
        {Platform.OS === 'ios' || Platform.OS === 'android'
          ? (
              <Field label={Platform.OS === 'ios' ? 'screenOrientationArrayIOS' : 'screenOrientationConstantAndroid'} value={platformValue} onChangeText={setPlatformValue} />
            )
          : null}
        {Platform.OS === 'web' ? <Cycle label="Web 方向" value={webLock} choices={Object.values(WebOrientationLock).filter(value => value !== WebOrientationLock.UNKNOWN)} onChange={setWebLock} /> : null}
        {Platform.OS === 'ios' || Platform.OS === 'android' || Platform.OS === 'web'
          ? (
              <ActionButton disabled={busy} label="应用平台方向设置" onPress={lockPlatform} tone="secondary" />
            )
          : null}
        <ResultPanel state={action.state} />
      </Panel>
      <Panel title="方向变化">
        <ActionRow>
          <ActionButton
            disabled={listening}
            label="监听方向变化"
            onPress={() => {
              subscription.current = ScreenOrientation.addOrientationChangeListener(setEvent);
              setListening(true);
            }}
          />
          <ActionButton
            disabled={!listening}
            label="移除监听"
            onPress={() => {
              if (subscription.current) ScreenOrientation.removeOrientationChangeListener(subscription.current);
              subscription.current = null;
              setListening(false);
            }}
            tone="secondary"
          />
          <ActionButton
            disabled={!listening}
            label="移除所有监听"
            onPress={() => {
              ScreenOrientation.removeOrientationChangeListeners();
              subscription.current = null;
              setListening(false);
            }}
            tone="secondary"
          />
        </ActionRow>
        {event ? <DataRow label="最近事件" value={json(event)} /> : null}
      </Panel>
    </>
  );
}
