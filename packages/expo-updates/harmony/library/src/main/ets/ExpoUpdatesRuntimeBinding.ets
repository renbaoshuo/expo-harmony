/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import {
  EXPO_CONTENT_APPEARED,
  ExpoFileAccessRegistry,
  ExpoFileAccessMode,
  ExpoFileAccessPolicy,
  ReactRuntimeBinding,
  ReactRuntimeContext,
} from '@expo-harmony/expo-modules-core';
import { assetAccess } from './UpdatesAssetAccess';
import { prepareClientIdentity } from './UpdatesClientIdentity';
import { UpdatesController } from './UpdatesController';
import { ExpoUpdatesError } from './UpdatesProtocol';

export class ExpoUpdatesRuntimeBinding implements ReactRuntimeBinding {
  private readonly context: common.ApplicationContext;

  constructor(context: common.Context) {
    this.context = context.getApplicationContext();
  }

  async bind(context: ReactRuntimeContext): Promise<(() => void) | void> {
    await UpdatesController.get(this.context).ready;
    await prepareClientIdentity(this.context, true).catch((error: Error): void => {
      console.warn(`Unable to prepare the legacy EAS client ID: ${String(error)}`);
    });

    const controller = UpdatesController.get(this.context);
    if (!controller.active) return;

    const instance = context.instance;
    const id = instance.getId();
    const subscriptions: (() => void)[] = [];
    let active = true;

    const cleanup = (): void => {
      if (!active) return;
      active = false;
      for (const dispose of subscriptions.splice(0).reverse()) {
        try {
          dispose();
        } catch (error) {
          console.error(`Unable to detach an Updates runtime subscription: ${String(error)}`);
        }
      }
    };

    try {
      subscriptions.push(controller.attach(id, context.reload, context.owner));
      subscriptions.push(
        ExpoFileAccessRegistry.register(id, (path: string, mode: ExpoFileAccessMode, policy?: ExpoFileAccessPolicy): boolean | undefined => {
          if (policy === undefined) return undefined;
          return assetAccess(path, mode, (candidate: string): boolean => controller.hasAsset(id, candidate));
        }),
      );
      subscriptions.push(instance.cppEventEmitter.subscribe(EXPO_CONTENT_APPEARED, (): void => controller.contentAppeared(id)));

      return cleanup;
    } catch (error) {
      cleanup();
      throw new ExpoUpdatesError('ERR_UPDATES_RUNTIME', 'Unable to attach the React runtime.', error as Error);
    }
  }
}
