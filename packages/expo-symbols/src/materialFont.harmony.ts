/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireOptionalNativeModule } from 'expo-modules-core';
import type * as Font from 'expo-font';

// The system SymbolView can register without importing the optional Expo Font package.
export const renderToImageAsync: typeof Font.renderToImageAsync | undefined
  = requireOptionalNativeModule('ExpoFontLoader') && requireOptionalNativeModule('ExpoFontUtils')
    ? async (...args) => (await import('expo-font')).renderToImageAsync(...args)
    : undefined;

export const loadAsync: typeof Font.loadAsync = async (...args) => (await import('expo-font')).loadAsync(...args);
