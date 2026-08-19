import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import fs from '@ohos.file.fs';
import fileHash from '@ohos.file.hash';
import util from '@ohos.util';
import display from '@ohos.display';
import drawing from '@ohos.graphics.drawing';
import image from '@ohos.multimedia.image';
import { bundledFontCachePath } from './BundledFontCache';
import { ExpoFontError } from './ExpoFontError';

const SERVICE_NAME: string = 'ExpoFontService';
let registered: boolean = false;
const cache: Map<string, string> = new Map();

interface BundledFontManifestEntry {
  family: string;
  file: string;
}

interface BundledFontManifest {
  fonts: BundledFontManifestEntry[];
}

class BundledFontRecord {
  family: string;
  uri: string;
  constructor(family: string, uri: string) {
    this.family = family;
    this.uri = uri;
  }
}

interface FontRenderOptions {
  fontFamily?: string;
  fontPath?: string;
  size?: number;
  lineHeight?: number;
  color?: number;
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

class ExpoFontService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;

  constructor(context: UITurboModuleContext) {
    this.context = context;
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'renderToImage') {
      return await this.renderToImage(String(args[0]), args[1] as FontRenderOptions);
    }

    return this.invokeSync(method, args);
  }

  invokeSync(method: string, args: ESObject[]): ESObject {
    if (method === 'registerFont') {
      const family = String(args[0]);
      const path = String(args[1]);

      if (family.trim().length === 0 || path.length === 0) {
        throw new ExpoFontError('ERR_FONT_LOAD', 'Font family and path must be non-empty.');
      }

      const instance = this.context.rnInstance;
      if (instance.registerFont === undefined) {
        throw new ExpoFontError('ERR_FONT_MANAGER', 'This RNOH runtime does not expose registerFont.');
      }

      instance.registerFont(family, path);

      return true;
    }

    if (method === 'materializeFont') {
      const source = rawFontPath(String(args[0]));
      const directory = `${this.context.uiAbilityContext.cacheDir}/expo-fonts`;

      ensureDirectory(directory);
      const destination = materializeRawFont(this.context, source, directory);

      return `file://${destination}`;
    }

    if (method !== 'bundledFonts') {
      throw new ExpoFontError('ERR_FONT_UNKNOWN_METHOD', method);
    }

    let entries: BundledFontManifestEntry[] = [];

    try {
      const bytes = this.context.uiAbilityContext.resourceManager.getRawFileContentSync('expo-fonts.json');
      const manifest: ESObject = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes));

      if (manifest === null || typeof manifest !== 'object' || !Array.isArray(manifest.fonts)) {
        this.context.logger.warn('Ignoring expo-fonts.json because it does not contain a fonts array.');
      } else {
        entries = (manifest as BundledFontManifest).fonts;
      }
    } catch (error) {
      if (!String(error).includes('expo-fonts.json')) {
        this.context.logger.warn(`Ignoring invalid expo-fonts.json: ${String(error)}`);
      }
    }

    const declared = new Set<string>();
    entries.forEach((entry: BundledFontManifestEntry): void => {
      if (entry !== null && typeof entry === 'object' && typeof entry.file === 'string') {
        declared.add(entry.file);
      }
    });

    try {
      this.context.uiAbilityContext.resourceManager
        .getRawFileListSync('fonts')
        .slice()
        .sort()
        .forEach((name: string): void => {
          const match = /^(.+?)(?:_bold|_italic|_bold_italic)?\.(?:ttf|otf)$/.exec(name);
          const file = `fonts/${name}`;
          if (match !== null && !declared.has(file)) {
            entries.push({ family: match[1], file });
          }
        });
    } catch (_) {
      // rawfile/fonts is optional.
    }

    const directory = `${this.context.uiAbilityContext.cacheDir}/expo-fonts`;
    ensureDirectory(directory);

    const records: BundledFontRecord[] = [];
    entries.forEach((entry: BundledFontManifestEntry): void => {
      try {
        if (
          entry === null ||
          typeof entry !== 'object' ||
          typeof entry.family !== 'string' ||
          typeof entry.file !== 'string' ||
          entry.family.trim().length === 0 ||
          !/^fonts\/[A-Za-z0-9._-]+\.(?:ttf|otf)$/i.test(entry.file)
        ) {
          throw new ExpoFontError('ERR_FONT_BUNDLED_MANIFEST', 'Invalid bundled font entry.');
        }

        const destination = materializeRawFont(this.context, entry.file, directory);
        records.push(new BundledFontRecord(entry.family, `file://${destination}`));
      } catch (error) {
        this.context.logger.warn(`Skipping an invalid bundled Expo font: ${String(error)}`);
      }
    });

    return records;
  }

  private async renderToImage(glyphs: string, options: FontRenderOptions): Promise<FontRenderResult> {
    const size = options.size ?? 24;
    const lineHeight = options.lineHeight;

    if (!Number.isFinite(size) || size <= 0 || (lineHeight !== undefined && (!Number.isFinite(lineHeight) || lineHeight <= 0))) {
      throw new ExpoFontError('ERR_FONT_RENDER_OPTIONS', 'size and lineHeight must be positive finite numbers.');
    }

    const scale = display.getDefaultDisplaySync().densityPixels;
    const font = new drawing.Font();
    font.setSize(size * scale);
    font.enableSubpixel(true);

    const path = options.fontPath;
    if (path !== undefined && path.length > 0) {
      font.setTypeface(drawing.Typeface.makeFromFile(path));
    }

    const metrics = font.getMetrics();
    const width = Math.ceil(font.measureText(glyphs, drawing.TextEncoding.TEXT_ENCODING_UTF8));
    const height = lineHeight === undefined ? Math.ceil(metrics.descent - metrics.ascent) : Math.ceil(lineHeight * scale);

    if (width <= 0 || height <= 0) {
      throw new ExpoFontError('ERR_FONT_RENDER_EMPTY', 'Text produced an empty image.');
    }

    const pixels = new ArrayBuffer(width * height * 4);
    const map = image.createPixelMapSync(pixels, {
      size: { width, height },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true,
      alphaType: image.AlphaType.PREMUL,
    });
    const packer = image.createImagePacker();

    try {
      const canvas = new drawing.Canvas(map);
      const brush = new drawing.Brush();
      const color = normalizedArgb(options.color ?? -16777216);

      brush.setColor(color.alpha, color.red, color.green, color.blue);
      brush.setAntiAlias(true);
      canvas.attachBrush(brush);

      try {
        const blob = drawing.TextBlob.makeFromString(glyphs, font);
        const textHeight = metrics.descent - metrics.ascent;
        const baseline = lineHeight === undefined ? -metrics.ascent : (height - textHeight) / 2 - metrics.ascent;

        canvas.drawTextBlob(blob, 0, baseline);
      } finally {
        canvas.detachBrush();
      }

      const png = await packer.packToData(map, { format: 'image/png', quality: 100 });
      const output = `${this.context.uiAbilityContext.cacheDir}/expo-font-${Date.now()}-${Math.floor(Math.random() * 0x7fffffff)}.png`;
      const file = fs.openSync(output, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);

      try {
        writeAll(file.fd, png, 0);
      } finally {
        fs.closeSync(file.fd);
      }

      return new FontRenderResult(`file://${output}`, width / scale, height / scale, scale);
    } catch (error) {
      throw new ExpoFontError('ERR_FONT_RENDER', String(error));
    } finally {
      await packer.release();
      await map.release();
    }
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

function normalizedArgb(value: number): ArgbColor {
  if (!Number.isFinite(value)) {
    throw new ExpoFontError('ERR_FONT_RENDER_OPTIONS', 'color must be numeric.');
  }

  const unsigned = value < 0 ? value + 0x100000000 : value;

  return new ArgbColor(
    Math.floor(unsigned / 0x1000000) % 0x100,
    Math.floor(unsigned / 0x10000) % 0x100,
    Math.floor(unsigned / 0x100) % 0x100,
    Math.floor(unsigned) % 0x100,
  );
}

function rawFontPath(uri: string): string {
  const asset = uri.startsWith('asset://');
  const raw = uri
    .replace(/^(?:asset|rawfile):\/\//, '')
    .replace(/^\/+/, '')
    .split(/[?#]/, 1)[0];

  let decoded: string;
  try {
    decoded = decodeURIComponent(raw).replace(/\\/g, '/');
  } catch (_) {
    throw new ExpoFontError('ERR_FONT_SOURCE', 'Font asset URI has invalid escaping.');
  }

  const segments = decoded.split('/');
  if (
    segments.length === 0 ||
    segments.some((segment: string): boolean => {
      return segment.length === 0 || segment === '.' || segment === '..';
    }) ||
    !/\.(?:ttf|otf)$/i.test(decoded)
  ) {
    throw new ExpoFontError('ERR_FONT_SOURCE', 'Font asset URI is invalid.');
  }

  const name = segments.join('/');
  // RNOH's asset:// scheme points at Metro assets copied below rawfile/assets,
  // while rawfile:// is already relative to the rawfile root. Keep the same
  // mapping used by expo-asset so bundled font URIs are interchangeable.
  return asset ? `assets/${name}` : name;
}

function ensureDirectory(path: string): void {
  if (fs.accessSync(path)) {
    if (!fs.statSync(path).isDirectory()) {
      throw new ExpoFontError('ERR_FONT_CACHE_DIRECTORY', `'${path}' is not a directory.`);
    }

    return;
  }

  try {
    fs.mkdirSync(path, true);
  } catch (_) {
    if (!fs.accessSync(path) || !fs.statSync(path).isDirectory()) {
      throw new ExpoFontError('ERR_FONT_CACHE_DIRECTORY', `Could not create '${path}'.`);
    }
  }
}

function materializeRawFont(context: UITurboModuleContext, source: string, directory: string): string {
  const cached = cache.get(source);
  if (cached !== undefined) {
    if (fs.accessSync(cached)) return cached;

    cache.delete(source);
  }

  const descriptor = context.uiAbilityContext.resourceManager.getRawFdSync(source);
  const temp = `${directory}/.expo-font-${Date.now()}-${Math.floor(Math.random() * 0x7fffffff)}.tmp`;
  let cleanup = true;

  try {
    const output = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    const digest = fileHash.createHash('sha256');

    try {
      const buffer = new ArrayBuffer(64 * 1024);
      let copied = 0;

      while (copied < descriptor.length) {
        const length = Math.min(buffer.byteLength, descriptor.length - copied);
        const count = fs.readSync(descriptor.fd, buffer, { offset: descriptor.offset + copied, length });

        if (count <= 0) {
          throw new ExpoFontError('ERR_FONT_BUNDLED_READ', source);
        }

        const chunk = buffer.slice(0, count);
        digest.update(chunk);
        writeAll(output.fd, chunk, copied);

        copied += count;
      }
    } finally {
      fs.closeSync(output.fd);
    }

    const destination = bundledFontCachePath(directory, source, digest.digest());
    if (fs.accessSync(destination)) {
      fs.unlinkSync(temp);
      cleanup = false;
      cache.set(source, destination);

      return destination;
    }

    fs.moveFileSync(temp, destination, 0);
    cleanup = false;
    cache.set(source, destination);

    return destination;
  } finally {
    if (cleanup && fs.accessSync(temp)) fs.unlinkSync(temp);

    context.uiAbilityContext.resourceManager.closeRawFdSync(source);
  }
}

function writeAll(fd: number, data: ArrayBuffer, offset: number): void {
  let written = 0;

  while (written < data.byteLength) {
    const count = fs.writeSync(fd, data.slice(written), { offset: offset + written });
    if (count <= 0) {
      throw new ExpoFontError('ERR_FONT_BUNDLED_WRITE', 'Unable to write bundled font data.');
    }

    written += count;
  }
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoFontService(context),
  });

  registered = true;
}

export class ExpoHarmonyExpoFontPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerService();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-font';
  }
}
