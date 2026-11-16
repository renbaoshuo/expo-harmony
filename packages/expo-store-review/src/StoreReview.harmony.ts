/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireNativeModule } from 'expo-modules-core';
import { isAvailableAsync } from 'expo-store-review';

export { isAvailableAsync, requestReview } from 'expo-store-review';

const native = requireNativeModule<{ readonly storeUrl?: string | null }>('ExpoStoreReview');

export function storeUrl(): string | null {
  return native.storeUrl ?? null;
}

export async function hasAction(): Promise<boolean> {
  return Boolean(storeUrl()) || (await isAvailableAsync());
}
