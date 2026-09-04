import { requireNativeViewManager } from 'expo-modules-core';
import * as React from 'react';
import { StyleSheet, View } from 'react-native';

const NativeView = requireNativeViewManager('ExpoLinearGradient');

export default function NativeLinearGradient({
  colors,
  locations,
  startPoint,
  endPoint,
  children,
  style,
  dither,
  ...props
}) {
  const flattened = StyleSheet.flatten(style) ?? {};

  const radius = flattened.borderRadius ?? 0;
  const radii = [
    flattened.borderTopLeftRadius ?? radius,
    flattened.borderTopRightRadius ?? radius,
    flattened.borderBottomRightRadius ?? radius,
    flattened.borderBottomLeftRadius ?? radius,
  ];

  return React.createElement(
    View,
    { ...props, style },
    React.createElement(NativeView, {
      style: StyleSheet.absoluteFill,
      colors,
      locations,
      startPoint,
      endPoint,
      borderRadii: radii,
      dither,
    }),
    children,
  );
}
