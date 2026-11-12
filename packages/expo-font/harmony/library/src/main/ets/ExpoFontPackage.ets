/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoValueType,
  ExpoValueTypes,
  fileUriFromPath,
  isRnohRawfileResourceUri,
  openRawResourceFile,
  rawResourcePathFromUri,
} from '@expo-harmony/expo-modules-core';
import fs from '@ohos.file.fs';
import fileHash from '@ohos.file.hash';
import util from '@ohos.util';
import display from '@ohos.display';
import drawing from '@ohos.graphics.drawing';
import text from '@ohos.graphics.text';
import image from '@ohos.multimedia.image';
import deviceInfo from '@ohos.deviceInfo';
import { bundledFontCachePath } from './BundledFontCache';
import { ExpoFontError } from './ExpoFontError';

interface BundledFontManifestEntry {
  family: string;
  file: string;
  sha256?: string;
  size?: number;
}

interface BundledFontManifest {
  fonts: BundledFontManifestEntry[];
}

interface CachedRawFont {
  path: string;
  digest: string;
  size: number;
}

const FONT_COPY_CHUNK_BYTES: number = 64 * 1024;
const MAX_FONT_BYTES: number = 32 * 1024 * 1024;
const MAX_RENDER_GLYPH_CODE_UNITS: number = 100_000;
const MAX_RENDER_SIDE_PIXELS: number = 8_192;
const MAX_RENDER_BUFFER_BYTES: number = 64 * 1024 * 1024;

// Graphics font registration uses a process-wide collection.
let fontRegistrationTail: Promise<void> = Promise.resolve();

class FontRenderOptions {
  fontFamily: string = '';
  size: number = 24;
  lineHeight?: number = undefined;
  color: number = -16777216;
}

class FontRenderResult {
  uri: string;
  width: number;
  height: number;
  scale: number;

  constructor(uri: string, width: number, height: number, scale: number) {
    this.uri = uri;
    this.width = width;
    this.height = height;
    this.scale = scale;
  }
}

class ArgbColor {
  alpha: number;
  red: number;
  green: number;
  blue: number;

  constructor(alpha: number, red: number, green: number, blue: number) {
    this.alpha = alpha;
    this.red = red;
    this.green = green;
    this.blue = blue;
  }
}

const FONT_RENDER_OPTIONS_TYPE: ExpoValueType<FontRenderOptions> = new ExpoValueType<FontRenderOptions>(
  'RenderToImageOptions object',
  (value: ESObject, path: string): FontRenderOptions => decodeRenderOptions(value, path),
  (value: FontRenderOptions): ESObject => encodeRenderOptions(value),
);

const FONT_RENDER_RESULT_TYPE: ExpoValueType<FontRenderResult> = new ExpoValueType<FontRenderResult>(
  'RenderToImageResult object',
  (value: ESObject, path: string): FontRenderResult => decodeRenderResult(value, path),
  (value: FontRenderResult): ESObject => encodeRenderResult(value),
);

