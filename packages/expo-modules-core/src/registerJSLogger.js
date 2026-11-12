/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

/* global __DEV__: readonly */

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
