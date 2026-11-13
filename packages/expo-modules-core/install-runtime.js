/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

/* global __DEV__: readonly */

try {
  const expoModulesCore = global.__turboModuleProxy?.('ExpoModulesCore')
    ?? global.nativeModuleProxy?.ExpoModulesCore;

  if (typeof expoModulesCore?.installModules !== 'function') {
    throw new Error('ExpoModulesCore is not linked into the RNOH runtime.');
  }
  expoModulesCore.installModules();

  if (__DEV__) {
    const logger = globalThis.expo?.modules?.ExpoModulesCoreJSLogger;
    if (logger) {
      for (const [level, suffix] of [
        ['error', 'Error'],
        ['warn', 'Warning'],
        ['debug', 'Debug'],
        ['info', 'Info'],
        ['trace', 'Trace'],
      ]) {
        logger.addListener(`ExpoModulesCoreJSLogger.onNew${suffix}`, ({ message }) => console[level](message));
      }
    }
  }
} catch (error) {
  console.error('Unable to install Expo Modules Core.', error);
}