export class ExpoFontLoaderModule extends ExpoModule {
  private readonly fonts: Map<string, string[]> = new Map<string, string[]>();
  private readonly cache: Map<string, CachedRawFont> = new Map<string, CachedRawFont>();
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoFontLoader')
      .syncFunction(
        'getLoadedFonts',
        ExpoFunction.typed0((): string[] => this.getLoadedFonts()).returns(ExpoValueTypes.array(ExpoValueTypes.string())),
      )
      .asyncFunction(
        'loadAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          async (family: string, uri: string): Promise<void> => this.load(family, uri),
        ),
      )
      .onCreate((): void => this.loadBundledFonts())
      .onDestroy((): void => this.destroy());
  }

  private getLoadedFonts(): string[] {
    this.assertActive();
    return Array.from(this.fonts.keys()).sort();
  }

  private async load(family: string, uri: string): Promise<void> {
    this.assertFamily(family, false);

    const operation = fontRegistrationTail.catch((): void => {}).then(async (): Promise<void> => {
      const path = this.validateSource(uri);
      const existing = this.fonts.get(family);
      if (existing !== undefined && existing.length === 1 && existing[0] === path) return;

      // FontCollection strips file:// without decoding the native path.
      const source = `file://${path}`;
      const collection = text.FontCollection.getGlobalInstance();
      if (deviceInfo.sdkApiVersion >= 23) await collection.loadFontWithCheck(family, source);
      else if (deviceInfo.sdkApiVersion >= 18) await collection.loadFont(family, source);
      else collection.loadFontSync(family, source);

      this.assertActive();

      this.context.registerReactNativeFont(family, path);
      this.fonts.set(family, [path]);
    });

    fontRegistrationTail = operation;
    await operation;
  }

  private loadBundledFonts(): void {
    this.assertActive();
    const entries: BundledFontManifestEntry[] = this.readBundledFontEntries();
    entries.forEach((entry: BundledFontManifestEntry): void => this.assertBundledEntry(entry));

    entries.forEach((entry: BundledFontManifestEntry): void => this.loadBundled(entry));
  }

  private readBundledFontEntries(): BundledFontManifestEntry[] {
    let files: string[];
    try {
      files = this.context.uiAbilityContext.resourceManager.getRawFileListSync('');
    } catch (error) {
      throw new ExpoFontError(
        'ERR_FONT_BUNDLED_MANIFEST',
        `Unable to enumerate bundled resources: ${errorMessage(error as Object)}`,
        error as Object,
      );
    }

    if (files.includes('expo-fonts.json')) {
      try {
        const bytes = this.context.uiAbilityContext.resourceManager.getRawFileContentSync('expo-fonts.json');

        const manifest: ESObject = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes));
        if (manifest === null || typeof manifest !== 'object' || !Array.isArray((manifest as BundledFontManifest).fonts)) {
          throw new ExpoFontError('ERR_FONT_BUNDLED_MANIFEST', 'expo-fonts.json must contain a fonts array.');
        }

        return (manifest as BundledFontManifest).fonts.slice();
      } catch (error) {
        if (error instanceof ExpoFontError) throw new ExpoFontError(error.code, error.message, error.cause);
        throw new ExpoFontError('ERR_FONT_BUNDLED_MANIFEST', `Unable to read expo-fonts.json: ${errorMessage(error as Object)}`, error as Object);
      }
    }

    const entries: BundledFontManifestEntry[] = [];

    try {
      this.context.uiAbilityContext.resourceManager
        .getRawFileListSync('fonts')
        .slice()
        .sort()
        .forEach((name: string): void => {
          const match = /^([A-Za-z0-9._-]+)\.(?:ttf|otf)$/i.exec(name);
          const file = `fonts/${name}`;
          if (match !== null) {
            entries.push({ family: match[1], file });
          }
        });
    } catch (error) {
      if (files.includes('fonts')) {
        throw new ExpoFontError('ERR_FONT_BUNDLED_MANIFEST', `Unable to enumerate bundled fonts: ${errorMessage(error as Object)}`, error as Object);
      }
    }

    return entries;
  }

  private assertBundledEntry(entry: BundledFontManifestEntry): void {
    if (
      entry === null ||
      typeof entry !== 'object' ||
      typeof entry.family !== 'string' ||
      typeof entry.file !== 'string' ||
      !/^fonts\/[A-Za-z0-9._-]+\.(?:ttf|otf)$/i.test(entry.file) ||
      (entry.sha256 !== undefined && !/^[A-Fa-f0-9]{64}$/.test(entry.sha256)) ||
      (entry.size !== undefined && (!Number.isSafeInteger(entry.size) || entry.size <= 0))
    ) {
      throw new ExpoFontError('ERR_FONT_BUNDLED_MANIFEST', 'Invalid bundled font entry.');
    }
    this.assertFamily(entry.family, true);
  }

  private loadBundled(entry: BundledFontManifestEntry): void {
    const source = this.validateSource(`rawfile://${entry.file}`, entry.sha256, entry.size);
    const existing = this.fonts.get(entry.family);
    if (existing !== undefined && existing.includes(source)) return;

    const collection = text.FontCollection.getGlobalInstance();
    const uri = `file://${source}`;
    if (deviceInfo.sdkApiVersion >= 23) collection.loadFontSyncWithCheck(entry.family, uri);
    else collection.loadFontSync(entry.family, uri);
    this.assertActive();

    this.context.registerReactNativeFont(entry.family, source);
    if (existing === undefined) this.fonts.set(entry.family, [source]);
    else existing.push(source);
  }

  private validateSource(uri: string, digest?: string, size?: number): string {
    this.assertActive();

    let path: string;
    if (uri.startsWith('asset://') || uri.startsWith('rawfile://') || isRnohRawfileResourceUri(uri)) {
      const directory = `${this.context.cachePath}/expo-fonts`;
      ensureDirectory(directory);
      path = materializeRawFont(this.context, uri, directory, this.cache, digest, size);
    } else {
      try {
        path = this.context.filePathForRead(uri);
      } catch (error) {
        throw new ExpoFontError('ERR_FONT_SOURCE', errorMessage(error as Object), error as Object);
      }
    }

    // Apply the same path constraints to materialized resources and local URI paths.
    // Prefix containment checks require a path without traversal segments.
    if (
      !path.startsWith('/') || path.includes('\0') || path.includes('\\') ||
      path.split('/').some((segment: string): boolean => segment === '.' || segment === '..')
    ) {
      throw new ExpoFontError('ERR_FONT_SOURCE', 'Font source must resolve to an absolute local path without traversal segments.');
    }

    const granted = this.context.assertFileAccess(path);
    const application = this.context.uiAbilityContext.getApplicationContext();
    const roots: string[] = [
      this.context.persistentFilesPath,
      this.context.cachePath,
      this.context.temporaryPath,
      application.filesDir,
      application.cacheDir,
    ];
    const root = roots.find((candidate: string): boolean => isInside(candidate, path));
    if (root === undefined && !granted) {
      throw new ExpoFontError('ERR_FONT_SOURCE_OUTSIDE_SANDBOX', 'Font URI is outside the application sandbox.');
    }

    if (root !== undefined) assertNoSymlinkSegments(root, path);

    try {
      const stat = fs.lstatSync(path);
      if (stat.isSymbolicLink() || !stat.isFile()) {
        throw new ExpoFontError('ERR_FONT_SOURCE', `Font file '${uri}' does not exist.`);
      }
      if (stat.size <= 0) {
        throw new ExpoFontError('ERR_FONT_SOURCE', 'Font file for the requested family is empty.');
      }
      if (stat.size > MAX_FONT_BYTES) {
        throw new ExpoFontError('ERR_FONT_SOURCE_TOO_LARGE', `Font files cannot exceed ${MAX_FONT_BYTES} bytes.`);
      }
    } catch (error) {
      if (error instanceof ExpoFontError) throw new ExpoFontError(error.code, error.message, error.cause);
      throw new ExpoFontError('ERR_FONT_SOURCE', `Font file '${uri}' does not exist.`, error as Object);
    }

    return path;
  }

  private assertFamily(family: string, bundled: boolean): void {
    if (family.trim().length === 0) {
      throw new ExpoFontError('ERR_FONT_FAMILY', bundled ? 'Bundled font family cannot be empty.' : 'Font family cannot be empty.');
    }
  }

  private assertActive(): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoFontError('ERR_FONT_MANAGER', 'The Expo font module runtime is no longer available.');
    }
  }

  private destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.fonts.clear();
    this.cache.clear();
  }
}

