/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ReactActivityHandler, ReactRootViewBuilder, ReactRootViewContext } from '@expo-harmony/expo-modules-core';

export interface ExpoReactRootViewSelection {
  readonly builder: ReactRootViewBuilder;
  readonly showsNativeContentBeforeReact: boolean;
}

export class ExpoReactRootViewFactory {
  static create(handlers: ReactActivityHandler[], context: ReactRootViewContext): ReactRootViewBuilder | undefined {
    return ExpoReactRootViewFactory.select(handlers, context)?.builder;
  }

  static select(handlers: ReactActivityHandler[], context: ReactRootViewContext): ExpoReactRootViewSelection | undefined {
    for (const handler of handlers) {
      const builder = handler.createReactRootViewContainer?.(context);
      if (builder !== undefined) {
        return { builder, showsNativeContentBeforeReact: handler.showsNativeContentBeforeReact === true };
      }
    }

    return undefined;
  }

  static getDelayLoadAppHandler(handlers: ReactActivityHandler[], context: ReactRootViewContext): Promise<void> | undefined {
    for (const handler of handlers) {
      const delay = handler.getDelayLoadAppHandler?.(context);
      if (delay !== undefined) return delay;
    }
    return undefined;
  }
}
