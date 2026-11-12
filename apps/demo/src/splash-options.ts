/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { File, Paths } from 'expo-file-system';
import type { SplashScreenOptions } from 'expo-splash-screen';
import { Platform } from 'react-native';

function optionsFile() {
  return new File(Paths.cache, 'demo-splash-options.json');
}

export function readSplashOptions(): SplashScreenOptions | undefined {
  if (Platform.OS === 'web') return undefined;

  try {
    const file = optionsFile();
    return file.exists ? JSON.parse(file.textSync()) : undefined;
  } catch (error) {
    console.warn('读取启动屏设置失败', error);
    return undefined;
  }
}

export function saveSplashOptions(options: SplashScreenOptions) {
  const file = optionsFile();
  if (!file.exists) file.create();
  file.write(JSON.stringify(options));
}
