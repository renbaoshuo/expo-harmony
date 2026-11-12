/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import type { JSBundleProvider, RNInstance } from '@rnoh/react-native-openharmony';
import type { ReactNativeHost, ReactNativeHostHandler } from '@expo-harmony/expo-modules-core';
import { DevLauncherController } from './DevLauncherController';

export class ExpoDevLauncherReactNativeHostHandler implements ReactNativeHostHandler {
  private readonly controller: DevLauncherController;

  constructor(context: common.Context) {
    this.controller = DevLauncherController.get(context.getApplicationContext());
  }

  onWillCreateReactInstance(debug: boolean): void {
    this.controller.activate(debug);
  }

  onDidCreateReactHost(context: common.Context, host: ReactNativeHost): void {
    const provider = host.hasEmbeddedJSBundle?.(context) === false ? undefined : host.createEmbeddedJSBundleProvider?.(context);
    this.controller.setEmbeddedProvider(provider);
  }

  getUseDeveloperSupport(): boolean | undefined {
    return this.controller.useDeveloperSupport;
  }

  async getJSBundleProvider(_debug: boolean): Promise<JSBundleProvider | undefined> {
    if (!this.controller.enabled) return undefined;
    this.controller.connectUpdates();
    await this.controller.ready;
    return this.controller.selectedProvider;
  }

  get onReactInstanceException(): ((_debug: boolean, instance: RNInstance, error: Error) => void) | undefined {
    if (!this.controller.enabled) return undefined;
    return (_debug: boolean, instance: RNInstance, error: Error): void => this.controller.reportReactError(instance.getId(), error);
  }
}
