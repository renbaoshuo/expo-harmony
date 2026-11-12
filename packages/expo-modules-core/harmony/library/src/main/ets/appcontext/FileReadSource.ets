/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fileUri from '@ohos.file.fileuri';
import { filePathFromUri } from './FileUri';

/** Converts an app-owned URI to a path and preserves the authority of provider URIs. */
export function resolveFileReadSource(value: string, cacheDir: string): string {
  if (value.includes('\0')) throw new Error('File paths must not contain a NUL character.');
  if (value.startsWith('/')) return value;

  const match = /^file:\/\/([^/?#]*)(\/.*)$/i.exec(value);
  if (match === null) throw new Error('Expected a local file path or URI.');

  const authority = match[1];
  if (authority === '' || authority.toLowerCase() === 'localhost') return filePathFromUri(value);
  if (authority === new fileUri.FileUri(cacheDir).authority) return filePathFromUri(`file://${match[2]}`);

  return `file://${authority}${match[2]}`;
}
