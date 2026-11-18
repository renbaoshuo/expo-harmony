/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { RNInstanceConfig } from '@rnoh/react-native-openharmony/src/main/ets/RNApp';
import type { JSBundleProvider, RNInstance, RNOHCoreContext } from '@rnoh/react-native-openharmony';
import type { WrappedCustomRNComponentBuilder } from '@rnoh/react-native-openharmony/src/main/ets/RNOH';
import type { ReactNativeHost } from './ReactNativeHostHandler';

export interface ReactRootViewContext {
  readonly owner: Object;
  readonly core: RNOHCoreContext;
  readonly host: ReactNativeHost;
  readonly instanceConfig: RNInstanceConfig;
  readonly appKey: string;
  readonly initialProps: Record<string, string>;
  readonly jsBundleProvider?: JSBundleProvider;
  readonly wrappedCustomRNComponentBuilder?: WrappedCustomRNComponentBuilder;
  readonly onSetUp: (instance: RNInstance) => Promise<void> | void;
  readonly ready: boolean;
  readonly isCustomRoot?: boolean;

  /** Allows the splash screen to hand off while the bundle is still loading. */
  readonly showsNativeContentBeforeReact?: boolean;
  readonly defaultRoot: WrappedBuilder<[ReactRootViewContext]>;
}

export type ReactRootViewBuilder = WrappedBuilder<[ReactRootViewContext]>;
