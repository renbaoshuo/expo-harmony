/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// BlurHash by Wolt Enterprises: https://github.com/woltapp/blurhash
// ThumbHash by Evan Wallace: https://github.com/evanw/thumbhash
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import taskpool from '@ohos.taskpool';
import { ExpoImageError } from './ExpoImageError';
import { ColorFactor, ThumbChannel, clamp, signPow, srgbToLinear, linearToSrgb, decode83, blurhash, thumbhash } from './ExpoImageHashCodec';

function pixelMap(width: number, height: number, rgba: Uint8Array): image.PixelMap {
  return image.createPixelMapSync(rgba.buffer, {
    size: { width, height },
    srcPixelFormat: image.PixelMapFormat.RGBA_8888,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    alphaType: image.AlphaType.UNPREMUL,
    editable: true,
  });
}

export function decodeBlurhash(hash: string, targetWidth: number, targetHeight: number): image.PixelMap {
  const width = Math.max(1, Math.min(512, Math.round(targetWidth)));
  const height = Math.max(1, Math.min(512, Math.round(targetHeight)));

  if (hash.length < 6) throw new ExpoImageError('ERR_IMAGE_INVALID_HASH', 'The blurhash is too short.');

  const size = decode83(hash, 0, 1);
  const columns = (size % 9) + 1;
  const rows = Math.floor(size / 9) + 1;
  if (rows > 9 || hash.length !== 4 + 2 * columns * rows) {
    throw new ExpoImageError('ERR_IMAGE_INVALID_HASH', 'The blurhash length does not match its component count.');
  }

  const maximum = (decode83(hash, 1, 2) + 1) / 166;
  const factors: ColorFactor[] = [];
  for (let index = 0; index < columns * rows; index += 1) {
    if (index === 0) {
      const color = decode83(hash, 2, 6);
      factors.push(new ColorFactor(srgbToLinear(color >> 16), srgbToLinear((color >> 8) & 255), srgbToLinear(color & 255)));
    } else {
      const color = decode83(hash, 4 + index * 2, 6 + index * 2);
      factors.push(
        new ColorFactor(
          signPow((Math.floor(color / (19 * 19)) - 9) / 9, 2) * maximum,
          signPow(((Math.floor(color / 19) % 19) - 9) / 9, 2) * maximum,
          signPow(((color % 19) - 9) / 9, 2) * maximum,
        ),
      );
    }
  }

  const output = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      let red = 0;
      let green = 0;
      let blue = 0;
      for (let row = 0; row < rows; row += 1) {
        for (let column = 0; column < columns; column += 1) {
          const basis = Math.cos((Math.PI * x * column) / width) * Math.cos((Math.PI * y * row) / height);
          const factor = factors[row * columns + column];
          red += factor.r * basis;
          green += factor.g * basis;
          blue += factor.b * basis;
        }
      }

      const offset = (y * width + x) * 4;
      output[offset] = linearToSrgb(red);
      output[offset + 1] = linearToSrgb(green);
      output[offset + 2] = linearToSrgb(blue);
      output[offset + 3] = 255;
    }
  }

  return pixelMap(width, height, output);
}

async function readRgba(pixel: image.PixelMap): Promise<Uint8Array> {
  const info = await pixel.getImageInfo();
  if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
    throw new ExpoImageError('ERR_IMAGE_PIXEL_FORMAT', 'Hash generation requires RGBA pixels.');
  }

  const rgba = new Uint8Array(pixel.getPixelBytesNumber());
  await pixel.readPixelsToBuffer(rgba.buffer);

  // Hash algorithms consume straight alpha; native drawing uses premultiplied RGB.
  if (info.alphaType === image.AlphaType.PREMUL) {
    for (let offset = 0; offset < rgba.length; offset += 4) {
      const alpha = rgba[offset + 3];
      if (alpha > 0 && alpha < 255) {
        for (let channel = 0; channel < 3; channel += 1) rgba[offset + channel] = Math.min(255, Math.round((rgba[offset + channel] * 255) / alpha));
      }
    }
  }

  return rgba;
}

export async function encodeBlurhash(pixel: image.PixelMap, columns: number, rows: number): Promise<string> {
  if (!Number.isInteger(columns) || !Number.isInteger(rows) || columns < 1 || columns > 9 || rows < 1 || rows > 9) {
    throw new ExpoImageError('ERR_IMAGE_INVALID_HASH_COMPONENTS', 'Blurhash component counts must be integers between 1 and 9.');
  }

  const info = await pixel.getImageInfo();
  const rgba = await readRgba(pixel);

  return (await taskpool.execute(encodeBlurhashData, rgba, info.size.width, info.size.height, columns, rows)) as string;
}

@Concurrent
function encodeBlurhashData(rgba: Uint8Array, width: number, height: number, columns: number, rows: number): string {
  return blurhash(rgba, width, height, columns, rows);
}

export async function encodeThumbhash(pixel: image.PixelMap): Promise<string> {
  const info = await pixel.getImageInfo();
  const width = info.size.width;
  const height = info.size.height;
  if (width > 100 || height > 100) {
    throw new ExpoImageError('ERR_IMAGE_HASH_TOO_LARGE', 'Thumbhash input must be at most 100 by 100 pixels.');
  }

  return (await taskpool.execute(encodeThumbhashData, await readRgba(pixel), width, height)) as string;
}

@Concurrent
function encodeThumbhashData(rgba: Uint8Array, width: number, height: number): string {
  return thumbhash(rgba, width, height);
}

