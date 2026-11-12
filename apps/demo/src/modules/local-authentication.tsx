/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as LocalAuthentication from 'expo-local-authentication';
import { useEffect, useRef, useState } from 'react';
import { Platform, Switch } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { SystemApiActions } from './system-api-actions';

const android = Platform.OS === 'android';
const ios = Platform.OS === 'ios';
const cancellable = android || String(Platform.OS) === 'harmony';

export function LocalAuthenticationDemo() {
  const [prompt, setPrompt] = useState('验证身份以继续');
  const [subtitle, setSubtitle] = useState('');
  const [description, setDescription] = useState('');
  const [cancelLabel, setCancelLabel] = useState('取消认证');
  const [fallbackLabel, setFallbackLabel] = useState('使用锁屏密码');
  const [disableFallback, setDisableFallback] = useState(false);
  const [requireConfirmation, setRequireConfirmation] = useState(true);
  const [strong, setStrong] = useState(false);
  const [cancelDelay, setCancelDelay] = useState('');
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const active = useRef(false);
  const auth = useAsyncResult();
  const cancel = useAsyncResult();
  const busy = auth.state.phase === 'running';
  const cancelling = cancel.state.phase === 'running';

  useEffect(() => () => {
    clearTimeout(timer.current);
    if (active.current && cancellable) {
      void LocalAuthentication.cancelAuthenticate().catch(() => {});
    }
  }, []);

  const stop = () => cancel.run(async () => {
    clearTimeout(timer.current);
    await LocalAuthentication.cancelAuthenticate();
    return '已请求取消认证';
  });

  const authenticate = () => auth.run(async () => {
    const delay = Number(cancelDelay);
    if (cancellable && cancelDelay.trim() && (!Number.isFinite(delay) || delay < 0.1 || delay > 60)) {
      throw new Error('取消延时须在 0.1 到 60 秒之间。');
    }

    active.current = true;
    cancel.clear();
    if (cancellable && delay > 0) {
      timer.current = setTimeout(() => {
        if (active.current) void stop();
      }, delay * 1000);
    }

    try {
      return json(await LocalAuthentication.authenticateAsync({
        promptMessage: prompt,
        cancelLabel,
        disableDeviceFallback: disableFallback,
        ...(cancellable ? { biometricsSecurityLevel: strong ? 'strong' : 'weak' } : {}),
        ...(android
          ? {
              promptSubtitle: subtitle || undefined,
              promptDescription: description || undefined,
              requireConfirmation,
            }
          : {}),
        ...(ios ? { fallbackLabel } : {}),
      }));
    } finally {
      clearTimeout(timer.current);
      active.current = false;
    }
  });

  return (
    <>
      <Panel title="认证能力">
        <SystemApiActions
          actions={[
            ['检查生物识别硬件', LocalAuthentication.hasHardwareAsync],
            ['查看支持的认证方式', async () => {
              const types = await LocalAuthentication.supportedAuthenticationTypesAsync();
              return types.map(type => LocalAuthentication.AuthenticationType[type]);
            }],
            ['检查是否录入生物特征', LocalAuthentication.isEnrolledAsync],
            ['读取已录入的安全等级', async () => {
              const level = await LocalAuthentication.getEnrolledLevelAsync();
              return { level, name: LocalAuthentication.SecurityLevel[level] };
            }],
          ]}
        />
      </Panel>

      <Panel title="身份认证">
        <Field editable={!busy} label="认证提示" onChangeText={setPrompt} testID="local-authentication-prompt" value={prompt} />
        {android
          ? (
              <>
                <Field editable={!busy} label="认证副标题" onChangeText={setSubtitle} value={subtitle} />
                <Field editable={!busy} label="认证详情" onChangeText={setDescription} value={description} />
              </>
            )
          : null}
        <Field editable={!busy} label="取消按钮文字" onChangeText={setCancelLabel} testID="local-authentication-label" value={cancelLabel} />
        {ios ? <Field editable={!busy} label="锁屏密码按钮文字" onChangeText={setFallbackLabel} value={fallbackLabel} /> : null}
        <DataRow
          label="禁止改用锁屏密码"
          value={<Switch accessibilityLabel="禁止改用锁屏密码" disabled={busy} onValueChange={setDisableFallback} testID="local-authentication-fallback" value={disableFallback} />}
        />
        {android
          ? (
              <DataRow label="认证后需要确认" value={<Switch accessibilityLabel="认证后需要确认" disabled={busy} onValueChange={setRequireConfirmation} value={requireConfirmation} />} />
            )
          : null}
        {cancellable
          ? (
              <>
                <DataRow label="只允许强生物识别" value={<Switch accessibilityLabel="只允许强生物识别" disabled={busy} onValueChange={setStrong} testID="local-authentication-strong" value={strong} />} />
                <Field editable={!busy} keyboardType="decimal-pad" label="自动取消延时（秒，选填）" onChangeText={setCancelDelay} value={cancelDelay} />
              </>
            )
          : null}
        <ActionRow>
          <ActionButton disabled={busy || cancelling} label="开始认证" onPress={() => void authenticate()} testID="local-authentication-authenticate" />
          {cancellable
            ? (
                <ActionButton disabled={cancelling} label="取消认证" onPress={() => void stop()} testID="local-authentication-cancel" tone="secondary" />
              )
            : null}
        </ActionRow>
        <ResultPanel state={auth.state} />
        <ResultPanel state={cancel.state} />
      </Panel>
    </>
  );
}
