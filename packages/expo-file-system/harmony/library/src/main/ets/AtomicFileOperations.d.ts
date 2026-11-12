/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

declare module 'libexpo_file_system_atomic.so' {
  const atomic: {
    exclusiveCreate(path: string): void;
    publishNoReplace(source: string, target: string): void;
    isSameFile(first: number, second: number): boolean;
  };

  export default atomic;
}
