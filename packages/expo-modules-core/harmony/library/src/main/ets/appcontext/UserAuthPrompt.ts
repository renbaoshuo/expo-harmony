/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

let activePrompt: (() => void) | undefined;

/** Reserves the system authentication prompt on the ArkTS UI actor. */
export function tryAcquireUserAuthPrompt(): (() => void) | undefined {
  if (activePrompt !== undefined) return undefined;

  const release = (): void => {
    if (activePrompt === release) activePrompt = undefined;
  };
  activePrompt = release;
  return release;
}
