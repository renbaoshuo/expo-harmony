/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { DevMenuHostDelegate } from '@expo-harmony/expo-dev-menu-interface';
import type { common } from '@kit.AbilityKit';
import { DevMenuAppInfoProvider, DevMenuAppMetadata, ExpoDevMenuRuntime } from '@expo-harmony/expo-dev-menu';
import { ExpoModuleError, ReactRuntimeBinding, ReactRuntimeContext } from '@expo-harmony/expo-modules-core';
import { DevLauncherController } from './DevLauncherController';

export class DevLauncherDevMenuDelegate implements DevMenuHostDelegate, DevMenuAppInfoProvider {
  private readonly metadata: DevMenuAppMetadata;
  private readonly controller: DevLauncherController;
  private readonly runtime: ReactRuntimeContext;

  constructor(controller: DevLauncherController, runtime: ReactRuntimeContext) {
    this.controller = controller;
    this.runtime = runtime;
    // Snapshot the selected app for this instance, not a subsequent in-flight selection.
    this.metadata = controller.getDevMenuAppInfo();
  }

  getDevMenuAppInfo(): DevMenuAppMetadata {
    return this.metadata;
  }

  devMenuNavigateHome(): void {
    this.controller
      .showLauncherForRuntime(this.runtime.instance.getId())
      .catch((error: Error): void => {
        this.runtime.core.logger.warn(`Unable to return to Expo Dev Launcher: ${error.message}`);
      });
  }
}

export class ExpoDevLauncherDevMenuBinding implements ReactRuntimeBinding {
  constructor(_context: common.Context) {}

  bind(context: ReactRuntimeContext): (() => void) | void {
    if (!context.core.isDebugModeEnabled || context.isHeadless) return;

    const controller = DevLauncherController.get(context.core.uiAbilityContext.getApplicationContext());
    if (!controller.enabled) return;

    const id = context.instance.getId();
    const delegate = new DevLauncherDevMenuDelegate(controller, context);
    const release = ExpoDevMenuRuntime.registerHostDelegate(id, delegate);
    const unbind = controller.registerRuntime(
      id,
      (): Promise<void> => context.suspend(),
      (reason: string): Promise<void> => context.reload(reason),
    );
    let unregister: () => void;

    try {
      unregister = ExpoDevMenuRuntime.registerAppInfoProvider(id, delegate);
    } catch (error) {
      unbind();
      release();

      throw new ExpoModuleError(
        error instanceof ExpoModuleError ? error.code : 'ERR_DEV_LAUNCHER_DELEGATE',
        error instanceof Error ? error.message : String(error),
        error as Object,
      );
    }

    return (): void => {
      unbind();
      try {
        unregister();
      } finally {
        release();
      }
    };
  }
}
