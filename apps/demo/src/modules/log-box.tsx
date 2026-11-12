/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireOptionalNativeModule } from 'expo-modules-core';
import { useState } from 'react';
import { LogBox } from 'react-native';

import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

interface NativeLogBox {
  enabled: boolean;
  copyTextAsync(text: string): Promise<void>;
}

export function LogBoxDemo() {
  const logbox = requireOptionalNativeModule<NativeLogBox>('ExpoLogBox');
  const [message, setMessage] = useState('Expo Harmony 日志');
  const [text, setText] = useState('Expo Harmony LogBox');
  const result = useAsyncResult();

  return (
    <>
      <Panel title="日志">
        <Field label="日志内容" value={message} onChangeText={setMessage} multiline />
        <ActionRow>
          <ActionButton label="console.warn()" testID="devtools-warning" disabled={!__DEV__} onPress={() => console.warn(message)} />
          <ActionButton label="console.error()" testID="devtools-error" disabled={!__DEV__} onPress={() => console.error(message)} />
          <ActionButton
            label="抛出未捕获异常"
            testID="logbox-uncaught"
            disabled={!__DEV__}
            tone="danger"
            onPress={() => {
              throw new Error(message);
            }}
          />
        </ActionRow>
        <ActionRow>
          <ActionButton label="隐藏所有日志" disabled={!__DEV__} tone="secondary" onPress={() => LogBox.ignoreAllLogs(true)} />
          <ActionButton label="显示日志" disabled={!__DEV__} tone="secondary" onPress={() => LogBox.ignoreAllLogs(false)} />
        </ActionRow>
      </Panel>
      <Panel title="原生 LogBox">
        <DataRow label="enabled" value={logbox ? String(logbox.enabled) : '未加载'} />
        <Field label="text" value={text} onChangeText={setText} />
        <ActionButton
          label="copyTextAsync()"
          testID="logbox-copy"
          disabled={!logbox?.enabled || result.state.phase === 'running'}
          onPress={() => void result.run(async () => {
            await logbox?.copyTextAsync(text);
            return '已复制';
          })}
        />
        <ResultPanel state={result.state} />
      </Panel>
    </>
  );
}