export class ExpoFontUtilsModule extends ExpoModule {
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoFontUtils')
      .asyncFunction(
        'renderToImageAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          FONT_RENDER_OPTIONS_TYPE.defaulted(new FontRenderOptions()),
          async (glyphs: string, options: FontRenderOptions): Promise<FontRenderResult> => {
            return await this.renderToImage(glyphs, options);
          },
        ).returns(FONT_RENDER_RESULT_TYPE),
      )
      .onDestroy((): void => {
        this.destroyed = true;
      });
  }

  private async renderToImage(glyphs: string, options: FontRenderOptions): Promise<FontRenderResult> {
    this.assertActive();
    if (
      !Number.isFinite(options.size) ||
      options.size <= 0 ||
      (options.lineHeight !== undefined && (!Number.isFinite(options.lineHeight) || options.lineHeight <= 0))
    ) {
      throw new ExpoFontError('ERR_FONT_RENDER_OPTIONS', 'size and lineHeight must be positive finite numbers.');
    }
    if (glyphs.length > MAX_RENDER_GLYPH_CODE_UNITS) {
      throw new ExpoFontError('ERR_FONT_RENDER_TOO_LARGE', `Text cannot exceed ${MAX_RENDER_GLYPH_CODE_UNITS} UTF-16 code units.`);
    }

    const scale = display.getDefaultDisplaySync().densityPixels;
    if (!Number.isFinite(scale) || scale <= 0) {
      throw new ExpoFontError('ERR_FONT_RENDER', 'Display density must be a positive finite number.');
    }

    const size = options.size * scale;
    const lineHeight = options.lineHeight === undefined ? undefined : options.lineHeight * scale;
    const ratio = options.lineHeight === undefined ? 1 : options.lineHeight / options.size;
    if (
      !Number.isFinite(size) ||
      size <= 0 ||
      size > MAX_RENDER_SIDE_PIXELS ||
      !Number.isFinite(ratio) ||
      ratio <= 0 ||
      (lineHeight !== undefined && (!Number.isFinite(lineHeight) || lineHeight <= 0 || lineHeight > MAX_RENDER_SIDE_PIXELS))
    ) {
      throw new ExpoFontError(
        'ERR_FONT_RENDER_TOO_LARGE',
        `Scaled font size and lineHeight must be positive and cannot exceed ${MAX_RENDER_SIDE_PIXELS}px.`,
      );
    }

    const color = normalizedArgb(options.color);
    const style: text.TextStyle = {
      color,
      fontFamilies: options.fontFamily.length === 0 ? [] : [options.fontFamily],
      fontSize: size,
      heightOnly: options.lineHeight !== undefined,
      heightScale: ratio,
      halfLeading: options.lineHeight !== undefined,
    };

    const builder = new text.ParagraphBuilder({ textStyle: style }, text.FontCollection.getGlobalInstance());
    builder.pushStyle(style);
    builder.addText(glyphs);
    builder.popStyle();

    const paragraph = builder.build();
    // The extra pixel prevents boundary rounding from wrapping; intrinsic width still rejects oversized lines.
    paragraph.layoutSync(MAX_RENDER_SIDE_PIXELS + 1);
    const width = Math.ceil(paragraph.getMaxIntrinsicWidth());
    const height = Math.ceil(paragraph.getHeight());
    if (width <= 0 || height <= 0) {
      throw new ExpoFontError('ERR_FONT_RENDER_EMPTY', 'Text produced an empty image.');
    }

    const pixels = width * height;
    const bytes = pixels * 4;
    if (
      !Number.isSafeInteger(pixels) ||
      !Number.isSafeInteger(bytes) ||
      width > MAX_RENDER_SIDE_PIXELS ||
      height > MAX_RENDER_SIDE_PIXELS ||
      bytes > MAX_RENDER_BUFFER_BYTES
    ) {
      throw new ExpoFontError(
        'ERR_FONT_RENDER_TOO_LARGE',
        `Rendered text exceeds the ${MAX_RENDER_SIDE_PIXELS}px side or ${MAX_RENDER_BUFFER_BYTES}-byte buffer limit.`,
      );
    }

    const buffer = new ArrayBuffer(bytes);
    const map = image.createPixelMapSync(buffer, {
      size: { width, height },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true,
      alphaType: image.AlphaType.PREMUL,
    });

    const id = util.generateRandomUUID();
    const temp = `${this.context.cachePath}/.expo-font-${id}.tmp`;
    const output = `${this.context.cachePath}/expo-font-${id}.png`;
    let committed = false;

    try {
      const packer = image.createImagePacker();
      try {
        const canvas = new drawing.Canvas(map);
        paragraph.paint(canvas, 0, 0);
        const png = await packer.packToData(map, { format: 'image/png', quality: 100 });
        this.assertActive();

        await writeFileFully(temp, png);
        await fs.moveFile(temp, output, 0);
        this.assertActive();

        committed = true;
        return new FontRenderResult(fileUriFromPath(output), width / scale, height / scale, scale);
      } finally {
        try {
          await packer.release();
        } catch (error) {
          this.context.logger.warn(`Unable to release the font image packer: ${errorMessage(error as Object)}`);
        }
      }
    } catch (error) {
      if (error instanceof ExpoFontError) throw new ExpoFontError(error.code, error.message, error.cause);
      throw new ExpoFontError('ERR_FONT_RENDER', errorMessage(error as Object), error as Object);
    } finally {
      try {
        await map.release();
      } catch (error) {
        this.context.logger.warn(`Unable to release the font PixelMap: ${errorMessage(error as Object)}`);
      }

      await unlinkIfExists(temp);
      if (!committed || this.destroyed || !this.context.isValid) await unlinkIfExists(output);
      if (committed) this.assertActive();
    }
  }

  private assertActive(): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoFontError('ERR_FONT_MANAGER', 'The Expo font module runtime is no longer available.');
    }
  }
}

