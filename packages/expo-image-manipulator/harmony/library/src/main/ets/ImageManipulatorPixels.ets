/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { drawing } from '@kit.ArkGraphics2D';
import { deviceInfo } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';

const PIXEL_MAP_CLONE_API = 18;

export function copyPixelMap(source: image.PixelMap): image.PixelMap {
  // Copy synchronously: the source SharedRef can be released as soon as manipulate() returns.
  let pixel: image.PixelMap | undefined;

  try {
    pixel = image.createPixelMapSync({
      size: source.getImageInfoSync().size,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.PREMUL,
      editable: true,
    });
    if (pixel === undefined || pixel === null) throw new Error('Could not allocate an image bitmap.');

    const canvas = new drawing.Canvas(pixel);
    const brush = new drawing.Brush();
    brush.setBlendMode(drawing.BlendMode.SRC);
    canvas.attachBrush(brush);

    try {
      canvas.drawImage(source, 0, 0);
    } finally {
      canvas.detachBrush();
    }

    return pixel;
  } catch (error) {
    if (pixel !== undefined && pixel !== null) releasePixelMap(pixel);

    throw new ExpoModuleError('ERR_IMAGE_MANIPULATOR', 'Could not copy the image bitmap.', error as Object);
  }
}

export async function snapshotPixelMap(source: image.PixelMap): Promise<image.PixelMap> {
  if (deviceInfo.sdkApiVersion >= PIXEL_MAP_CLONE_API) {
    try {
      return await source.clone();
    } catch (error) {
      throw new ExpoModuleError('ERR_IMAGE_MANIPULATOR', 'Could not copy the image bitmap.', error as Object);
    }
  }

  return copyPixelMap(source);
}

export async function releasePixelMap(pixel: image.PixelMap): Promise<void> {
  try {
    await pixel.release();
  } catch (error) {
    console.warn(`ImageManipulator could not release a bitmap: ${String(error)}`);
  }
}
