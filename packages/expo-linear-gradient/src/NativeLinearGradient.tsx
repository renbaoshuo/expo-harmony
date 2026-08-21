import { requireNativeViewManager } from 'expo-modules-core';
import type { ReactElement } from 'react';
import { StyleSheet, View } from 'react-native';

import type { NativeLinearGradientProps } from './NativeLinearGradient.types';

export default function NativeLinearGradient({
  colors,
  locations,
  startPoint,
  endPoint,
  children,
  style,
  ...props
}: NativeLinearGradientProps): ReactElement {
  const flatStyle = StyleSheet.flatten(style) ?? {};
  const borderRadius = normalizeRadius(flatStyle.borderRadius);

  const borderRadii = [
    normalizeRadius(flatStyle.borderTopLeftRadius, borderRadius),
    normalizeRadius(flatStyle.borderTopRightRadius, borderRadius),
    normalizeRadius(flatStyle.borderBottomRightRadius, borderRadius),
    normalizeRadius(flatStyle.borderBottomLeftRadius, borderRadius),
  ];

  return (
    <View {...props} style={style}>
      <BaseNativeLinearGradient
        style={StyleSheet.absoluteFill}
        colors={colors}
        locations={locations}
        startPoint={startPoint}
        endPoint={endPoint}
        borderRadii={borderRadii}
      />
      {children}
    </View>
  );
}

type BaseNativeLinearGradientProps = Omit<NativeLinearGradientProps, 'children'> & {
  borderRadii: readonly (number | string)[];
};

const BaseNativeLinearGradient
  = requireNativeViewManager<BaseNativeLinearGradientProps>('ExpoLinearGradient');

function normalizeRadius(value: unknown, fallback: number | string = 0): number | string {
  return typeof value === 'number' || typeof value === 'string' ? value : fallback;
}
