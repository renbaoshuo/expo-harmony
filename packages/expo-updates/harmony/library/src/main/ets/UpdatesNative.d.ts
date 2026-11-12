/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

declare module 'libexpo_updates.so' {
  export function applyPatch(base: string, output: string, patch: string): Promise<number>;
  export function linkAsset(source: string, destination: string): boolean;
  export function crash(message: string): never;
}