function decodeRenderOptions(value: ESObject, path: string): FontRenderOptions {
  const record = requireRecord(value, path);
  const result = new FontRenderOptions();
  if (record.fontFamily !== undefined) {
    result.fontFamily = requireString(record.fontFamily, `${path}.fontFamily`);
  }
  if (record.size !== undefined) result.size = requireNumber(record.size, `${path}.size`);
  if (record.lineHeight !== undefined && record.lineHeight !== null) {
    result.lineHeight = requireNumber(record.lineHeight, `${path}.lineHeight`);
  }
  if (record.color !== undefined) result.color = requireNumber(record.color, `${path}.color`);

  return result;
}

function encodeRenderOptions(value: FontRenderOptions): ESObject {
  return value;
}

function decodeRenderResult(value: ESObject, path: string): FontRenderResult {
  const record = requireRecord(value, path);
  return new FontRenderResult(
    requireString(record.uri, `${path}.uri`),
    requireNumber(record.width, `${path}.width`),
    requireNumber(record.height, `${path}.height`),
    requireNumber(record.scale, `${path}.scale`),
  );
}

function encodeRenderResult(value: FontRenderResult): ESObject {
  return value;
}

function requireRecord(value: ESObject, path: string): Record<string, ESObject> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    const actual = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
    throw new ExpoFontError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected object, received ${actual}.`);
  }
  return value as Record<string, ESObject>;
}

function requireString(value: ESObject, path: string): string {
  if (typeof value !== 'string') {
    const actual = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
    throw new ExpoFontError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected string, received ${actual}.`);
  }
  return value;
}