export async function decodeThumbhash(encoded: string): Promise<image.PixelMap> {
  let hash: Uint8Array;
  try {
    hash = await new util.Base64Helper().decode(encoded);
  } catch (_) {
    throw new ExpoImageError('ERR_IMAGE_INVALID_HASH', 'The thumbhash is not valid base64.');
  }

  if (hash.length < 5) throw new ExpoImageError('ERR_IMAGE_INVALID_HASH', 'The thumbhash is too short.');

  const header24 = hash[0] | (hash[1] << 8) | (hash[2] << 16);
  const header16 = hash[3] | (hash[4] << 8);
  const lDc = (header24 & 63) / 63;
  const pDc = ((header24 >> 6) & 63) / 31.5 - 1;
  const qDc = ((header24 >> 12) & 63) / 31.5 - 1;
  const lScale = ((header24 >> 18) & 31) / 31;
  const hasAlpha = header24 >> 23 !== 0;
  const pScale = ((header16 >> 3) & 63) / 63;
  const qScale = ((header16 >> 9) & 63) / 63;
  const landscape = header16 >> 15 !== 0;
  const columns = landscape ? (hasAlpha ? 5 : 7) : header16 & 7;
  const rows = landscape ? header16 & 7 : hasAlpha ? 5 : 7;
  if (columns <= 0 || rows <= 0) {
    throw new ExpoImageError('ERR_IMAGE_INVALID_HASH', 'The thumbhash contains an invalid aspect ratio.');
  }

  const lx = Math.max(3, columns);
  const ly = Math.max(3, rows);

  if (hasAlpha && hash.length < 6) throw new ExpoImageError('ERR_IMAGE_INVALID_HASH', 'The thumbhash alpha header is missing.');

  const aDc = hasAlpha ? (hash[5] & 15) / 15 : 1;
  const aScale = hasAlpha ? ((hash[5] >> 4) & 15) / 15 : 0;
  const start = hasAlpha ? 6 : 5;
  let index = 0;

  const l = new ThumbChannel(lx, ly);
  const p = new ThumbChannel(3, 3);
  const q = new ThumbChannel(3, 3);
  const a = hasAlpha ? new ThumbChannel(5, 5) : undefined;
  const required = l.ac.length + p.ac.length + q.ac.length + (a?.ac.length ?? 0);

  if (hash.length < start + Math.floor((required + 1) / 2)) {
    throw new ExpoImageError('ERR_IMAGE_INVALID_HASH', 'The thumbhash coefficient data is truncated.');
  }

  index = l.decode(hash, start, index, lScale);
  index = p.decode(hash, start, index, pScale * 1.25);
  index = q.decode(hash, start, index, qScale * 1.25);
  if (a !== undefined) a.decode(hash, start, index, aScale);

  const ratio = columns / rows;
  const width = Math.max(1, Math.round(ratio > 1 ? 32 : 32 * ratio));
  const height = Math.max(1, Math.round(ratio > 1 ? 32 / ratio : 32));
  const rgba = new Uint8Array(width * height * 4);
  const maxX = Math.max(lx, hasAlpha ? 5 : 3);
  const maxY = Math.max(ly, hasAlpha ? 5 : 3);
  const cosX: number[] = new Array(maxX).fill(0);
  const cosY: number[] = new Array(maxY).fill(0);

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      let luminance = lDc;
      let yellowBlue = pDc;
      let redGreen = qDc;
      let alpha = aDc;

      for (let cx = 0; cx < maxX; cx += 1) cosX[cx] = Math.cos((Math.PI / width) * (x + 0.5) * cx);
      for (let cy = 0; cy < maxY; cy += 1) cosY[cy] = Math.cos((Math.PI / height) * (y + 0.5) * cy);

      let factor = 0;
      for (let cy = 0; cy < ly; cy += 1) {
        for (let cx = cy > 0 ? 0 : 1; cx * ly < lx * (ly - cy); cx += 1) {
          luminance += l.ac[factor] * cosX[cx] * cosY[cy] * 2;
          factor += 1;
        }
      }

      factor = 0;
      for (let cy = 0; cy < 3; cy += 1) {
        for (let cx = cy > 0 ? 0 : 1; cx < 3 - cy; cx += 1) {
          const basis = cosX[cx] * cosY[cy] * 2;
          yellowBlue += p.ac[factor] * basis;
          redGreen += q.ac[factor] * basis;
          factor += 1;
        }
      }

      if (a !== undefined) {
        factor = 0;
        for (let cy = 0; cy < 5; cy += 1) {
          for (let cx = cy > 0 ? 0 : 1; cx < 5 - cy; cx += 1) {
            alpha += a.ac[factor] * cosX[cx] * cosY[cy] * 2;
            factor += 1;
          }
        }
      }

      const blue = luminance - (2 * yellowBlue) / 3;
      const red = (3 * luminance - blue + redGreen) / 2;
      const green = red - redGreen;
      const offset = (y * width + x) * 4;
      rgba[offset] = Math.trunc(255 * clamp(red, 0, 1));
      rgba[offset + 1] = Math.trunc(255 * clamp(green, 0, 1));
      rgba[offset + 2] = Math.trunc(255 * clamp(blue, 0, 1));
      rgba[offset + 3] = Math.trunc(255 * clamp(alpha, 0, 1));
    }
  }

  return pixelMap(width, height, rgba);
}
