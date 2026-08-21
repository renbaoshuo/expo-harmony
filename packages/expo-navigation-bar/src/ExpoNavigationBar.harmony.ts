import { type EventSubscription, requireNativeModule } from 'expo-modules-core';
import { DeviceEventEmitter } from 'react-native';

import type {
  NavigationBarButtonStyle,
  NavigationBarPosition,
  NavigationBarVisibility,
  NavigationBarVisibilityEvent,
} from './NavigationBar.types';

type NativeNavigationBarModule = {
  setBackgroundColorAsync(color: number): Promise<void>;
  getBackgroundColorAsync(): Promise<string>;
  setButtonStyleAsync(style: NavigationBarButtonStyle): Promise<void>;
  getButtonStyleAsync(): Promise<NavigationBarButtonStyle>;
  setVisibilityAsync(visibility: NavigationBarVisibility): Promise<void>;
  getVisibilityAsync(): Promise<NavigationBarVisibility>;
  setPositionAsync(position: NavigationBarPosition): Promise<void>;
  getPositionAsync(): Promise<NavigationBarPosition>;
};

const nativeModule = requireNativeModule<NativeNavigationBarModule>('ExpoNavigationBar');

export default {
  addListener(
    event: 'ExpoNavigationBar.didChange',
    listener: (event: NavigationBarVisibilityEvent) => void
  ): EventSubscription {
    return DeviceEventEmitter.addListener(event, listener);
  },
  setBackgroundColorAsync: nativeModule.setBackgroundColorAsync.bind(nativeModule),
  getBackgroundColorAsync: nativeModule.getBackgroundColorAsync.bind(nativeModule),
  setButtonStyleAsync: nativeModule.setButtonStyleAsync.bind(nativeModule),
  getButtonStyleAsync: nativeModule.getButtonStyleAsync.bind(nativeModule),
  setVisibilityAsync: nativeModule.setVisibilityAsync.bind(nativeModule),
  getVisibilityAsync: nativeModule.getVisibilityAsync.bind(nativeModule),
  setPositionAsync: nativeModule.setPositionAsync.bind(nativeModule),
  getPositionAsync: nativeModule.getPositionAsync.bind(nativeModule),
};
