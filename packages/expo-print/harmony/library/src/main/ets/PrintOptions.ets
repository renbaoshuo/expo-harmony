import { ExpoModuleError, ExpoValueType, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { webview } from '@kit.ArkWeb';

export const POINTS_PER_INCH: number = 72;
export const CSS_PIXELS_PER_INCH: number = 96;
const MAX_TEXT_ZOOM: number = 2147483647;

export class PageMargins {
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  left: number = 0;
}

export class PrintOptions {
  html?: string;
  uri?: string;
  width: number = 612;
  height: number = 792;
  orientation?: string;
  margins: PageMargins = new PageMargins();
  textZoom: number = 100;
  base64: boolean = false;
}

export const PRINT_OPTIONS = new ExpoValueType<PrintOptions>(
  'PrintOptions',
  (value: ESObject, path: string): PrintOptions => decodeOptions(value, path),
  (value: PrintOptions): ESObject => value,
);

function decodeOptions(value: ESObject, path: string): PrintOptions {
  const record = requireRecord(value, path);

  const options = new PrintOptions();
  options.html = optionalString(record['html'], `${path}.html`);
  options.uri = optionalString(record['uri'], `${path}.uri`);
  options.orientation = optionalString(record['orientation'], `${path}.orientation`);
  options.width = optionalNumber(record['width'], `${path}.width`) ?? options.width;
  options.height = optionalNumber(record['height'], `${path}.height`) ?? options.height;
  options.textZoom = optionalNumber(record['textZoom'], `${path}.textZoom`) ?? options.textZoom;
  if (record['base64'] !== undefined) {
    options.base64 = ExpoValueTypes.boolean().decode(record['base64'], `${path}.base64`);
  }

  const margins: ESObject = record['margins'];
  if (margins !== undefined && margins !== null) {
    const fields = requireRecord(margins, `${path}.margins`);
    options.margins.top = optionalNumber(fields['top'], `${path}.margins.top`) ?? 0;
    options.margins.right = optionalNumber(fields['right'], `${path}.margins.right`) ?? 0;
    options.margins.bottom = optionalNumber(fields['bottom'], `${path}.margins.bottom`) ?? 0;
    options.margins.left = optionalNumber(fields['left'], `${path}.margins.left`) ?? 0;
  }

  return options;
}

export function pdfConfiguration(options: PrintOptions): webview.PdfConfiguration {
  let width = options.width;
  let height = options.height;
  if (options.orientation === 'landscape' && height > width) {
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
    // ArkWeb silently resets out-of-range margins to zero. Reject rather than change the requested layout.
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

function requireRecord(value: ESObject, path: string): Record<string, ESObject> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoModuleError('ERR_PRINT_INVALID_OPTIONS', `${path} must be an object.`);
  }
  return value as Record<string, ESObject>;
}

function optionalString(value: ESObject, path: string): string | undefined {
  return value === undefined || value === null ? undefined : ExpoValueTypes.string().decode(value, path);
}

function optionalNumber(value: ESObject, path: string): number | undefined {
  return value === undefined || value === null ? undefined : ExpoValueTypes.number().decode(value, path);
}
