/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export function redirectSystemPath({ path }: { path: string }): string {
  return path === 'expoharmonydemo://expo-sharing' ? '/module/sharing' : path;
}
