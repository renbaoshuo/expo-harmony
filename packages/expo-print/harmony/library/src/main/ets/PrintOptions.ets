/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError, ExpoRecordShape, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { webview } from '@kit.ArkWeb';

export const POINTS_PER_INCH: number = 72;
export const CSS_PIXELS_PER_INCH: number = 96;
export const ORIENTATION_LANDSCAPE: string = 'landscape';
const MAX_TEXT_ZOOM: number = 2147483647;

interface PageMargins {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface PrintOptions {
  html?: string;
  uri?: string;
  width: number;
  height: number;
  orientation?: string;
  margins: PageMargins;
  textZoom: number;
  base64: boolean;
}

const PAGE_MARGINS = ExpoValueTypes.shapedRecord<PageMargins>(
  'PageMargins',
  new ExpoRecordShape()
    .field('top', ExpoValueTypes.number().optional())
    .field('right', ExpoValueTypes.number().optional())
    .field('bottom', ExpoValueTypes.number().optional())
    .field('left', ExpoValueTypes.number().optional()),
  (fields: Record<string, ESObject>): PageMargins => ({
    top: fields.top ?? 0,
    right: fields.right ?? 0,
    bottom: fields.bottom ?? 0,
    left: fields.left ?? 0,
  }),
  (margins: PageMargins): Record<string, ESObject> => {
    const fields: Record<string, ESObject> = {};
    fields.top = margins.top;
    fields.right = margins.right;
    fields.bottom = margins.bottom;
    fields.left = margins.left;

    return fields;
  },
);

export const PRINT_OPTIONS = ExpoValueTypes.shapedRecord<PrintOptions>(
  'PrintOptions',
  new ExpoRecordShape()
    .field('html', ExpoValueTypes.string().optional())
    .field('uri', ExpoValueTypes.string().optional())
    .field('orientation', ExpoValueTypes.string().optional())
    .field('width', ExpoValueTypes.number().optional())
    .field('height', ExpoValueTypes.number().optional())
    .field('textZoom', ExpoValueTypes.number().optional())
    .field('base64', ExpoValueTypes.boolean())
    .field('margins', PAGE_MARGINS.optional()),
  (fields: Record<string, ESObject>): PrintOptions => ({
    html: fields.html,
    uri: fields.uri,
    orientation: fields.orientation,
    width: fields.width ?? 612,
    height: fields.height ?? 792,
    textZoom: fields.textZoom ?? 100,
    base64: fields.base64 ?? false,
    margins: fields.margins ?? { top: 0, right: 0, bottom: 0, left: 0 },
  }),
  (options: PrintOptions): Record<string, ESObject> => {
    const fields: Record<string, ESObject> = {};
    fields.html = options.html;
    fields.uri = options.uri;
    fields.orientation = options.orientation;
    fields.width = options.width;
    fields.height = options.height;
    fields.textZoom = options.textZoom;
    fields.base64 = options.base64;
    fields.margins = options.margins;

    return fields;
  },
);

export function pdfConfiguration(options: PrintOptions): webview.PdfConfiguration {
  let width = options.width;
  let height = options.height;
  if (options.orientation === ORIENTATION_LANDSCAPE && height > width) {
    width = options.height;
    height = options.width;
  }

  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    throw new ExpoModuleError('ERR_PRINT_INVALID_OPTIONS', 'Page width and height must be positive finite numbers.');
  }

  const widthInches = width / POINTS_PER_INCH;
  const heightInches = height / POINTS_PER_INCH;
  if (
    widthInches <= 0 ||
    heightInches <= 0 ||
    !Number.isFinite(widthInches * CSS_PIXELS_PER_INCH) ||
    !Number.isFinite(heightInches * CSS_PIXELS_PER_INCH)
  ) {
    throw new ExpoModuleError('ERR_PRINT_INVALID_OPTIONS', 'Page dimensions cannot be represented in ArkWeb units.');
  }

  if (!Number.isInteger(options.textZoom) || options.textZoom <= 0 || options.textZoom > MAX_TEXT_ZOOM) {
    throw new ExpoModuleError('ERR_PRINT_INVALID_OPTIONS', 'textZoom must be a positive int32 percentage.');
  }

  const margins = options.margins;
  if (
    !Number.isFinite(margins.left) ||
    !Number.isFinite(margins.right) ||
    !Number.isFinite(margins.top) ||
    !Number.isFinite(margins.bottom) ||
    margins.left < 0 ||
    margins.right < 0 ||
    margins.top < 0 ||
    margins.bottom < 0 ||
    margins.left >= width / 2 ||
    margins.right >= width / 2 ||
    margins.top >= height / 2 ||
    margins.bottom >= height / 2
  ) {
    // ArkWeb silently resets out-of-range margins to zero.
    throw new ExpoModuleError('ERR_PRINT_INVALID_OPTIONS', 'Each margin must be non-negative and smaller than half its page dimension.');
  }

  return {
    width: widthInches,
    height: heightInches,
    marginTop: margins.top / POINTS_PER_INCH,
    marginBottom: margins.bottom / POINTS_PER_INCH,
    marginLeft: margins.left / POINTS_PER_INCH,
    marginRight: margins.right / POINTS_PER_INCH,
    scale: 1,
    shouldPrintBackground: true,
  };
}
