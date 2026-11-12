/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import type { RNOHCoreContext } from '@rnoh/react-native-openharmony';

import type { ReactNativeRuntime } from '../interfaces/ReactNativeRuntime';

export interface HeadlessAppLoaderParams {
  appScopeKey: string;
  appUrl?: string;
}

export interface HeadlessAppLoader {
  isAvailable(): boolean;
  /** Joins a loading scope. Invalidate a failed or closing scope before starting it again. */
  loadApp(context: common.Context, params: HeadlessAppLoaderParams, alreadyRunning?: () => void, callback?: (success: boolean) => void): void;
  invalidateApp(appScopeKey: string): boolean;
  isRunning(appScopeKey: string): boolean;
  waitForApp(appScopeKey: string): Promise<void>;
  invalidateAppAsync(appScopeKey: string): Promise<void>;
}

export interface HeadlessAppLoaderDelegate {
  readonly workerScriptUrl: string;
  isAvailable(): boolean;
  hasOtherOwner(context: common.UIAbilityContext): boolean;
  getRuntime(): ReactNativeRuntime | undefined;
  createRuntime(core: RNOHCoreContext, context: common.Context): ReactNativeRuntime;
  begin(context: common.UIAbilityContext): void;
  end(context: common.UIAbilityContext): void;
}
