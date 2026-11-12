/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { parseExpoColor } from '@expo-harmony/expo-modules-core';
import { drawing } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import deviceInfo from '@ohos.deviceInfo';
import { ExpoImageError } from './ExpoImageError';

export function colorComponents(value: number | string): number[] {
  try {
    const color: number = parseExpoColor(value);
    return [(color >>> 16) & 255, (color >>> 8) & 255, color & 255, color >>> 24];
  } catch (_) {
    throw new ExpoImageError('ERR_IMAGE_INVALID_COLOR', 'Expected a React Native color.');
  }
}

export async function copyPixelMap(pixel: image.PixelMap, maxSize?: number): Promise<image.PixelMap> {
  const info = pixel.getImageInfoSync();
  // Draw into an owned RGBA map synchronously before an external SharedRef can
  // release the source. Drawing performs native format/alpha conversion.
  const copy = image.createPixelMapSync(new ArrayBuffer(info.size.width * info.size.height * 4), {
    size: info.size,
    srcPixelFormat: image.PixelMapFormat.RGBA_8888,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    alphaType: image.AlphaType.PREMUL,
    editable: true,
  });

  try {
    const canvas = new drawing.Canvas(copy);
    canvas.drawImage(pixel, 0, 0);

    if (maxSize !== undefined) {
      const factor = Math.min(1, maxSize / Math.max(info.size.width, info.size.height));
      if (factor < 1)
        await copy.scale(
          Math.max(1, Math.round(info.size.width * factor)) / info.size.width,
          Math.max(1, Math.round(info.size.height * factor)) / info.size.height,
        );
    }

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
    } else if (mediaType === 'image/webp' && deviceInfo.apiAvailable(24)) {
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
    const info = await copy.getImageInfo();
    const canvas = new drawing.Canvas(copy);
    const brush = new drawing.Brush();
    brush.setColor({ red: tint[0], green: tint[1], blue: tint[2], alpha: tint[3] });
    brush.setBlendMode(drawing.BlendMode.SRC_IN);
    canvas.attachBrush(brush);
    canvas.drawRect({ left: 0, top: 0, right: info.size.width, bottom: info.size.height });
    canvas.detachBrush();

    return copy;
  } catch (error) {
    await copy.release();

    throw new ExpoImageError('ERR_IMAGE_TRANSFORM', String(error));
  }
}
