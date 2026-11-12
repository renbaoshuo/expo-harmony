/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { type EventSubscription, requireNativeModule } from 'expo-modules-core';
import { type ParsedURL, type URLListener, parse } from 'expo-linking';
import { useEffect, useState } from 'react';

export * from 'expo-linking';

type NativeLinking = {
  getInitialURL(): string | null;
  getLinkingURL(): string | null;
  addListener(event: 'onURLReceived', listener: URLListener): EventSubscription;
  openURL(url: string): Promise<boolean>;
  canOpenURL(url: string): Promise<boolean>;
  openSettings(): Promise<void>;
};

const native = requireNativeModule<NativeLinking>('ExpoLinking');

export function addEventListener(_type: 'url', handler: URLListener): EventSubscription {
  return native.addListener('onURLReceived', handler);
}

export async function getInitialURL(): Promise<string | null> {
  return native.getInitialURL();
}

export async function parseInitialURLAsync(): Promise<ParsedURL> {
  const url = await getInitialURL();
  return url ? parse(url) : { scheme: null, hostname: null, path: null, queryParams: null };
}

/** @deprecated Use useLinkingURL instead. */
export function useURL(): string | null {
  const [url, setURL] = useState<string | null>(null);

  useEffect(() => {
    const subscription = addEventListener('url', event => setURL(event.url));
    setURL(native.getInitialURL());

    return () => subscription.remove();
  }, []);

  return url;
}

export function useLinkingURL(): string | null {
  const [url, setURL] = useState<string | null>(() => native.getLinkingURL());

  useEffect(() => {
    const subscription = addEventListener('url', event => setURL(event.url));
    // A Want can arrive between the initial render and listener registration.
    setURL(native.getLinkingURL());

    return () => subscription.remove();
  }, []);

  return url;
}

export async function openURL(url: string): Promise<true> {
  await native.openURL(url);
  return true;
}

export async function canOpenURL(url: string): Promise<boolean> {
  return native.canOpenURL(url);
}

export async function openSettings(): Promise<void> {
  await native.openSettings();
}
