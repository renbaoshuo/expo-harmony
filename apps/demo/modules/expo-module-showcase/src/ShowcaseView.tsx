import { requireNativeViewManager } from 'expo-modules-core';
import type { ComponentType } from 'react';

import type { ShowcaseViewProps } from './types';

let NativeView: ComponentType<ShowcaseViewProps> | undefined;

export function ShowcaseView(props: ShowcaseViewProps) {
  NativeView ??= requireNativeViewManager<ShowcaseViewProps>('ExpoModuleShowcase');
  return <NativeView {...props} />;
}
