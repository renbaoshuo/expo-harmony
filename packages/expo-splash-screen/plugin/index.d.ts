/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { SplashScreenPluginConfig } from './withSplashScreen';

declare function splashScreen(
  props?: SplashScreenPluginConfig
): ['@expo-harmony/expo-splash-screen', SplashScreenPluginConfig];

declare namespace splashScreen {
  type Props = SplashScreenPluginConfig;
}

export = splashScreen;
