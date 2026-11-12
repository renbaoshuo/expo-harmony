/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { UnavailabilityError, requireNativeModule } from 'expo-modules-core';
import { useEffect } from 'react';

export * from 'expo-screen-capture';

type NativeScreenCapture = {
  preventScreenCapture?: () => Promise<void>;
  allowScreenCapture?: () => Promise<void>;
};

const native = requireNativeModule<NativeScreenCapture>('ExpoScreenCapture');
const DEFAULT_KEY = 'default';
const activeTags = new Map<string, Promise<void>>();

export async function preventScreenCaptureAsync(key: string = DEFAULT_KEY): Promise<void> {
  if (!native.preventScreenCapture) {
    throw new UnavailabilityError('ScreenCapture', 'preventScreenCaptureAsync');
  }

  const active = activeTags.get(key);
  if (active) return active;

  const request: Promise<void> = native.preventScreenCapture().catch(async (error) => {
    // The same key may now belong to another request. Releasing the last remaining key also clears
    // any previously protected window whose owner released it while this request was pending.
    if (activeTags.get(key) === request) {
      await allowScreenCaptureAsync(key).catch(logAllowError);
    }
    throw error;
  });
  activeTags.set(key, request);

  return request;
}

export async function allowScreenCaptureAsync(key: string = DEFAULT_KEY): Promise<void> {
  if (!native.preventScreenCapture || !native.allowScreenCapture) {
    throw new UnavailabilityError('ScreenCapture', 'allowScreenCaptureAsync');
  }

  activeTags.delete(key);
  if (activeTags.size === 0) await native.allowScreenCapture();
}

export function usePreventScreenCapture(key: string = DEFAULT_KEY): void {
  useEffect(() => {
    preventScreenCaptureAsync(key).catch((error) => {
      console.error(`Failed to prevent screen capture: ${error}`);
    });

    return () => {
      allowScreenCaptureAsync(key).catch(logAllowError);
    };
  }, [key]);
}

function logAllowError(error: unknown): void {
  console.error(`Failed to allow screen capture: ${error}`);
}
