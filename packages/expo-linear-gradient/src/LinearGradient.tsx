'use client';

import { Component } from 'react';
import type { ColorValue, ProcessedColorValue, ViewProps } from 'react-native';
import { processColor } from 'react-native';

import NativeLinearGradient from './NativeLinearGradient';
import type { NativeLinearGradientPoint } from './NativeLinearGradient.types';

export type LinearGradientPoint
  = | {
    x: number;
    y: number;
  }
  | NativeLinearGradientPoint;

export type LinearGradientProps = ViewProps & {
  colors: readonly [ColorValue, ColorValue, ...ColorValue[]];
  locations?: readonly [number, number, ...number[]] | null;
  start?: LinearGradientPoint | null;
  end?: LinearGradientPoint | null;
  dither?: boolean;
};

let didWarnDither = false;

/** Renders a native view that transitions between multiple colors in a linear direction. */
export class LinearGradient extends Component<LinearGradientProps> {
  render() {
    const { colors, locations, start, end, dither, ...props } = this.props;
    let resolvedLocations: readonly number[] | null | undefined = locations;
    if (locations && colors.length !== locations.length) {
      console.warn('LinearGradient colors and locations props should be arrays of the same length');
      resolvedLocations = locations.slice(0, colors.length);
    }

    warnUnsupportedDither(dither);

    return (
      <NativeLinearGradient
        {...props}
        colors={colors.map(processColor) as ProcessedColorValue[]}
        locations={resolvedLocations}
        startPoint={normalizePoint(start)}
        endPoint={normalizePoint(end)}
      />
    );
  }
}

function warnUnsupportedDither(dither?: boolean): void {
  if (!__DEV__ || dither === undefined || didWarnDither) return;

  console.warn('LinearGradient dither is only supported on Android and is ignored on HarmonyOS.');
  didWarnDither = true;
}

function normalizePoint(
  point?: LinearGradientPoint | null
): NativeLinearGradientPoint | undefined {
  if (!point) return undefined;

  if (Array.isArray(point) && point.length !== 2) {
    console.warn('start and end props for LinearGradient must be of the format [x,y] or {x, y}');
    return undefined;
  }

  return Array.isArray(point) ? point : [point.x, point.y];
}

export type { NativeLinearGradientPoint };
