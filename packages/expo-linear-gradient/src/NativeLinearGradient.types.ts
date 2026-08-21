import type { PropsWithChildren } from 'react';
import type { ProcessedColorValue, ViewProps } from 'react-native';

export type NativeLinearGradientProps = ViewProps
  & PropsWithChildren<{
    colors: readonly ProcessedColorValue[];
    locations?: readonly number[] | null;
    startPoint?: NativeLinearGradientPoint | null;
    endPoint?: NativeLinearGradientPoint | null;
  }>;

export type NativeLinearGradientPoint = [x: number, y: number];
