/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { HarmonyConfigPlugin } from '@expo-harmony/config-plugins';
import type { Props as SplashScreenProps } from 'expo-splash-screen/plugin';

declare const withSplashScreen: HarmonyConfigPlugin<withSplashScreen.SplashScreenPluginConfig | null | void>;

declare namespace withSplashScreen {
  type HarmonySplashResizeMode = 'contain' | 'cover' | 'native';

  interface HarmonySplashScreenConfig {
    backgroundColor?: string;
    imageWidth?: number;
    image?: string;
    resizeMode?: HarmonySplashResizeMode;
    dark?: {
      backgroundColor?: string;
      image?: string;
    };
  }

  type SplashScreenPluginConfig = SplashScreenProps & {
    harmony?: HarmonySplashScreenConfig;
  };
}

export = withSplashScreen;
