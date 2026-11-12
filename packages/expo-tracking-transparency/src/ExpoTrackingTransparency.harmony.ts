/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { PermissionResponse } from 'expo';
import { requireNativeModule } from 'expo-modules-core';

type TrackingModule = {
  getAdvertisingId(): string | null;
  getAdvertisingIdAsync(): Promise<string | null>;
  getPermissionsAsync(): Promise<PermissionResponse>;
  requestPermissionsAsync(): Promise<PermissionResponse>;
};

export default requireNativeModule<TrackingModule>('ExpoTrackingTransparency');
