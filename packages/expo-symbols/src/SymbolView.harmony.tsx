/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireNativeModule, requireNativeViewManager } from 'expo-modules-core';
import { useMemo } from 'react';
import type { ComponentType, JSX } from 'react';
import { processColor } from 'react-native';
import type { ColorValue } from 'react-native';

import type { NativeSymbolViewProps, SymbolViewProps } from './SymbolModule.types';

const native = requireNativeModule<{ isSymbolAvailable(name: string): boolean }>('SymbolModule');
const NativeView: ComponentType<NativeSymbolViewProps> = requireNativeViewManager('SymbolModule');

function colorValue(color: ColorValue | undefined): number | null {
  if (color === undefined) return null;

  const value = processColor(color);
  if (typeof value !== 'number') throw new TypeError('expo-symbols requires a valid HarmonyOS color.');

  return value;
}

export function SymbolView({
  name,
  fallback,
  size = 24,
  style,
  type = 'monochrome',
  weight = 'unspecified',
  tintColor,
  colors,
  scale: _scale,
  resizeMode: _resizeMode,
  animationSpec: _animationSpec,
  ...props
}: SymbolViewProps): JSX.Element {
  const symbol = typeof name === 'object' && name !== null && typeof name.harmony === 'string'
    ? name.harmony
    : '';
  const available = useMemo(() => symbol !== '' && native.isSymbolAvailable(symbol), [symbol]);

  if (!available) return <>{fallback}</>;

  if (!Number.isFinite(size) || size < 0) throw new RangeError('expo-symbols size must be a finite, non-negative number.');

  const tint = colorValue(tintColor);
  const palette = type === 'palette' && tint === null && Array.isArray(colors) && colors.length > 1
    ? colors.slice(0, 3).map(colorValue).filter((color): color is number => color !== null)
    : [];

  return (
    <NativeView
      {...props}
      name={symbol}
      size={size}
      style={[{ width: size, height: size }, style]}
      type={type}
      weight={typeof weight === 'string' ? weight : 'unspecified'}
      tint={tint}
      colors={palette}
    />
  );
}
