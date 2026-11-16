/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { util } from '@kit.ArkTS';
import { ExpoImageError } from './ExpoImageError';

const BASE83: string = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~';

export class ColorFactor {
  r: number;
  g: number;
  b: number;

  constructor(r: number, g: number, b: number) {
    this.r = r;
    this.g = g;
    this.b = b;
  }
}

export function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

export function signPow(value: number, exponent: number): number {
  return Math.sign(value) * Math.pow(Math.abs(value), exponent);
}

export function srgbToLinear(value: number): number {
  const normalized = value / 255;
  return normalized <= 0.04045 ? normalized / 12.92 : Math.pow((normalized + 0.055) / 1.055, 2.4);
}

export function linearToSrgb(value: number): number {
  const normalized = clamp(value, 0, 1);
  return Math.round(255 * (normalized <= 0.0031308 ? normalized * 12.92 : 1.055 * Math.pow(normalized, 1 / 2.4) - 0.055));
}

export function decode83(value: string, start: number, end: number): number {
  let result = 0;

  for (let index = start; index < end; index += 1) {
    const digit = BASE83.indexOf(value[index]);
    if (digit < 0) throw new ExpoImageError('ERR_IMAGE_INVALID_HASH', 'The blurhash contains an invalid character.');
    result = result * 83 + digit;
  }

  return result;
}

function encode83(value: number, length: number): string {
  let result = '';

  for (let index = 1; index <= length; index += 1) {
    const divisor = Math.pow(83, length - index);
    result += BASE83[Math.floor(value / divisor) % 83];
  }

  return result;
}

function basisFactor(rgba: Uint8Array, width: number, height: number, column: number, row: number): ColorFactor {
  const normalization = column === 0 && row === 0 ? 1 : 2;
  let red = 0;
  let green = 0;
  let blue = 0;

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const basis = normalization * Math.cos((Math.PI * column * x) / width) * Math.cos((Math.PI * row * y) / height);
      const offset = (y * width + x) * 4;
      red += basis * srgbToLinear(rgba[offset]);
      green += basis * srgbToLinear(rgba[offset + 1]);
      blue += basis * srgbToLinear(rgba[offset + 2]);
    }
  }

  const scale = 1 / (width * height);

  return new ColorFactor(red * scale, green * scale, blue * scale);
}

export function blurhash(rgba: Uint8Array, width: number, height: number, columns: number, rows: number): string {
  const factors: ColorFactor[] = [];
  for (let y = 0; y < rows; y += 1) {
    for (let x = 0; x < columns; x += 1) {
      factors.push(basisFactor(rgba, width, height, x, y));
    }
  }

  let result = encode83(columns - 1 + (rows - 1) * 9, 1);
  let maximum = 1;

  if (factors.length > 1) {
    let peak = 0;

    for (let index = 1; index < factors.length; index += 1) {
      const factor = factors[index];
      peak = Math.max(peak, Math.abs(factor.r), Math.abs(factor.g), Math.abs(factor.b));
    }

    const quantized = Math.floor(clamp(Math.floor(peak * 166 - 0.5), 0, 82));
    maximum = (quantized + 1) / 166;
    result += encode83(quantized, 1);
  } else {
    result += encode83(0, 1);
  }

  const dc = factors[0];
  result += encode83((linearToSrgb(dc.r) << 16) + (linearToSrgb(dc.g) << 8) + linearToSrgb(dc.b), 4);

  for (let index = 1; index < factors.length; index += 1) {
    const factor = factors[index];
    const red = Math.floor(clamp(Math.floor(signPow(factor.r / maximum, 0.5) * 9 + 9.5), 0, 18));
    const green = Math.floor(clamp(Math.floor(signPow(factor.g / maximum, 0.5) * 9 + 9.5), 0, 18));
    const blue = Math.floor(clamp(Math.floor(signPow(factor.b / maximum, 0.5) * 9 + 9.5), 0, 18));
    result += encode83(red * 19 * 19 + green * 19 + blue, 2);
  }

  return result;
}

export class ThumbChannel {
  readonly nx: number;
  readonly ny: number;
  dc: number = 0;
  scale: number = 0;
  ac: number[] = [];

  constructor(nx: number, ny: number) {
    this.nx = nx;
    this.ny = ny;

    for (let cy = 0; cy < ny; cy += 1) {
      for (let cx = cy > 0 ? 0 : 1; cx * ny < nx * (ny - cy); cx += 1) this.ac.push(0);
    }
  }

