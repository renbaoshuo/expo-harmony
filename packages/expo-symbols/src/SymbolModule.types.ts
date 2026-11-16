/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { SymbolViewProps as UpstreamSymbolViewProps } from 'expo-symbols';
import type { ViewProps } from 'react-native';

export type * from 'expo-symbols';

export type HarmonySymbolName = Exclude<UpstreamSymbolViewProps['name'], string> & {
  harmony?: string;
};

export type SymbolViewProps = Omit<UpstreamSymbolViewProps, 'name'> & {
  name: Extract<UpstreamSymbolViewProps['name'], string> | HarmonySymbolName;
};

export type NativeSymbolAnimation = {
  type: 'bounce' | 'pulse' | 'scale' | 'hierarchical';
  wholeSymbol?: boolean;
  direction?: 'up' | 'down';
  iterative?: boolean;
};

export type NativeSymbolViewProps = ViewProps & {
  name: string;
  size: number;
  type: NonNullable<UpstreamSymbolViewProps['type']>;
  weight: NonNullable<Exclude<UpstreamSymbolViewProps['weight'], object>>;
  resizeMode?: UpstreamSymbolViewProps['resizeMode'];
  animation: NativeSymbolAnimation | null;
  tint: number | null;
  colors: number[];
};
