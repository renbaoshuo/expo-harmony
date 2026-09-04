import { type EventSubscription, requireNativeModule } from 'expo-modules-core';

import type {
  NavigationBarButtonStyle,
  NavigationBarPosition,
  NavigationBarVisibility,
  NavigationBarVisibilityEvent,
} from './NavigationBar.types';

type NativeNavigationBarModule = {
  addListener(event: 'ExpoNavigationBar.didChange', listener: (event: NavigationBarVisibilityEvent) => void): EventSubscription;
  setBackgroundColorAsync(color: number): Promise<void>;
  getBackgroundColorAsync(): Promise<string>;
  setButtonStyleAsync(style: NavigationBarButtonStyle): Promise<void>;
  getButtonStyleAsync(): Promise<NavigationBarButtonStyle>;
  setVisibilityAsync(visibility: NavigationBarVisibility): Promise<void>;
  getVisibilityAsync(): Promise<NavigationBarVisibility>;
  setPositionAsync(position: NavigationBarPosition): Promise<void>;
  getPositionAsync(): Promise<NavigationBarPosition>;
};

const native = requireNativeModule<NativeNavigationBarModule>('ExpoNavigationBar');

export default {
  addListener(
    event: 'ExpoNavigationBar.didChange',
    listener: (event: NavigationBarVisibilityEvent) => void
  ): EventSubscription {
    return native.addListener(event, listener);
  },
  setBackgroundColorAsync: native.setBackgroundColorAsync.bind(native),
  getBackgroundColorAsync: native.getBackgroundColorAsync.bind(native),
  setButtonStyleAsync: native.setButtonStyleAsync.bind(native),
  getButtonStyleAsync: native.getButtonStyleAsync.bind(native),
  setVisibilityAsync: native.setVisibilityAsync.bind(native),
  getVisibilityAsync: native.getVisibilityAsync.bind(native),
  setPositionAsync: native.setPositionAsync.bind(native),
  getPositionAsync: native.getPositionAsync.bind(native),
};