  encode(width: number, height: number, values: number[]): ThumbChannel {
    let index = 0;
    const xFactors: number[] = new Array(width).fill(0);

    for (let cy = 0; cy < this.ny; cy += 1) {
      for (let cx = 0; cx * this.ny < this.nx * (this.ny - cy); cx += 1) {
        let factor = 0;
        for (let x = 0; x < width; x += 1) xFactors[x] = Math.cos((Math.PI / width) * cx * (x + 0.5));
        for (let y = 0; y < height; y += 1) {
          const yFactor = Math.cos((Math.PI / height) * cy * (y + 0.5));
          for (let x = 0; x < width; x += 1) factor += values[x + y * width] * xFactors[x] * yFactor;
        }
        factor /= width * height;
        if (cx === 0 && cy === 0) this.dc = factor;
        else {
          this.ac[index] = factor;
          this.scale = Math.max(this.scale, Math.abs(factor));
          index += 1;
        }
      }
    }

    if (this.scale > 0) {
      for (let index = 0; index < this.ac.length; index += 1) this.ac[index] = 0.5 + (0.5 * this.ac[index]) / this.scale;
    }

    return this;
  }

  write(output: Uint8Array, start: number, offset: number): number {
    let index = offset;

    for (const value of this.ac) {
      const shift = (index & 1) << 2;
      output[start + (index >> 1)] |= Math.round(15 * value) << shift;
      index += 1;
    }

    return index;
  }

  decode(input: Uint8Array, start: number, offset: number, scale: number): number {
    let index = offset;

    for (let factor = 0; factor < this.ac.length; factor += 1) {
      const shift = (index & 1) << 2;
      this.ac[factor] = (((input[start + (index >> 1)] >> shift) & 15) / 7.5 - 1) * scale;
      index += 1;
    }

    return index;
  }
}

export function thumbhash(rgba: Uint8Array, width: number, height: number): string {
  let avgRed = 0;
  let avgGreen = 0;
  let avgBlue = 0;
  let avgAlpha = 0;

  for (let index = 0; index < width * height; index += 1) {
    const alpha = rgba[index * 4 + 3] / 255;
    avgRed += (alpha * rgba[index * 4]) / 255;
    avgGreen += (alpha * rgba[index * 4 + 1]) / 255;
    avgBlue += (alpha * rgba[index * 4 + 2]) / 255;
    avgAlpha += alpha;
  }

  if (avgAlpha > 0) {
    avgRed /= avgAlpha;
    avgGreen /= avgAlpha;
    avgBlue /= avgAlpha;
  }

  const hasAlpha = avgAlpha < width * height;
  const limit = hasAlpha ? 5 : 7;
  const lx = Math.max(1, Math.round((limit * width) / Math.max(width, height)));
  const ly = Math.max(1, Math.round((limit * height) / Math.max(width, height)));
  const luminance: number[] = [];
  const yellowBlue: number[] = [];
  const redGreen: number[] = [];
  const alphas: number[] = [];

  for (let index = 0; index < width * height; index += 1) {
    const alpha = rgba[index * 4 + 3] / 255;
    const red = avgRed * (1 - alpha) + (alpha * rgba[index * 4]) / 255;
    const green = avgGreen * (1 - alpha) + (alpha * rgba[index * 4 + 1]) / 255;
    const blue = avgBlue * (1 - alpha) + (alpha * rgba[index * 4 + 2]) / 255;

    luminance.push((red + green + blue) / 3);
    yellowBlue.push((red + green) / 2 - blue);
    redGreen.push(red - green);
    alphas.push(alpha);
  }

  const l = new ThumbChannel(Math.max(3, lx), Math.max(3, ly)).encode(width, height, luminance);
  const p = new ThumbChannel(3, 3).encode(width, height, yellowBlue);
  const q = new ThumbChannel(3, 3).encode(width, height, redGreen);
  const a = hasAlpha ? new ThumbChannel(5, 5).encode(width, height, alphas) : undefined;
  const landscape = width > height;

  const header24 =
    Math.round(63 * l.dc) |
    (Math.round(31.5 + 31.5 * p.dc) << 6) |
    (Math.round(31.5 + 31.5 * q.dc) << 12) |
    (Math.round(31 * l.scale) << 18) |
    (hasAlpha ? 1 << 23 : 0);
  const header16 = (landscape ? ly : lx) | (Math.round(63 * p.scale) << 3) | (Math.round(63 * q.scale) << 9) | (landscape ? 1 << 15 : 0);

  const start = hasAlpha ? 6 : 5;
  const count = l.ac.length + p.ac.length + q.ac.length + (a?.ac.length ?? 0);
  const output = new Uint8Array(start + Math.floor((count + 1) / 2));

  output[0] = header24;
  output[1] = header24 >> 8;
  output[2] = header24 >> 16;
  output[3] = header16;
  output[4] = header16 >> 8;
  if (a !== undefined) output[5] = Math.round(15 * a.dc) | (Math.round(15 * a.scale) << 4);

  let index = l.write(output, start, 0);
  index = p.write(output, start, index);
  index = q.write(output, start, index);
  if (a !== undefined) a.write(output, start, index);

  return new util.Base64Helper().encodeToStringSync(output);
}
