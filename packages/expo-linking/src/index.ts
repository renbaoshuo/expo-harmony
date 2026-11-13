/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { addEventListener, getLinkingURL } from 'expo-linking';
import { useEffect, useState } from 'react';

import native from './RNLinking';

export * from 'expo-linking';

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
  const [url, setURL] = useState(getLinkingURL);

  useEffect(() => {
    const subscription = addEventListener('url', event => setURL(event.url));
    // A Want can arrive between the initial render and listener registration.
    setURL(getLinkingURL());

    return () => subscription.remove();
  }, []);

  return url;
}
