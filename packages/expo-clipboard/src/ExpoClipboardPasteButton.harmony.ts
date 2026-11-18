/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ClipboardPasteButtonProps, PasteEventPayload } from 'expo-clipboard';
import { requireNativeModule, requireNativeViewManager } from 'expo-modules-core';
import { createElement } from 'react';
import { processColor, type NativeSyntheticEvent } from 'react-native';

type NativePasteButtonProps = Omit<ClipboardPasteButtonProps, 'onPress'> & {
  onPastePressed: (event: NativeSyntheticEvent<PasteEventPayload>) => void;
};

const clipboard = requireNativeModule<{ isPasteButtonAvailable?: boolean }>('ExpoClipboard');

export const isPasteButtonAvailable = clipboard.isPasteButtonAvailable === true;

const NativePasteButton = isPasteButtonAvailable
  ? requireNativeViewManager<NativePasteButtonProps>('ExpoClipboard')
  : undefined;

function toArkUIColor(color: string | null | undefined): string | null {
  const argb = processColor(color ?? undefined);

  // React Native accepts CSS RGBA strings, while ArkUI uses ARGB for eight-digit hex.
  return typeof argb === 'number' ? `#${(argb >>> 0).toString(16).padStart(8, '0')}` : null;
}

export default NativePasteButton && function HarmonyPasteButton({
  backgroundColor,
  foregroundColor,
  ...props
}: NativePasteButtonProps) {
  return createElement(NativePasteButton, {
    ...props,
    backgroundColor: toArkUIColor(backgroundColor),
    foregroundColor: toArkUIColor(foregroundColor),
  });
};
