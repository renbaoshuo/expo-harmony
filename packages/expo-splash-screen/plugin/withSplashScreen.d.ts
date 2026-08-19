import type { ConfigPlugin } from '@expo/config-plugins';

export type HarmonySplashResizeMode = 'contain' | 'cover' | 'native';

export interface HarmonySplashScreenConfig {
  backgroundColor?: string;
  imageWidth?: number;
  image?: string;
  resizeMode?: HarmonySplashResizeMode;
  dark?: {
    backgroundColor?: string;
    image?: string;
  };
}

export interface SplashScreenPluginConfig extends HarmonySplashScreenConfig {
  harmony?: HarmonySplashScreenConfig;
}

declare const withSplashScreen: ConfigPlugin<SplashScreenPluginConfig | null> & {
  withHarmonySplashScreen: ConfigPlugin<SplashScreenPluginConfig | null>;
};
export = withSplashScreen;
