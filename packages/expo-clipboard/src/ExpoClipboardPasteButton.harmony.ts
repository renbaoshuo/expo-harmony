/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireNativeModule, requireNativeViewManager } from 'expo-modules-core';

const clipboard = requireNativeModule<{ isPasteButtonAvailable?: boolean }>('ExpoClipboard');

export const isPasteButtonAvailable = clipboard.isPasteButtonAvailable === true;

export default isPasteButtonAvailable ? requireNativeViewManager('ExpoClipboard') : undefined;
