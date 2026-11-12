/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { DevToolsController } from '@rnoh/react-native-openharmony/src/main/ets/RNOH/DevToolsController';
import type { common } from '@kit.AbilityKit';
import type { JSBundleProvider, RNInstance, RNOHCoreContext } from '@rnoh/react-native-openharmony';

import type { RNInstanceConfig } from '@rnoh/react-native-openharmony/src/main/ets/RNApp';
import type { ReactNativeRuntime } from './ReactNativeRuntime';

export interface ReactNativeHost {
  createRuntime(
    core: RNOHCoreContext,
    config: RNInstanceConfig,
    bundle?: JSBundleProvider,
    replace?: (reason: string) => Promise<RNInstance>,
  ): ReactNativeRuntime;

  createJSBundleProvider(context: common.Context, debug?: boolean): JSBundleProvider;
  hasEmbeddedJSBundle?(context: common.Context): boolean;
  createEmbeddedJSBundleProvider?(context: common.Context): JSBundleProvider;

  load(context: common.Context): Promise<void>;
  unload(): Promise<void>;
}

export interface ReactNativeHostHandler {
  getUseDeveloperSupport?(): boolean | undefined;
  // A handler may select a provider when a development client needs an exact
  // Metro URL (including query parameters) instead of only a file or asset.
  getJSBundleProvider?(debug: boolean): JSBundleProvider | undefined | Promise<JSBundleProvider | undefined>;
  // ArkTS must await bundle selection instead of blocking its UI thread.
  getJSBundleFile?(debug: boolean): string | undefined | Promise<string | undefined>;
  getBundleAssetName?(debug: boolean): string | undefined | Promise<string | undefined>;
  onWillCreateReactInstance?(debug: boolean): void;
  onDidCreateReactHost?(context: common.Context, host: ReactNativeHost): void;
  onDidCreateDevSupportManager?(manager: DevToolsController): void;
  onDidCreateReactInstance?(debug: boolean, instance: RNInstance): void;
  onReactInstanceException?: (debug: boolean, instance: RNInstance, error: Error) => void;
}

export interface ReactNativeHostHandlerRegistration {
  readonly packageName?: string;
  readonly registrationId: string;
  readonly create: (context: common.Context) => ReactNativeHostHandler;
}
