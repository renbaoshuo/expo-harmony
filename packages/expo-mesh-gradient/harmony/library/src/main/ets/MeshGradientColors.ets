/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// Oklab matrices: https://bottosson.github.io/posts/oklab/ (Björn Ottosson).

function linearize(value: number): number {
  return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
}

function encode(value: number): number {
  return value <= 0.0031308 ? value * 12.92 : 1.055 * Math.pow(value, 1 / 2.4) - 0.055;
}

function toOklab(color: number): number[] {
  const r = linearize(((color >>> 16) & 255) / 255);
  const g = linearize(((color >>> 8) & 255) / 255);
  const b = linearize((color & 255) / 255);

  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);

  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

function byte(value: number): number {
  return Math.round(Math.min(1, Math.max(0, value)) * 255);
}

function fromOklab(lightness: number, a: number, b: number, alpha: number): number {
  const l = Math.pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3);
  const m = Math.pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3);
  const s = Math.pow(lightness - 0.0894841775 * a - 1.291485548 * b, 3);

  const r = encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s);
  const g = encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s);
  const blue = encode(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s);

  return ((byte(alpha) << 24) | (byte(r) << 16) | (byte(g) << 8) | byte(blue)) >>> 0;
}

function interpolateSrgb(start: number, end: number, fraction: number): number {
  const t = 3 * fraction * fraction - 2 * fraction * fraction * fraction;
  let result = 0;

  for (let shift = 0; shift <= 24; shift += 8) {
    const channel = Math.round(((start >>> shift) & 255) * (1 - t) + ((end >>> shift) & 255) * t);
    result |= channel << shift;
  }

  return result >>> 0;
}

export function createColorSampler(start: number, end: number, smooth: boolean): (fraction: number) => number {
  if (start === end) return (): number => start;
  if (smooth) return (fraction: number): number => interpolateSrgb(start, end, fraction);

  const a = toOklab(start);
  const b = toOklab(end);
  const startAlpha = start >>> 24;
  const endAlpha = end >>> 24;

  return (fraction: number): number => fromOklab(
    a[0] * (1 - fraction) + b[0] * fraction,
    a[1] * (1 - fraction) + b[1] * fraction,
    a[2] * (1 - fraction) + b[2] * fraction,
    (startAlpha * (1 - fraction) + endAlpha * fraction) / 255,
  );
}
