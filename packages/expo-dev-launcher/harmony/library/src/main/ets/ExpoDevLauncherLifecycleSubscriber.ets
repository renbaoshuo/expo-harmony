/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { Want, common } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { ExpoAbilityLifecycleSubscriber } from '@expo-harmony/expo-modules-core';
import { DevLauncherController } from './DevLauncherController';
import { isLauncherLink } from './DevLauncherProtocol';

export class ExpoDevLauncherLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  private readonly controller: DevLauncherController;
  private readonly debug: boolean;

  constructor(context: common.UIAbilityContext) {
    super(context);
    this.debug = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).appInfo.debug;
    this.controller = DevLauncherController.get(context.getApplicationContext());
    if (this.debug) this.controller.attachAbility(context);
  }

  override onWillReceiveWant(want: Want): void {
    this.receive(want);
  }

  override onForeground(): void {
    this.controller.foreground(this.context);
  }

  override onDidForeground(): void {
    this.controller.foreground(this.context);
  }

  override onBackground(): void {
    this.controller.background(this.context);
  }

  override onDidBackground(): void {
    this.controller.background(this.context);
  }

  override onDestroy(): void {
    this.controller.detachAbility(this.context);
  }

  private receive(want: Want): void {
    if (!this.debug) return;

    const value = want.uri;
    if (value === undefined || !isLauncherLink(value)) return;

    // Clear the URI before RNOH caches it; preserve the original Want parameters.
    want.uri = undefined;
    this.controller.receiveLink(value);
  }
}
