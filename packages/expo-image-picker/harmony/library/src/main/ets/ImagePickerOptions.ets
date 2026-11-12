/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { ExpoImagePickerError } from './ExpoImagePickerError';
import { ProcessingOptions } from './ExpoImagePickerMedia';

export interface ImagePickerOptions extends ProcessingOptions {
  allowsEditing: boolean;
  allowsMultipleSelection: boolean;
  selectionLimit: number;
  mediaTypes: string[];
  videoMaxDuration: number;
  cameraType: string;
  aspect?: number[];
  shape: string;
}

export const IMAGE_PICKER_OPTIONS = ExpoValueTypes.custom<ImagePickerOptions>(
  'ImagePickerOptions',
  (value: ESObject): ImagePickerOptions => readOptions(value),
  (value: ImagePickerOptions): ESObject => value,
);

function readOptions(value: ESObject): ImagePickerOptions {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoImagePickerError('ERR_INVALID_ARGUMENT', 'ImagePicker options must be an object.');
  }

  const record = value as Record<string, ESObject>;
  const quality = readNumber(record, 'quality', 1);
  if (quality > 1) throw new ExpoImagePickerError('ERR_INVALID_ARGUMENT', 'quality must be between 0 and 1.');

  const limit = readNumber(record, 'selectionLimit', 0);
  if (!Number.isSafeInteger(limit)) throw new ExpoImagePickerError('ERR_INVALID_ARGUMENT', 'selectionLimit must be an integer.');

  const types = record['mediaTypes'] == null ? ['images'] : ExpoValueTypes.array(ExpoValueTypes.string()).decode(record['mediaTypes'], 'mediaTypes');
  if (types.some((type: string): boolean => !['images', 'videos', 'livePhotos'].includes(type))) {
    throw new ExpoImagePickerError('ERR_INVALID_ARGUMENT', 'Unknown ImagePicker media type.');
  }

  const aspect = record['aspect'] == null ? undefined : ExpoValueTypes.array(ExpoValueTypes.number()).decode(record['aspect'], 'aspect');
  if (aspect !== undefined && (aspect.length !== 2 || aspect.some((part: number): boolean => !Number.isFinite(part) || part <= 0))) {
    throw new ExpoImagePickerError('ERR_INVALID_ARGUMENT', 'aspect must contain two positive, finite numbers.');
  }

  return {
    allowsEditing: readBoolean(record, 'allowsEditing'),
    allowsMultipleSelection: readBoolean(record, 'allowsMultipleSelection'),
    quality,
    selectionLimit: limit,
    base64: readBoolean(record, 'base64'),
    exif: readBoolean(record, 'exif'),
    mediaTypes: types,
    videoMaxDuration: readNumber(record, 'videoMaxDuration', 0),
    cameraType: readEnum(record, 'cameraType', ['back', 'front']),
    aspect,
    shape: readEnum(record, 'shape', ['rectangle', 'oval']),
  };
}

function readBoolean(record: Record<string, ESObject>, key: string): boolean {
  return record[key] == null ? false : ExpoValueTypes.boolean().decode(record[key], key);
}

function readNumber(record: Record<string, ESObject>, key: string, fallback: number): number {
  if (record[key] == null) return fallback;
  const value = ExpoValueTypes.number().decode(record[key], key);
  if (!Number.isFinite(value) || value < 0) throw new ExpoImagePickerError('ERR_INVALID_ARGUMENT', `${key} must be a finite, non-negative number.`);
  return value;
}

function readEnum(record: Record<string, ESObject>, key: string, allowed: string[]): string {
  if (record[key] == null) return allowed[0];
  const value = ExpoValueTypes.string().decode(record[key], key);
  if (!allowed.includes(value)) throw new ExpoImagePickerError('ERR_INVALID_ARGUMENT', `${key} must be one of: ${allowed.join(', ')}.`);
  return value;
}

export function selectsVideos(options: ImagePickerOptions): boolean {
  return options.mediaTypes.includes('videos');
}

export function selectsImages(options: ImagePickerOptions): boolean {
  return options.mediaTypes.includes('images') || !selectsVideos(options);
}

export function validateEditing(options: ImagePickerOptions, camera: boolean): void {
  if (!options.allowsEditing || options.allowsMultipleSelection || !selectsImages(options)) return;
  if (camera || options.aspect !== undefined || options.shape !== 'rectangle') {
    throw new ExpoImagePickerError(
      'ERR_IMAGE_PICKER_UNSUPPORTED_EDITING',
      'HarmonyOS supports optional editing in the library picker only; camera editing, a fixed aspect ratio and oval cropping are unavailable.',
    );
  }
}
