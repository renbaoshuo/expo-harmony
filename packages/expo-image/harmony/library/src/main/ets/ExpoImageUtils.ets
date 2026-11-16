/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { parseExpoColor } from '@expo-harmony/expo-modules-core';
import { drawing } from '@kit.ArkGraphics2D';
import { deviceInfo } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { ExpoImageError } from './ExpoImageError';

const WEBP_LOOP_METADATA_API: number = 24;
export const MAX_DECODED_BYTES: number = 256 * 1024 * 1024;

export function colorComponents(value: number | string): number[] {
  try {
    const color: number = parseExpoColor(value);
    return [(color >>> 16) & 255, (color >>> 8) & 255, color & 255, color >>> 24];
  } catch (_) {
    throw new ExpoImageError('ERR_IMAGE_INVALID_COLOR', 'Expected a React Native color.');
  }
}

export async function copyPixelMap(pixel: image.PixelMap, maxSize?: number): Promise<image.PixelMap> {
  const info = pixel.getImageInfoSync().size;
  const width = info.width;
  const height = info.height;
  const scale = maxSize === undefined ? 1 : Math.min(1, maxSize / Math.max(width, height));
  const size: image.Size = {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };

  if (size.width * size.height * 4 > MAX_DECODED_BYTES) {
    throw new ExpoImageError('ERR_IMAGE_TOO_LARGE', 'Decoded image frames exceed the 256 MiB memory limit.');
  }

  // Draw synchronously before a release can invalidate the borrowed SharedRef.
  const copy = image.createPixelMapSync({
    size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    alphaType: image.AlphaType.PREMUL,
    editable: true,
  });

  try {
    const canvas = new drawing.Canvas(copy);
    canvas.drawColor(0, 0, 0, 0, drawing.BlendMode.SRC);
    canvas.drawImageRect(
      pixel,
      { left: 0, top: 0, right: size.width, bottom: size.height },
      new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR),
    );

    return copy;
  } catch (error) {
    await copy.release();

    throw new ExpoImageError('ERR_IMAGE_TRANSFORM', String(error));
  }
}

// TIFF/EXIF orientation values. Image Kit's string labels are documented under
// PropertyKey.ORIENTATION; image.Orientation itself requires API 23.
export enum ExifOrientation {
  Normal = 1,
  MirrorHorizontal = 2,
  Rotate180 = 3,
  MirrorVertical = 4,
  Transpose = 5,
  Rotate90 = 6,
  Transverse = 7,
  Rotate270 = 8,
}

export async function readOrientation(source: image.ImageSource): Promise<ExifOrientation> {
  try {
    const value = await source.getImageProperty(image.PropertyKey.ORIENTATION);
    const labels: Record<string, ExifOrientation> = {
      'Top-left': ExifOrientation.Normal,
      'Top-right': ExifOrientation.MirrorHorizontal,
      'Bottom-right': ExifOrientation.Rotate180,
      'Bottom-left': ExifOrientation.MirrorVertical,
      'Left-top': ExifOrientation.Transpose,
      'Right-top': ExifOrientation.Rotate90,
      'Right-bottom': ExifOrientation.Transverse,
      'Left-bottom': ExifOrientation.Rotate270,
    };
    const number = Number(value);
    return labels[value] ?? (Number.isInteger(number) && number >= 1 && number <= 8 ? number : ExifOrientation.Normal);
  } catch (_) {
    return ExifOrientation.Normal;
  }
}

export async function orientPixelMap(pixel: image.PixelMap, orientation: ExifOrientation): Promise<void> {
  if (orientation === ExifOrientation.MirrorHorizontal || orientation === ExifOrientation.Transpose || orientation === ExifOrientation.Transverse) {
    await pixel.flip(true, false);
  } else if (orientation === ExifOrientation.MirrorVertical) await pixel.flip(false, true);
  if (orientation === ExifOrientation.Rotate180) await pixel.rotate(180);
  else if (orientation === ExifOrientation.Rotate90 || orientation === ExifOrientation.Transverse) await pixel.rotate(90);
  else if (orientation === ExifOrientation.Rotate270 || orientation === ExifOrientation.Transpose) await pixel.rotate(270);
}

export async function animationIterations(source: image.ImageSource, mediaType: string | null): Promise<number> {
  try {
    let count: number | undefined;
    if (mediaType === 'image/gif') {
      const value = await source.getImageProperty(image.PropertyKey.GIF_LOOP_COUNT);
      if (value.trim().length > 0) count = Number(value);
    } else if (mediaType === 'image/webp' && deviceInfo.sdkApiVersion >= WEBP_LOOP_METADATA_API) {
      const metadata = await source.readImageMetadata([image.WebPPropertyKey.LOOP_COUNT]);
      count = metadata.webPMetadata?.loopCount;
    }
    if (count !== undefined && Number.isInteger(count) && count >= 0) return count === 0 ? -1 : count;
  } catch (_) {}
  // GIFs without a looping extension play once. Older Image Kit versions do
  // not expose WebP loop metadata; use the normal repeating animation fallback.
  return mediaType === 'image/gif' ? 1 : -1;
}

export async function tintPixelMap(pixel: image.PixelMap, tint: number[]): Promise<image.PixelMap> {
  const copy = await copyPixelMap(pixel);

  try {
    const canvas = new drawing.Canvas(copy);
    canvas.drawColor(tint[3], tint[0], tint[1], tint[2], drawing.BlendMode.SRC_IN);

    return copy;
  } catch (error) {
    await copy.release();

    throw new ExpoImageError('ERR_IMAGE_TRANSFORM', String(error));
  }
}
