/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://i.baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { resourceManager } from '@kit.LocalizationKit';
import fs from '@ohos.file.fs';

export class ExpoRawResourceFile {
  readonly file: fs.File;
  readonly offset: number;
  readonly length: number;

  constructor(file: fs.File, offset: number, length: number) {
    this.file = file;
    this.offset = offset;
    this.length = length;
  }
}

/** Returns an owned descriptor. Read at absolute offsets because dup shares the cursor. */
export function openRawResourceFile(resources: resourceManager.ResourceManager, name: string): ExpoRawResourceFile {
  // ResourceManager caches one borrowed descriptor per name. Duplicate and release it without yielding.
  const raw = resources.getRawFdSync(name);
  let file: fs.File | undefined;

  try {
    if (!Number.isSafeInteger(raw.fd) || raw.fd < 0
      || !Number.isSafeInteger(raw.offset) || raw.offset < 0
      || !Number.isSafeInteger(raw.length) || raw.length < 0
      || !Number.isSafeInteger(raw.offset + raw.length)) {
      throw new Error('The packaged resource has an invalid file descriptor.');
    }

    file = fs.dup(raw.fd);
  } finally {
    try {
      resources.closeRawFdSync(name);
    } catch (error) {
      if (file !== undefined) {
        try { fs.closeSync(file.fd); } catch (_) {}
      }
      throw error as Error;
    }
  }

  return new ExpoRawResourceFile(file, raw.offset, raw.length);
}
