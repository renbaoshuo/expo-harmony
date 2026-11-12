import { requireNativeViewManager } from 'expo-modules-core';
import * as React from 'react';
import { StyleSheet, View } from 'react-native';

const NativeView = requireNativeViewManager('ExpoLinearGradient');

const clip = {
  ...StyleSheet.absoluteFill,
  overflow: 'hidden',
};

export default function NativeLinearGradient({
  colors,
  locations,
  startPoint,
  endPoint,
  children,
  style,
  dither: _dither,
  ...props
}) {
  const flat = StyleSheet.flatten(style) ?? {};

  return React.createElement(
    View,
    { ...props, style },
    // The inner view lets React Native resolve logical and percentage radii.
    React.createElement(
      View,
      {
        pointerEvents: 'none',
        style: [
          clip,
          {
            borderRadius: flat.borderRadius,
            borderTopLeftRadius: flat.borderTopLeftRadius,
            borderTopRightRadius: flat.borderTopRightRadius,
            borderBottomLeftRadius: flat.borderBottomLeftRadius,
            borderBottomRightRadius: flat.borderBottomRightRadius,
            borderTopStartRadius: flat.borderTopStartRadius,
            borderTopEndRadius: flat.borderTopEndRadius,
            borderBottomStartRadius: flat.borderBottomStartRadius,
            borderBottomEndRadius: flat.borderBottomEndRadius,
            borderStartStartRadius: flat.borderStartStartRadius,
            borderStartEndRadius: flat.borderStartEndRadius,
            borderEndStartRadius: flat.borderEndStartRadius,
            borderEndEndRadius: flat.borderEndEndRadius,
          },
        ],
      },
      React.createElement(NativeView, {
        style: StyleSheet.absoluteFill,
        pointerEvents: 'none',
        colors,
        locations,
        startPoint,
        endPoint,
      }),
    ),
    children,
  );
}
