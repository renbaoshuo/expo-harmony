/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { requireNativeViewManager, requireOptionalNativeModule } from 'expo-modules-core';
import { useMemo } from 'react';
import type { ComponentType, JSX } from 'react';
import { processColor } from 'react-native';
import type { ColorValue } from 'react-native';

import type { NativeSymbolAnimation, NativeSymbolViewProps, SymbolViewProps } from './SymbolModule.types';

const native = requireOptionalNativeModule<{ isSymbolAvailable(name: string): boolean }>('SymbolModule');
const NativeView: ComponentType<NativeSymbolViewProps> | null = native
  ? requireNativeViewManager('SymbolModule')
  : null;

function colorValue(color: ColorValue | null | undefined): number | null {
  if (color == null) return null;

  const value = processColor(color);
  if (typeof value !== 'number') throw new TypeError('expo-symbols requires a valid HarmonyOS color.');

  return value;
}

export function SymbolView({
  name,
  fallback,
  size = 24,
  style,
  type: colorMode,
  weight = 'unspecified',
  tintColor,
  colors,
  scale: _scale,
  resizeMode,
  animationSpec,
  ...props
}: SymbolViewProps): JSX.Element {
  const symbol = typeof name === 'object' && name !== null && typeof name.harmony === 'string'
    ? name.harmony
    : '';
  const available = useMemo(() => symbol !== '' && native?.isSymbolAvailable(symbol) === true, [symbol]);

  if (!NativeView || !available) return <>{fallback}</>;
  if (!Number.isFinite(size) || size < 0) throw new RangeError('expo-symbols size must be a finite, non-negative number.');

  const type = colorMode ?? 'monochrome';
  const tint = colorValue(tintColor);
  const palette = type === 'palette' && tint === null && Array.isArray(colors) && colors.length > 1
    ? colors.slice(0, 3).map(colorValue).filter((color): color is number => color !== null)
    : [];

  const variable = animationSpec?.variableAnimationSpec;
  const animation: NativeSymbolAnimation | null = variable
    ? { type: 'hierarchical', iterative: variable.iterative === true && variable.cumulative !== true }
    : animationSpec?.effect ?? null;

  return (
    <NativeView
      {...props}
      name={symbol}
      size={size}
      style={[{ width: size, height: size }, style]}
      type={type}
      weight={typeof weight === 'string' ? weight : 'unspecified'}
      resizeMode={resizeMode}
      animation={animation}
      tint={tint}
      colors={palette}
    />
  );
}
