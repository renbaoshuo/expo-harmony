/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { deviceInfo } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';

// Use the EXIF strings on SDKs older than Image Kit's API 23 Orientation enum.
enum ExifOrientation {
  TOP_LEFT = 'Top-left',
  TOP_RIGHT = 'Top-right',
  BOTTOM_RIGHT = 'Bottom-right',
  BOTTOM_LEFT = 'Bottom-left',
  LEFT_TOP = 'Left-top',
  RIGHT_TOP = 'Right-top',
  RIGHT_BOTTOM = 'Right-bottom',
  LEFT_BOTTOM = 'Left-bottom',
}

export async function applyImageOrientation(source: image.ImageSource, pixel: image.PixelMap): Promise<void> {
  let orientation: string;

  try {
    orientation = await source.getImageProperty(image.PropertyKey.ORIENTATION, { defaultValue: ExifOrientation.TOP_LEFT });
  } catch (_) {
    return;
  }

  let horizontal = false;
  let vertical = false;
  let rotation = 0;

  switch (orientation.trim()) {
    case '2':
    case ExifOrientation.TOP_RIGHT:
      horizontal = true;
      break;
    case '3':
    case ExifOrientation.BOTTOM_RIGHT:
      rotation = 180;
      break;
    case '4':
    case ExifOrientation.BOTTOM_LEFT:
      vertical = true;
      break;
    case '5':
    case ExifOrientation.LEFT_TOP:
      horizontal = true;
      rotation = 270;
      break;
    case '6':
    case ExifOrientation.RIGHT_TOP:
      rotation = 90;
      break;
    case '7':
    case ExifOrientation.RIGHT_BOTTOM:
      horizontal = true;
      rotation = 90;
      break;
    case '8':
    case ExifOrientation.LEFT_BOTTOM:
      rotation = 270;
      break;
  }

  if (!horizontal && !vertical && rotation === 0) return;

  // Apply the mirror before rotating for the transpose and transverse orientations.
  if (typeof deviceInfo.apiAvailable === 'function') {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (horizontal || vertical) await pixel.applyFlip(horizontal, vertical);
      if (rotation !== 0) await pixel.applyRotate(rotation);
      return;
    }
  }

  if (horizontal || vertical) await pixel.flip(horizontal, vertical);
  if (rotation !== 0) await pixel.rotate(rotation);
}
