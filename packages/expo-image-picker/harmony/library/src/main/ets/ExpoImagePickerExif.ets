/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { image } from '@kit.ImageKit';

const TEXT_KEYS: image.PropertyKey[] = [
  image.PropertyKey.MAKE,
  image.PropertyKey.MODEL,
  image.PropertyKey.SOFTWARE,
  image.PropertyKey.DATE_TIME,
  image.PropertyKey.DATE_TIME_ORIGINAL,
  image.PropertyKey.DATE_TIME_DIGITIZED,
  image.PropertyKey.OFFSET_TIME,
  image.PropertyKey.OFFSET_TIME_ORIGINAL,
  image.PropertyKey.OFFSET_TIME_DIGITIZED,
  image.PropertyKey.SUBSEC_TIME,
  image.PropertyKey.SUBSEC_TIME_ORIGINAL,
  image.PropertyKey.SUBSEC_TIME_DIGITIZED,
  image.PropertyKey.ARTIST,
  image.PropertyKey.COPYRIGHT,
  image.PropertyKey.IMAGE_DESCRIPTION,
  image.PropertyKey.USER_COMMENT,
  image.PropertyKey.EXIF_VERSION,
  image.PropertyKey.LENS_MAKE,
  image.PropertyKey.LENS_MODEL,
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
  image.PropertyKey.GPS_IMG_DIRECTION,
  image.PropertyKey.GPS_IMG_DIRECTION_REF,
  image.PropertyKey.GPS_SPEED,
  image.PropertyKey.GPS_SPEED_REF,
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
  image.PropertyKey.MAX_APERTURE_VALUE,
  image.PropertyKey.SUBJECT_DISTANCE,
  image.PropertyKey.FOCAL_LENGTH,
  image.PropertyKey.PIXEL_X_DIMENSION,
  image.PropertyKey.PIXEL_Y_DIMENSION,
  image.PropertyKey.DIGITAL_ZOOM_RATIO,
  image.PropertyKey.X_RESOLUTION,
  image.PropertyKey.Y_RESOLUTION,
];

export const EXIF_KEYS: image.PropertyKey[] = TEXT_KEYS.concat(NUMERIC_KEYS, [image.PropertyKey.ORIENTATION]);

// ImageKit returns libexif's TIFF orientation names.
const ORIENTATIONS: string[] = ['Top-left', 'Top-right', 'Bottom-right', 'Bottom-left', 'Left-top', 'Right-top', 'Right-bottom', 'Left-bottom'];

export function orientationCode(value?: string | null): number | undefined {
  if (value == null) return undefined;

  const code = Number(value);
  if (Number.isInteger(code) && code >= 1 && code <= 8) return code;

  const index = ORIENTATIONS.indexOf(value.trim());
  return index < 0 ? undefined : index + 1;
}

export async function readOrientation(source: image.ImageSource): Promise<number | undefined> {
  try {
    return orientationCode(await source.getImageProperty(image.PropertyKey.ORIENTATION));
  } catch (_) {
    return undefined;
  }
}

function rationalNumber(value: string): number | undefined {
  const input = value.trim();
  if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:\s*\/\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+))?$/.test(input)) return undefined;

  const parts = input.split('/');
  const result = Number(parts[0]) / (parts.length === 2 ? Number(parts[1]) : 1);
  return Number.isFinite(result) ? result : undefined;
}

function numericProperty(key: image.PropertyKey, value: string): number | undefined {
  // ImageKit returns human-readable units for these EXIF fields.
  if (key === image.PropertyKey.EXPOSURE_TIME) return rationalNumber(value.replace(/\s+sec\.$/, ''));
  if (key === image.PropertyKey.F_NUMBER) return rationalNumber(value.replace(/^f\//, ''));
  if (key === image.PropertyKey.FOCAL_LENGTH) return rationalNumber(value.replace(/\s+mm$/, ''));
  if (key === image.PropertyKey.SUBJECT_DISTANCE) return rationalNumber(value.replace(/\s+m$/, ''));
  return rationalNumber(value.replace(/\s+EV(?:\s+\([^()]*\))?$/, ''));
}

function direction(value?: string | null): string | undefined {
  // ImageKit can return GPS references as decimal ASCII codes.
  switch (value?.trim()) {
    case 'N':
    case '78':
      return 'N';
    case 'S':
    case '83':
      return 'S';
    case 'E':
    case '69':
      return 'E';
    case 'W':
    case '87':
      return 'W';
    default:
      return undefined;
  }
}

function coordinate(value: string, ref: string | undefined, positive: string, negative: string, maximum: number): number | undefined {
  if (ref !== positive && ref !== negative) return undefined;

  const parts = value.split(',').map((part: string): number | undefined => rationalNumber(part));
  if (parts.length !== 3) return undefined;

  const degrees = parts[0];
  const minutes = parts[1];
  const seconds = parts[2];
  if (degrees === undefined || minutes === undefined || seconds === undefined ||
    degrees < 0 || minutes < 0 || minutes >= 60 || seconds < 0 || seconds >= 60) return undefined;

  const decimal = degrees + minutes / 60 + seconds / 3600;
  if (decimal > maximum) return undefined;
  return ref === negative ? -decimal : decimal;
}

function altitudeReference(value?: string | null): number | undefined {
  if (value === '0' || value === 'Sea level') return 0;
  if (value === '1' || value === 'Sea level reference') return 1;
  return undefined;
}

export function decodeExifProperties(data: Record<image.PropertyKey, string | null>, includeLocation: boolean): Record<string, ESObject> {
  const exif: Record<string, ESObject> = {};
  const latitudeRef = includeLocation ? direction(data[image.PropertyKey.GPS_LATITUDE_REF]) : undefined;
  const longitudeRef = includeLocation ? direction(data[image.PropertyKey.GPS_LONGITUDE_REF]) : undefined;
  const altitudeRef = includeLocation ? altitudeReference(data[image.PropertyKey.GPS_ALTITUDE_REF]) : undefined;
  const keys = includeLocation ? EXIF_KEYS.concat(EXIF_LOCATION_KEYS) : EXIF_KEYS;

  for (const key of keys) {
    const raw = data[key];
    if (raw == null || raw.length === 0) continue;

    if (key === image.PropertyKey.ORIENTATION) exif[key] = orientationCode(raw) ?? raw;
    else if (key === image.PropertyKey.GPS_LATITUDE) exif[key] = coordinate(raw, latitudeRef, 'N', 'S', 90) ?? raw;
    else if (key === image.PropertyKey.GPS_LONGITUDE) exif[key] = coordinate(raw, longitudeRef, 'E', 'W', 180) ?? raw;
    else if (key === image.PropertyKey.GPS_LATITUDE_REF) exif[key] = latitudeRef ?? raw;
    else if (key === image.PropertyKey.GPS_LONGITUDE_REF) exif[key] = longitudeRef ?? raw;
    else if (key === image.PropertyKey.GPS_ALTITUDE_REF) exif[key] = altitudeRef ?? raw;
    else if (key === image.PropertyKey.GPS_ALTITUDE) {
      const altitude = rationalNumber(raw);
      exif[key] = altitude === undefined || altitudeRef === undefined ? raw : altitudeRef === 1 ? -altitude : altitude;
    } else if (NUMERIC_KEYS.includes(key) || key === image.PropertyKey.GPS_SPEED || key === image.PropertyKey.GPS_IMG_DIRECTION) {
      exif[key] = numericProperty(key, raw) ?? raw;
    } else exif[key] = raw;
  }

  return exif;
}
