/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import type { ReactActivityHandler, ReactRootViewContext } from '@expo-harmony/expo-modules-core';
import { UpdatesController } from './UpdatesController';
import { UpdatesHostPriority } from './UpdatesProtocol';

export class ExpoUpdatesReactActivityHandler implements ReactActivityHandler {
  readonly priority: number = UpdatesHostPriority;
  private readonly context: common.ApplicationContext;

  constructor(context: common.Context) {
    this.context = context.getApplicationContext();
  }

  getDelayLoadAppHandler(_context: ReactRootViewContext): Promise<void> | undefined {
    const controller = UpdatesController.get(this.context);
    return controller.active ? controller.ready : undefined;
  }
}
