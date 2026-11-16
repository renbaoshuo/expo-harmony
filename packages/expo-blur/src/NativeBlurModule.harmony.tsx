/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use client';

import type { BlurViewProps } from 'expo-blur';
import { requireNativeViewManager } from 'expo-modules-core';
import type { Component, RefAttributes } from 'react';
import type { ViewProps } from 'react-native';

type BlurProps = Pick<BlurViewProps, 'intensity' | 'tint'> & Pick<ViewProps, 'style'>;
type NativeBlurProps = BlurProps & RefAttributes<Component<BlurProps>>;

const ExpoBlurView = requireNativeViewManager<NativeBlurProps & Pick<ViewProps, 'pointerEvents'>>('ExpoBlur', 'ExpoBlurView');

export function NativeBlurView({ intensity, ref, style, tint }: NativeBlurProps) {
  return <ExpoBlurView intensity={intensity} pointerEvents="none" ref={ref} style={style} tint={tint} />;
}
