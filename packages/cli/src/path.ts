/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import path from 'node:path';

function isInside(root: string, target: string): boolean {
  const relative = path.relative(root, target);

  return relative === ''
    || (relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative));
}

function toPosixPath(value: string): string {
  return value.split(path.sep).join('/');
}

function assertSafeRelative(relative: string, label: string): string {
  if (typeof relative !== 'string' || !relative || relative.includes('\\') || relative.includes('\0')
    || path.win32.parse(relative).root) {
    throw new Error(`${label} contains an unsafe path.`);
  }

  const segments = relative.split('/');

  if (segments.some(segment => !segment || segment === '.' || segment === '..')) {
    throw new Error(`${label} contains an unsafe path.`);
  }

  return segments.join(path.sep);
}

export { assertSafeRelative, isInside, toPosixPath };
