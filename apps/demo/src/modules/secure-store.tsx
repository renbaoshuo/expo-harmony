/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as SecureStore from 'expo-secure-store';
import { useState } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';

const SERVICE = 'expo-harmony-demo.secure-store';
const accessibility = {
  WHEN_UNLOCKED: SecureStore.WHEN_UNLOCKED,
  WHEN_UNLOCKED_THIS_DEVICE_ONLY: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
  AFTER_FIRST_UNLOCK: SecureStore.AFTER_FIRST_UNLOCK,
  AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY,
  WHEN_PASSCODE_SET_THIS_DEVICE_ONLY: SecureStore.WHEN_PASSCODE_SET_THIS_DEVICE_ONLY,
  ALWAYS: SecureStore.ALWAYS,
  ALWAYS_THIS_DEVICE_ONLY: SecureStore.ALWAYS_THIS_DEVICE_ONLY,
};
const harmony = String(Platform.OS) === 'harmony';

export function SecureStoreDemo() {
  const [key, setKey] = useState('message');
  const [value, setValue] = useState('你好，安全存储');
  const [service, setService] = useState(SERVICE);
  const [prompt, setPrompt] = useState('验证身份以读取演示数据');
  const [accessGroup, setAccessGroup] = useState('');
  const [requiresAuthentication, setRequiresAuthentication] = useState(false);
  const [policy, setPolicy] = useState<keyof typeof accessibility>('WHEN_UNLOCKED');
  const action = useAsyncResult();
  const availability = useAsyncResult();
  const busy = action.state.phase === 'running';
  const options: SecureStore.SecureStoreOptions = {
    keychainService: service || undefined,
    requireAuthentication: requiresAuthentication,
    authenticationPrompt: requiresAuthentication ? prompt : undefined,
    keychainAccessible: harmony || Platform.OS === 'ios' ? accessibility[policy] : undefined,
    accessGroup: Platform.OS === 'ios' ? accessGroup || undefined : undefined,
  };

  return (
    <>
      <Panel title="存储选项">
        <Field label="服务名 keychainService" onChangeText={setService} value={service} />
        <Field label="键" onChangeText={setKey} testID="secure-store-key" value={key} />
        <Field label="值" multiline onChangeText={setValue} testID="secure-store-value" value={value} />
        <ActionButton
          label={requiresAuthentication ? '关闭生物认证' : '要求生物认证'}
          onPress={() => setRequiresAuthentication(value => !value)}
          tone={requiresAuthentication ? 'primary' : 'secondary'}
        />
        {requiresAuthentication ? <Field label="认证提示 authenticationPrompt" onChangeText={setPrompt} value={prompt} /> : null}
        {Platform.OS === 'ios' ? <Field label="访问组 accessGroup" onChangeText={setAccessGroup} value={accessGroup} /> : null}
        {harmony || Platform.OS === 'ios'
          ? (
              <ActionRow>
                {(Object.keys(accessibility) as (keyof typeof accessibility)[]).map(name => (
                  <ActionButton key={name} label={name} onPress={() => setPolicy(name)} tone={policy === name ? 'primary' : 'secondary'} />
                ))}
              </ActionRow>
            )
          : null}
        <ActionRow>
          <ActionButton
            disabled={busy}
            label="异步写入"
            onPress={() => void action.run(async () => {
              await SecureStore.setItemAsync(key, value, options);
              return '已写入';
            })}
            testID="secure-store-write"
          />
          <ActionButton disabled={busy} label="异步读取" onPress={() => void action.run(async () => json(await SecureStore.getItemAsync(key, options)))} testID="secure-store-read" />
          <ActionButton
            disabled={busy || (harmony && requiresAuthentication)}
            label="同步写入"
            onPress={() => void action.run(() => {
              SecureStore.setItem(key, value, options);
              return '已写入';
            })}
            testID="secure-store-write-sync"
            tone="secondary"
          />
          <ActionButton disabled={busy || (harmony && requiresAuthentication)} label="同步读取" onPress={() => void action.run(() => json(SecureStore.getItem(key, options)))} testID="secure-store-read-sync" tone="secondary" />
          <ActionButton
            disabled={busy}
            label="删除"
            onPress={() => void action.run(async () => {
              await SecureStore.deleteItemAsync(key, options);
              return '已删除';
            })}
            testID="secure-store-delete"
            tone="danger"
          />
        </ActionRow>
        <ResultPanel state={action.state} />
      </Panel>

      <Panel title="设备能力">
        <ActionRow>
          <ActionButton label="isAvailableAsync()" onPress={() => void availability.run(async () => json(await SecureStore.isAvailableAsync()))} />
          <ActionButton label="canUseBiometricAuthentication()" onPress={() => void availability.run(() => json(SecureStore.canUseBiometricAuthentication()))} tone="secondary" />
        </ActionRow>
        <ResultPanel state={availability.state} />
      </Panel>
    </>
  );
}
