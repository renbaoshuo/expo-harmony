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

  // Leave room for the digest and extension even when the source name uses multibyte characters.
  const stem = dot <= 60 ? `${name.slice(0, dot)}-` : '';
  return `${directory}/${stem}${hash.toLowerCase()}${name.slice(dot).toLowerCase()}`;
}
