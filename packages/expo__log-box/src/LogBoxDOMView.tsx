/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import React, { useRef } from 'react';
import { requireNativeModule, requireNativeViewManager } from 'expo-modules-core';
import { View, type ViewProps } from 'react-native';
import type LogBoxPolyfillDOM from '@expo/log-box/src/logbox-dom-polyfill';
import { getInjectEventScript, NATIVE_ACTION, NATIVE_ACTION_RESULT } from 'expo/src/dom/injection';

type Props = React.ComponentProps<typeof LogBoxPolyfillDOM>;
type NativeRef = { injectJavaScript(script: string): Promise<void> };
type NativeProps = ViewProps & {
  payload: string;
  onMessage(event: { nativeEvent: { data: string } }): void;
  ref: React.Ref<NativeRef>;
};

const NativeView = requireNativeViewManager<NativeProps>('ExpoLogBox');

export default function LogBoxDOMView({ dom, ...props }: Props) {
  const ref = useRef<NativeRef>(null);
  const native = requireNativeModule<{ enabled: boolean; copyTextAsync(text: string): Promise<void> }>('ExpoLogBox');
  if (!native.enabled) {
    throw new Error('Expo LogBox requires EXPO_UNSTABLE_LOG_BOX=1 for both Harmony prebuild and Metro. Rebuild the application after enabling the plugin.');
  }

  const actions: Record<string, unknown> = {
    ...Object.fromEntries(Object.entries(props).filter(([, value]) => typeof value === 'function')),
    // RNOH does not expose the Clipboard API used by upstream LogBox.
    onCopyText: (text: string) => native.copyTextAsync(text),
  };
  const payload = JSON.stringify({
    names: Object.keys(actions),
    props: Object.fromEntries(Object.entries(props).filter(([, value]) => typeof value !== 'function')),
  });

  const onMessage: NativeProps['onMessage'] = async ({ nativeEvent }) => {
    const { type, data } = JSON.parse(nativeEvent.data);
    if (type !== NATIVE_ACTION || typeof data?.uid !== 'string' || typeof data.actionId !== 'string') return;

    const view = ref.current;
    const { uid, actionId, args } = data;
    let result: unknown;
    let error: { message: string; stack?: string } | undefined;

    try {
      const action = actions[actionId];
      if (!Object.hasOwn(actions, actionId) || typeof action !== 'function' || !Array.isArray(args)) {
        throw new Error(`Invalid LogBox action: ${actionId}`);
      }

      result = await (action as (...args: unknown[]) => unknown)(...args);
    } catch (cause) {
      error = cause instanceof Error ? { message: cause.message, stack: cause.stack } : { message: String(cause) };
    }

    // Dismiss/reload can unmount this view while an action is pending.
    if (view && view === ref.current) {
      await view.injectJavaScript(getInjectEventScript({
        type: NATIVE_ACTION_RESULT, data: { uid, actionId, result, error },
      }));
    }
  };

  return (
    <View style={[{ flex: 1 }, dom?.containerStyle]}>
      <NativeView ref={ref} payload={payload} onMessage={onMessage} style={[{ flex: 1 }, dom?.style]} />
    </View>
  );
}
