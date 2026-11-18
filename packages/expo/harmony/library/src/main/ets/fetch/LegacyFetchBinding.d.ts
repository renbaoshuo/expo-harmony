/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

declare module 'libexpo_fetch_legacy.so' {
  export interface LegacyFetchOptions {
    url: string;
    method: string;
    headers: string[][];
    body: ArrayBuffer | null;
    proxyHost: string;
    proxyPort: number;
    proxyUsername: string;
    proxyPassword: string;
  }

  export interface LegacyFetchEvent {
    status?: number;
    statusText?: string;
    headers?: string[][];
    data?: ArrayBuffer;
    error?: string;
  }

  const legacyFetch: {
    start(options: LegacyFetchOptions, callback: (event: LegacyFetchEvent) => void): () => void;
  };

  export default legacyFetch;
}
