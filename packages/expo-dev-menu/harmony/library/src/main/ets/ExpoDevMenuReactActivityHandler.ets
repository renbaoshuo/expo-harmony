/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ReactActivityHandler, ReactRootViewContext } from '@expo-harmony/expo-modules-core';
import { RNInstance } from '@rnoh/react-native-openharmony';
import { UIContext } from '@kit.ArkUI';
import type { common } from '@kit.AbilityKit';
import { ExpoDevMenuRuntime } from './ExpoDevMenuRuntime';
import { DevMenuPreference } from './DevMenuPreferences';

interface MountedInstanceConfig {
  rnInstance?: RNInstance;
}

function menuForRoot(context: ReactRootViewContext): ExpoDevMenuRuntime | undefined {
  if (!context.ready || !context.core.isDebugModeEnabled) return undefined;
  const instance = (context.instanceConfig as MountedInstanceConfig).rnInstance;
  return instance === undefined ? undefined : ExpoDevMenuRuntime.find(instance.getId());
}

export class ExpoDevMenuReactActivityHandler implements ReactActivityHandler {
  private readonly mountedMenus: Map<Object, ExpoDevMenuRuntime> = new Map<Object, ExpoDevMenuRuntime>();

  constructor(_context: common.Context) {}

  onRootViewMounted(context: ReactRootViewContext, uiContext: UIContext, root: Object): void {
    const menu = menuForRoot(context);
    if (menu === undefined) return;

    this.mountedMenus.set(root, menu);
    menu.mountRoot(root, uiContext);
  }

  onRootViewUnmounted(_context: ReactRootViewContext, root: Object): void {
    const menu = this.mountedMenus.get(root);
    this.mountedMenus.delete(root);
    menu?.unmountRoot(root);
  }

  applyRootViewGestures(context: ReactRootViewContext, event: UIGestureEvent): void {
    if (!context.core.isDebugModeEnabled) return;
    event.addParallelGesture(
      new LongPressGestureHandler({ fingers: 3, duration: 500, repeat: false }).onAction((): void => {
        const menu = menuForRoot(context);
        if (menu?.preferences.get(DevMenuPreference.TouchGesture)) menu.toggleMenu();
      }),
    );
  }

  onRootViewKeyEvent(context: ReactRootViewContext, event: KeyEvent): boolean {
    return menuForRoot(context)?.handleKeyEvent(event) ?? false;
  }
}
