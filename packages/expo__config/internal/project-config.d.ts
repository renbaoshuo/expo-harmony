/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { getConfig } from '@expo/config';
import type { EnvMode } from '@expo/env';

export type { EnvMode };

export declare function stripPrivateHarmonyConfig<T extends object>(config: T): T;

export declare function getHarmonyProjectConfig(
  root: string,
  options?: Parameters<typeof getConfig>[1],
  mode?: EnvMode
): ReturnType<typeof getConfig>;
