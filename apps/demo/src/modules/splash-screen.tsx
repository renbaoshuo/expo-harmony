/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as SplashScreen from 'expo-splash-screen';
import { useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { readSplashOptions, saveSplashOptions } from '../splash-options';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { optionalNumber, Toggle } from './visual-controls';

export function SplashScreenDemo() {
  const action = useAsyncResult();
  const [saved] = useState(readSplashOptions);
  const [duration, setDuration] = useState(String(saved?.duration ?? 400));
  const [fade, setFade] = useState(saved?.fade ?? true);
  const busy = action.state.phase === 'running';

  if (Platform.OS === 'web') return null;

  return (
    <Panel title="启动屏">
      <Field label="淡出时长（毫秒）" keyboardType="number-pad" value={duration} onChangeText={setDuration} />
      <Toggle label="淡出" value={fade} onChange={setFade} />
      <ActionRow>
        <ActionButton
          disabled={busy}
          label="应用到下次启动"
          onPress={() => void action.run(() => {
            const options = { duration: optionalNumber(duration, '时长'), fade };
            SplashScreen.setOptions(options);
            saveSplashOptions(options);
            return json(options);
          })}
        />
        <ActionButton disabled={busy} label="阻止自动隐藏" onPress={() => void action.run(async () => String(await SplashScreen.preventAutoHideAsync()))} tone="secondary" />
        <ActionButton
          disabled={busy}
          label="隐藏（hide）"
          onPress={() => void action.run(() => {
            SplashScreen.hide();
            return 'hide()';
          })}
          tone="secondary"
        />
        <ActionButton
          disabled={busy}
          label="隐藏（hideAsync）"
          onPress={() => void action.run(async () => {
            await SplashScreen.hideAsync();
            return 'hideAsync()';
          })}
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}
