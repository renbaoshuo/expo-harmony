/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFontError } from './ExpoFontError';

export function bundledFontCachePath(directory: string, source: string, hash: string): string {
  const name = source.slice(source.lastIndexOf('/') + 1);
  const dot = name.lastIndexOf('.');
  if (dot <= 0 || dot === name.length - 1 || !/^[A-Fa-f0-9]{64}$/.test(hash)) {
    throw new ExpoFontError('ERR_FONT_BUNDLED_MANIFEST', 'Invalid bundled font cache identity.');
  }

  return `${directory}/${hash.toLowerCase()}${name.slice(dot).toLowerCase()}`;
}