function requireNumber(value: ESObject, path: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    const actual = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
    throw new ExpoFontError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected finite number, received ${actual}.`);
  }
  return value;
}

function normalizedArgb(value: number): ArgbColor {
  if (!Number.isInteger(value) || value < -0x80000000 || value > 0xffffffff) {
    throw new ExpoFontError('ERR_FONT_RENDER_OPTIONS', 'color must be a signed or unsigned 32-bit integer.');
  }

  const unsigned = value < 0 ? value + 0x100000000 : value;
  return new ArgbColor(
    Math.floor(unsigned / 0x1000000) % 0x100,
    Math.floor(unsigned / 0x10000) % 0x100,
    Math.floor(unsigned / 0x100) % 0x100,
    Math.floor(unsigned) % 0x100,
  );
}

function isInside(root: string, path: string): boolean {
  const base = root.endsWith('/') ? root.substring(0, root.length - 1) : root;
  return path === base || path.startsWith(`${base}/`);
}

function assertNoSymlinkSegments(root: string, path: string): void {
  const base = root.endsWith('/') ? root.substring(0, root.length - 1) : root;
  const suffix = path.slice(base.length).replace(/^\/+/, '');
  let current = base;
  const segments = suffix.length === 0 ? [] : suffix.split('/');

  try {
    const stat = fs.lstatSync(current);
    if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error('Invalid root');

    segments.forEach((segment: string, index: number): void => {
      current = `${current}/${segment}`;
      const stat = fs.lstatSync(current);
      if (stat.isSymbolicLink()) throw new Error('Symbolic link');
      if (index < segments.length - 1 && !stat.isDirectory()) throw new Error('Not a directory');
    });
  } catch (error) {
    throw new ExpoFontError('ERR_FONT_SOURCE_OUTSIDE_SANDBOX', 'Font URI traverses a symbolic link or invalid sandbox path.', error as Object);
  }
}

function rawFontPath(uri: string): string {
  let path: string;
  try {
    path = rawResourcePathFromUri(uri);
  } catch (error) {
    throw new ExpoFontError('ERR_FONT_SOURCE', 'Font asset URI is invalid.', error as Object);
  }
  if (!/\.(?:ttf|otf)$/i.test(path)) {
    throw new ExpoFontError('ERR_FONT_SOURCE', 'Font asset URI is invalid.');
  }
  return path;
}

function ensureDirectory(path: string): void {
  if (fs.accessSync(path)) {
    const stat = fs.lstatSync(path);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new ExpoFontError('ERR_FONT_CACHE_DIRECTORY', `'${path}' is not a directory.`);
    }
    return;
  }

  try {
    fs.mkdirSync(path, true);
  } catch (_) {
    if (!fs.accessSync(path)) {
      throw new ExpoFontError('ERR_FONT_CACHE_DIRECTORY', `Could not create '${path}'.`);
    }
  }

  const stat = fs.lstatSync(path);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new ExpoFontError('ERR_FONT_CACHE_DIRECTORY', `'${path}' is not a directory.`);
  }
}

function materializeRawFont(
  context: ExpoModuleContext,
  uri: string,
  directory: string,
  cache: Map<string, CachedRawFont>,
  digest?: string,
  size?: number,
): string {
  const source = rawFontPath(uri);
  const identity = `${source}:${digest?.toLowerCase() ?? ''}:${size ?? ''}`;
  const cached = cache.get(identity);
  if (cached !== undefined) {
    if (verifyCachedFont(cached.path, cached.digest, cached.size)) return cached.path;

    cache.delete(identity);
    unlinkIfExistsSync(cached.path);
  }

  if (digest !== undefined) {
    const destination = bundledFontCachePath(directory, source, digest);
    if (verifyCachedFont(destination, digest, size)) {
      return destination;
    }

    unlinkIfExistsSync(destination);
  }

  const temp = `${directory}/.expo-font-${util.generateRandomUUID()}.tmp`;
  const descriptor = openRawResourceFile(context.uiAbilityContext.resourceManager, source);
  let cleanup = true;

  try {
    if (descriptor.length <= 0 || descriptor.length > MAX_FONT_BYTES) {
      throw new ExpoFontError('ERR_FONT_SOURCE_TOO_LARGE', `Bundled font size must be between 1 and ${MAX_FONT_BYTES} bytes.`);
    }
    if (size !== undefined && descriptor.length !== size) {
      throw new ExpoFontError('ERR_FONT_BUNDLED_MANIFEST', 'Bundled font size does not match its manifest.');
    }

    const output = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC | fs.OpenMode.NOFOLLOW);
    let checksum = '';

    try {
      const hash = fileHash.createHash('sha256');
      const buffer = new ArrayBuffer(FONT_COPY_CHUNK_BYTES);
      let copied = 0;

      while (copied < descriptor.length) {
        const length = Math.min(buffer.byteLength, descriptor.length - copied);
        const count = fs.readSync(descriptor.file.fd, buffer, { offset: descriptor.offset + copied, length });
        if (count <= 0) {
          throw new ExpoFontError('ERR_FONT_BUNDLED_READ', source);
        }

        const chunk = buffer.slice(0, count);
        hash.update(chunk);
        writeAll(output.fd, chunk);
        copied += count;
      }

      checksum = hash.digest().toLowerCase();
    } finally {
      fs.closeSync(output.fd);
    }

    if (digest !== undefined && checksum !== digest.toLowerCase()) {
      throw new ExpoFontError('ERR_FONT_BUNDLED_MANIFEST', 'Bundled font digest does not match its manifest.');
    }

    const destination = bundledFontCachePath(directory, source, checksum);
    if (verifyCachedFont(destination, checksum, descriptor.length)) {
      unlinkIfExistsSync(temp);
      cleanup = false;
      cache.set(identity, { path: destination, digest: checksum, size: descriptor.length });

      return destination;
    }

    unlinkIfExistsSync(destination);
    try {
      fs.moveFileSync(temp, destination, 0);
    } catch (error) {
      if (!verifyCachedFont(destination, checksum, descriptor.length)) {
        throw new ExpoFontError('ERR_FONT_BUNDLED_WRITE', `Unable to commit bundled font '${source}'.`, error as Object);
      }
      unlinkIfExistsSync(temp);
    }

    cleanup = false;
    cache.set(identity, { path: destination, digest: checksum, size: descriptor.length });

    return destination;
  } finally {
    if (cleanup) unlinkIfExistsSync(temp);

    try {
      fs.closeSync(descriptor.file.fd);
    } catch (error) {
      context.logger.warn(`Unable to close bundled font '${source}': ${errorMessage(error as Object)}`);
    }
  }
}

function verifyCachedFont(path: string, digest?: string, size?: number): boolean {
  try {
    const stat = fs.lstatSync(path);
    if (stat.isSymbolicLink() || !stat.isFile() || stat.size <= 0 || stat.size > MAX_FONT_BYTES) {
      return false;
    }
    if (size !== undefined && stat.size !== size) return false;
    if (digest !== undefined && fileDigestSync(path) !== digest.toLowerCase()) return false;
    return true;
  } catch (_) {
    return false;
  }
}

function fileDigestSync(path: string): string {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
  const digest = fileHash.createHash('sha256');
  try {
    const buffer = new ArrayBuffer(FONT_COPY_CHUNK_BYTES);
    while (true) {
      const count = fs.readSync(file.fd, buffer, { length: buffer.byteLength });
      if (count === 0) break;
      if (count < 0) throw new ExpoFontError('ERR_FONT_BUNDLED_READ', path);
      digest.update(count === buffer.byteLength ? buffer : buffer.slice(0, count));
    }

    return digest.digest().toLowerCase();
  } finally {
    fs.closeSync(file.fd);
  }
}

function unlinkIfExistsSync(path: string): void {
  try {
    if (fs.accessSync(path)) fs.unlinkSync(path);
  } catch (_) {}
}

function writeAll(fd: number, data: ArrayBuffer): void {
  let written = 0;
  while (written < data.byteLength) {
    const count = fs.writeSync(fd, data.slice(written));
    if (count <= 0) {
      throw new ExpoFontError('ERR_FONT_BUNDLED_WRITE', 'Unable to write bundled font data.');
    }
    written += count;
  }
}

async function writeFileFully(path: string, data: ArrayBuffer): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC | fs.OpenMode.NOFOLLOW);
  try {
    let written = 0;
    while (written < data.byteLength) {
      const count = await fs.write(file.fd, data.slice(written));
      if (count <= 0) {
        throw new ExpoFontError('ERR_FONT_RENDER_WRITE', 'Unable to write rendered font image.');
      }
      written += count;
    }
  } finally {
    await fs.close(file.fd);
  }
}

async function unlinkIfExists(path: string): Promise<void> {
  try {
    if (await fs.access(path)) await fs.unlink(path);
  } catch (_) {}
}

function errorMessage(error: Object): string {
  try {
    return String(error);
  } catch (_) {
    return 'Unknown font error';
  }
}
