/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import type { ReactActivityHandler, ReactRootViewBuilder, ReactRootViewContext } from '@expo-harmony/expo-modules-core';
import { DevLauncherController } from './DevLauncherController';
import { DevLauncherHostPriority } from './DevLauncherProtocol';
import { buildExpoDevLauncherRoot } from './ExpoDevLauncherView';

export class ExpoDevLauncherReactActivityHandler implements ReactActivityHandler {
  readonly priority: number = DevLauncherHostPriority;
  readonly showsNativeContentBeforeReact: boolean = true;
  private readonly controller: DevLauncherController;

  constructor(context: common.Context) {
    this.controller = DevLauncherController.get(context.getApplicationContext());
  }

  createReactRootViewContainer(_context: ReactRootViewContext): ReactRootViewBuilder | undefined {
    return this.controller.enabled ? wrapBuilder(buildExpoDevLauncherRoot) : undefined;
  }

  getDelayLoadAppHandler(_context: ReactRootViewContext): Promise<void> | undefined {
    if (!this.controller.enabled) return undefined;

    this.controller.startInitialSelection();
    return this.controller.ready;
  }
}
