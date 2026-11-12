/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { type EventSubscription, requireNativeModule } from 'expo-modules-core';

import type {
  NavigationBarVisibility,
  NavigationBarVisibilityEvent,
} from './NavigationBar.types';

type NativeNavigationBarModule = {
  addListener(event: 'ExpoNavigationBar.didChange', listener: (event: NavigationBarVisibilityEvent) => void): EventSubscription;
  setStyle(style: 'light' | 'dark'): Promise<void>;
  setHidden(hidden: boolean): Promise<void>;
  getVisibilityAsync(): Promise<NavigationBarVisibility>;
};

const native = requireNativeModule<NativeNavigationBarModule>('ExpoNavigationBar');

export default {
  addListener(
    event: 'ExpoNavigationBar.didChange',
    listener: (event: NavigationBarVisibilityEvent) => void
  ): EventSubscription {
    return native.addListener(event, listener);
  },
  setStyle: native.setStyle.bind(native),
  setHidden: native.setHidden.bind(native),
  getVisibilityAsync: native.getVisibilityAsync.bind(native),
};
