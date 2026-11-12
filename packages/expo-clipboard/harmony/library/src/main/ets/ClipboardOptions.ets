/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError, ExpoRecordShape, ExpoValueType, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

export enum ContentType {
  PlainText = 'plain-text',
  HTML = 'html',
  Image = 'image',
  URL = 'url',
}

export enum StringFormat {
  PlainText = 'plainText',
  HTML = 'html',
}

export enum ImageFormat {
  PNG = 'png',
  JPEG = 'jpeg',
}

const STRING_FORMAT_VALUES: Record<string, StringFormat> = {
  'plainText': StringFormat.PlainText,
  'html': StringFormat.HTML,
};
const STRING_FORMAT = ExpoValueTypes.enumerable<StringFormat>('StringFormat', STRING_FORMAT_VALUES);

function stringOptions(name: string, field: string): ExpoValueType<StringFormat> {
  return ExpoValueTypes.shapedRecord<StringFormat>(
    name,
    new ExpoRecordShape().field(field, STRING_FORMAT.optional()),
    (fields: Record<string, ESObject>): StringFormat => (fields[field] as StringFormat | undefined) ?? StringFormat.PlainText,
    (format: StringFormat): Record<string, ESObject> => {
      const fields: Record<string, ESObject> = {};
      fields[field] = format;
      return fields;
    },
  );
}

export const GET_STRING_OPTIONS = stringOptions('GetStringOptions', 'preferredFormat');
export const SET_STRING_OPTIONS = stringOptions('SetStringOptions', 'inputFormat');

export class GetImageOptions {
  format: ImageFormat = ImageFormat.JPEG;
  jpegQuality: number = 1;
}

const IMAGE_FORMAT_VALUES: Record<string, ImageFormat> = { 'png': ImageFormat.PNG, 'jpeg': ImageFormat.JPEG };

export const GET_IMAGE_OPTIONS = ExpoValueTypes.shapedRecord<GetImageOptions>(
  'GetImageOptions',
  new ExpoRecordShape()
    .field('format', ExpoValueTypes.enumerable<ImageFormat>('ImageFormat', IMAGE_FORMAT_VALUES).optional())
    .field('jpegQuality', ExpoValueTypes.number().optional()),
  (fields: Record<string, ESObject>): GetImageOptions => {
    const options = new GetImageOptions();
    options.format = (fields['format'] as ImageFormat | undefined) ?? ImageFormat.JPEG;
    options.jpegQuality = (fields['jpegQuality'] as number | undefined) ?? 1;

    if (options.format === ImageFormat.JPEG && (!Number.isFinite(options.jpegQuality) || options.jpegQuality < 0 || options.jpegQuality > 1)) {
      throw new ExpoModuleError('ERR_INVALID_ARGUMENT', 'jpegQuality must be a finite number between 0 and 1.');
    }

    return options;
  },
  (options: GetImageOptions): Record<string, ESObject> => {
    const fields: Record<string, ESObject> = {};
    fields['format'] = options.format;
    fields['jpegQuality'] = options.jpegQuality;
    return fields;
  },
);
