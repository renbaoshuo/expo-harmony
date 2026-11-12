/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type upstreamSecureStore from 'expo-secure-store/plugin';

declare function secureStore(props?: secureStore.SecureStorePluginOptions): [
  string,
  secureStore.SecureStorePluginOptions,
];

declare namespace secureStore {
  export type SecureStorePluginOptions = NonNullable<Parameters<typeof upstreamSecureStore>[0]>;
  export { secureStore as default };
}

export = secureStore;
