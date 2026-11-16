/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { image } from '@kit.ImageKit';

export const EXIF_KEYS: image.PropertyKey[] = [
  image.PropertyKey.ORIENTATION,
  image.PropertyKey.IMAGE_WIDTH,
  image.PropertyKey.IMAGE_LENGTH,
  image.PropertyKey.MAKE,
  image.PropertyKey.MODEL,
  image.PropertyKey.SOFTWARE,
  image.PropertyKey.DATE_TIME,
  image.PropertyKey.DATE_TIME_ORIGINAL,
  image.PropertyKey.DATE_TIME_DIGITIZED,
  image.PropertyKey.EXPOSURE_TIME,
  image.PropertyKey.F_NUMBER,
  image.PropertyKey.ISO_SPEED_RATINGS,
  image.PropertyKey.APERTURE_VALUE,
  image.PropertyKey.SHUTTER_SPEED,
  image.PropertyKey.BRIGHTNESS_VALUE,
  image.PropertyKey.EXPOSURE_BIAS_VALUE,
  image.PropertyKey.FOCAL_LENGTH,
  image.PropertyKey.PIXEL_X_DIMENSION,
  image.PropertyKey.PIXEL_Y_DIMENSION,
];

export const EXIF_LOCATION_KEYS: image.PropertyKey[] = [
  image.PropertyKey.GPS_LATITUDE,
  image.PropertyKey.GPS_LATITUDE_REF,
  image.PropertyKey.GPS_LONGITUDE,
  image.PropertyKey.GPS_LONGITUDE_REF,
  image.PropertyKey.GPS_ALTITUDE,
  image.PropertyKey.GPS_ALTITUDE_REF,
  image.PropertyKey.GPS_TIME_STAMP,
  image.PropertyKey.GPS_DATE_STAMP,
];

const NUMERIC_KEYS: image.PropertyKey[] = [
  image.PropertyKey.IMAGE_WIDTH,
  image.PropertyKey.IMAGE_LENGTH,
  image.PropertyKey.EXPOSURE_TIME,
  image.PropertyKey.F_NUMBER,
  image.PropertyKey.ISO_SPEED_RATINGS,
  image.PropertyKey.APERTURE_VALUE,
  image.PropertyKey.SHUTTER_SPEED,
  image.PropertyKey.BRIGHTNESS_VALUE,
  image.PropertyKey.EXPOSURE_BIAS_VALUE,
  image.PropertyKey.FOCAL_LENGTH,
  image.PropertyKey.PIXEL_X_DIMENSION,
  image.PropertyKey.PIXEL_Y_DIMENSION,
];

// ImageKit returns libexif's TIFF orientation names.
const ORIENTATIONS: string[] = ['Top-left', 'Top-right', 'Bottom-right', 'Bottom-left', 'Left-top', 'Right-top', 'Right-bottom', 'Left-bottom'];

export function orientationCode(value?: string | null): number | undefined {
  if (value == null) return undefined;
  const number = Number(value);
  if (Number.isInteger(number) && number >= 1 && number <= 8) return number;
  const index = ORIENTATIONS.indexOf(value.trim());
  return index < 0 ? undefined : index + 1;
}

function rationalNumber(value: string): number | undefined {
  // Do not parse partial formatted strings (e.g. "1/60 sec.") as numbers.
  if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:\s*\/\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+))?$/.test(value.trim())) return undefined;
  const parts = value.trim().split('/');
  const number = Number(parts[0]) / (parts.length === 2 ? Number(parts[1]) : 1);
  return Number.isFinite(number) ? number : undefined;
}

function coordinate(value: string, ref: string | null | undefined): number | undefined {
  if (ref !== 'N' && ref !== 'S' && ref !== 'E' && ref !== 'W') return undefined;
  const parts = value.split(',').map((part: string): number | undefined => rationalNumber(part));
  if (parts.length !== 3 || parts.some((part: number | undefined): boolean => part === undefined)) return undefined;

  const degrees = (parts[0] as number) + (parts[1] as number) / 60 + (parts[2] as number) / 3600;
  return ref === 'S' || ref === 'W' ? -degrees : degrees;
}

export function decodeExifProperties(data: Record<image.PropertyKey, string | null>): Record<string, ESObject> {
  const exif: Record<string, ESObject> = {};

  for (const key of EXIF_KEYS.concat(EXIF_LOCATION_KEYS)) {
    const raw = data[key];
    if (raw == null || raw.length === 0) continue;

    if (key === image.PropertyKey.ORIENTATION) exif[key] = orientationCode(raw) ?? raw;
    else if (key === image.PropertyKey.GPS_LATITUDE) exif[key] = coordinate(raw, data[image.PropertyKey.GPS_LATITUDE_REF]) ?? raw;
    else if (key === image.PropertyKey.GPS_LONGITUDE) exif[key] = coordinate(raw, data[image.PropertyKey.GPS_LONGITUDE_REF]) ?? raw;
    else if (key === image.PropertyKey.GPS_ALTITUDE) {
      const altitude = rationalNumber(raw);
      const ref = data[image.PropertyKey.GPS_ALTITUDE_REF];
      exif[key] = altitude === undefined || (ref !== '0' && ref !== '1') ? raw : ref === '1' ? -altitude : altitude;
    } else if (NUMERIC_KEYS.includes(key)) exif[key] = rationalNumber(raw) ?? raw;
    else exif[key] = raw;
  }

  return exif;
}
