/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

try {
  const expoModulesCore = global.__turboModuleProxy?.('ExpoModulesCore')
    ?? global.nativeModuleProxy?.ExpoModulesCore;

  if (typeof expoModulesCore?.installModules !== 'function') {
    throw new Error('ExpoModulesCore is not linked into the RNOH runtime.');
  }
  expoModulesCore.installModules();
} catch (error) {
  console.error('Unable to install Expo Modules Core.', error);
}
