/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import type { JSBundleProvider, RNInstance } from '@rnoh/react-native-openharmony';
import type { ReactNativeHost, ReactNativeHostHandler, ReactRuntimeAppearance } from '@expo-harmony/expo-modules-core';
import { DevLauncherController } from './DevLauncherController';
import { DevLauncherHostPriority } from './DevLauncherProtocol';

export class ExpoDevLauncherReactNativeHostHandler implements ReactNativeHostHandler {
  readonly priority: number = DevLauncherHostPriority;
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

  getRuntimeAppearance(): ReactRuntimeAppearance | undefined {
    return this.controller.getRuntimeAppearance();
  }

  async getJSBundleProvider(_debug: boolean, headless: boolean = false): Promise<JSBundleProvider | undefined> {
    if (headless || !this.controller.enabled) return undefined;

    this.controller.connectUpdates();
    await this.controller.ready;

    return this.controller.selectedProvider;
  }

  onDidCreateReactInstance(_debug: boolean, instance: RNInstance): void {
    this.controller.reportReactInitialized(instance.getId()).catch((error: Error): void => {
      console.warn(`Unable to save Expo Dev Launcher history: ${error.message}`);
    });
  }

  get onReactInstanceException(): ((_debug: boolean, instance: RNInstance, error: Error) => void) | undefined {
    if (!this.controller.enabled) return undefined;
    return (_debug: boolean, instance: RNInstance, error: Error): void => this.controller.reportReactError(instance.getId(), error);
  }
}
