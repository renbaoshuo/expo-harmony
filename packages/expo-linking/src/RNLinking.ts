/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { type EventSubscription, requireNativeModule } from 'expo-modules-core';
import type { URLListener } from 'expo-linking';

const native = requireNativeModule<{
  getInitialURL(): string | null;
  addListener(event: 'onURLReceived', listener: URLListener): EventSubscription;
  openURL(url: string): Promise<true>;
  canOpenURL(url: string): Promise<boolean>;
  openSettings(): Promise<void>;
}>('ExpoLinking');

// ExpoLinking validates URLs natively and returns Harmony's coded errors.
export function validateURL() {}

export default {
  addEventListener(_type: 'url', listener: URLListener) {
    return native.addListener('onURLReceived', listener);
  },
  getInitialURL: native.getInitialURL.bind(native),
  openURL: native.openURL.bind(native),
  canOpenURL: native.canOpenURL.bind(native),
  openSettings: native.openSettings.bind(native),
};
