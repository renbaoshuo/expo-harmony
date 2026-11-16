/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { createPermissionHook, type PermissionResponse } from 'expo';
import { requireNativeModule } from 'expo-modules-core';
import { isAvailable as isUpstreamAvailable } from 'expo-tracking-transparency';

const native = requireNativeModule<{
  isAvailable?(): boolean;
  getAdvertisingIdAsync(): Promise<string | null>;
  getPermissionsAsync(): Promise<PermissionResponse>;
  requestPermissionsAsync(): Promise<PermissionResponse>;
}>('ExpoTrackingTransparency');

export function isAvailable(): boolean {
  return native.isAvailable?.() ?? isUpstreamAvailable();
}

export async function getTrackingPermissionsAsync(): Promise<PermissionResponse> {
  return native.getPermissionsAsync();
}

export async function requestTrackingPermissionsAsync(): Promise<PermissionResponse> {
  return native.requestPermissionsAsync();
}

export const useTrackingPermissions = createPermissionHook({
  getMethod: getTrackingPermissionsAsync,
  requestMethod: requestTrackingPermissionsAsync,
});

export async function getAdvertisingIdAsync(): Promise<string | null> {
  return native.getAdvertisingIdAsync();
}

export { getAdvertisingId, PermissionStatus } from 'expo-tracking-transparency';
export type { PermissionResponse, PermissionExpiration, PermissionHookOptions } from 'expo-tracking-transparency';
