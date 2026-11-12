/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ColorMetrics } from '@kit.ArkUI';

/** Returns an unsigned AARRGGBB color from a bridge value. */
export function parseExpoColor(value: ESObject): number {
  if (typeof value === 'number' && Number.isInteger(value) && value >= -0x80000000 && value <= 0xffffffff) {
    return value >>> 0;
  }

  if (typeof value === 'string') {
    const text: string = value.trim().toLowerCase();
    if (/^#[0-9a-f]{3,4}$/.test(text)) {
      const hex: string = text.slice(1).split('').map((digit: string): string => digit + digit).join('');
      return rgbaHexToArgb(hex);
    }
    if (/^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/.test(text)) return rgbaHexToArgb(text.slice(1));

    const color: ColorMetrics = ColorMetrics.resourceColor(text);
    return ((color.alpha << 24) | (color.red << 16) | (color.green << 8) | color.blue) >>> 0;
  }

  if (Array.isArray(value) && value.length >= 3) {
    const red: number = colorComponent(value[0]);
    const green: number = colorComponent(value[1]);
    const blue: number = colorComponent(value[2]);
    const alpha: number = value.length > 3 ? colorComponent(value[3]) : 255;
    return ((alpha << 24) | (red << 16) | (green << 8) | blue) >>> 0;
  }

  throw new Error('Expected an ARGB integer, color string, or RGB(A) components.');
}

function rgbaHexToArgb(hex: string): number {
  const rgb: number = parseInt(hex.slice(0, 6), 16);
  const alpha: number = hex.length === 8 ? parseInt(hex.slice(6), 16) : 255;
  return ((alpha << 24) | rgb) >>> 0;
}

function colorComponent(value: ESObject): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error('Color components must be finite numbers.');
  }
  return Math.round(Math.min(1, Math.max(0, value)) * 255);
}
