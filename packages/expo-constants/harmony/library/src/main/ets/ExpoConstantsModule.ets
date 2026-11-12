/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleDefinition } from '@expo-harmony/expo-modules-core';
import { webview } from '@kit.ArkWeb';
import { ExpoConstantsKey } from './ExpoConstantsService';

export class ExpoConstantsModule extends ExpoModule {
  private static initialized: boolean = false;

  definition(): ExpoModuleDefinition {
    const constants = this.context.services.get(ExpoConstantsKey)?.constants(this.context) ?? {};

    return new ExpoModuleDefinition()
      .name('ExponentConstants')
      .constants(constants)
      .asyncFunction('getWebViewUserAgentAsync', async (): Promise<string | null> => {
        try {
          if (!ExpoConstantsModule.initialized) {
            webview.WebviewController.initializeWebEngine();
            ExpoConstantsModule.initialized = true;
          }

          return webview.WebviewController.getDefaultUserAgent();
        } catch (error) {
          this.context.logger.warn(`Unable to read the default Harmony WebView user agent: ${String(error)}`);
          return null;
        }
      });
  }
}
