/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '../modules/ExpoModuleError';
import { HeadlessAppLoader } from './HeadlessAppLoader';

interface AppLoaderRegistration {
  loader: HeadlessAppLoader;
}

export class AppLoaderProvider {
  static readonly reactNative = 'react-native-headless';
  private static readonly loaders = new Map<string, AppLoaderRegistration>();

  /** Registers a loader until the returned disposer is called. A live registration cannot be replaced by another loader. */
  static registerLoader(name: string, loader: HeadlessAppLoader): () => void {
    const current = AppLoaderProvider.loaders.get(name);
    if (current !== undefined && current.loader !== loader)
      throw new ExpoModuleError('ERR_APP_LOADER_DUPLICATE', `An app loader is already registered for '${name}'.`);

    const registration: AppLoaderRegistration = { loader };
    AppLoaderProvider.loaders.set(name, registration);

    return (): void => {
      if (AppLoaderProvider.loaders.get(name) === registration) AppLoaderProvider.loaders.delete(name);
    };
  }

  static getLoader(name: string): HeadlessAppLoader | undefined {
    return AppLoaderProvider.loaders.get(name)?.loader;
  }
}
