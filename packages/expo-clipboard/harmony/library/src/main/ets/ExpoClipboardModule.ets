import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoPermissionStatus,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { GET_IMAGE_OPTIONS, GET_STRING_OPTIONS, GetImageOptions, ImageFormat, SET_STRING_OPTIONS, StringFormat } from './ClipboardOptions';

const CLIPBOARD_CHANGED_EVENT: string = 'onClipboardChanged';
const READ_PERMISSION: Permissions = 'ohos.permission.READ_PASTEBOARD';
const PERMISSION_DENIED: number = 201;
const IMAGE_QUALITY_MAX: number = 100;
const FILE_READ_CHUNK_SIZE: number = 64 * 1024;

enum ContentType {
  PlainText = 'plain-text',
  HTML = 'html',
  Image = 'image',
  URL = 'url',
}

interface ClipboardImage {
  data: string;
  size: image.Size;
}

export class ExpoClipboardModule extends ExpoModule {
  private readonly board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
  private pending: Promise<void> = Promise.resolve();
  private destroyed: boolean = false;
  private observing: boolean = false;
  private listening: boolean = false;

  private readonly changed = (): void => {
    if (!this.observing || this.destroyed || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) return;

    try {
      const contentTypes: ContentType[] = [];
      const html = this.board.hasDataType(pasteboard.MIMETYPE_TEXT_HTML);
      if (html || this.board.hasDataType(pasteboard.MIMETYPE_TEXT_PLAIN)) contentTypes.push(ContentType.PlainText);
      if (html) contentTypes.push(ContentType.HTML);
      if (this.board.hasDataType(pasteboard.MIMETYPE_PIXELMAP)) contentTypes.push(ContentType.Image);
      if (this.board.hasDataType(pasteboard.MIMETYPE_TEXT_URI)) contentTypes.push(ContentType.URL);

      this.sendEvent(CLIPBOARD_CHANGED_EVENT, { contentTypes });
    } catch (error) {
      this.warn('inspect clipboard changes', error);
    }
  };

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoClipboard')
      .events([CLIPBOARD_CHANGED_EVENT])
      .asyncFunction(
        'getStringAsync',
        ExpoFunction.typed1(
          GET_STRING_OPTIONS,
          (format: StringFormat): Promise<string> => this.perform(async (): Promise<string> => this.readText(format)),
        ),
      )
      .asyncFunction(
        'setStringAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          SET_STRING_OPTIONS,
          (text: string, format: StringFormat): Promise<boolean> =>
            this.perform(async (): Promise<boolean> => {
              const data = pasteboard.createData(format === StringFormat.HTML ? pasteboard.MIMETYPE_TEXT_HTML : pasteboard.MIMETYPE_TEXT_PLAIN, text);
              if (format === StringFormat.HTML) {
                const plain = await plainTextFromHtml(text);
                const record = data.getRecord(0);
                record.addEntry(pasteboard.MIMETYPE_TEXT_PLAIN, plain);
                data.replaceRecord(0, record);
              }

              this.assertActive();
              await this.board.setData(data);

              return true;
            }),
        ),
      )
      .asyncFunction(
        'hasStringAsync',
        (): Promise<boolean> =>
          this.perform(
            async (): Promise<boolean> =>
              this.board.hasDataType(pasteboard.MIMETYPE_TEXT_PLAIN) || this.board.hasDataType(pasteboard.MIMETYPE_TEXT_HTML),
          ),
      )
      .asyncFunction(
        'getImageAsync',
        ExpoFunction.typed1(
          GET_IMAGE_OPTIONS,
          (options: GetImageOptions): Promise<ClipboardImage | null> =>
            this.perform(async (): Promise<ClipboardImage | null> => this.readImage(options), 'ERR_PASTE_FAILURE'),
        ),
      )
      .asyncFunction(
        'setImageAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          (base64: string): Promise<void> => this.perform(async (): Promise<void> => this.writeImage(base64), 'ERR_COPY_FAILURE'),
        ),
      )
      .asyncFunction(
        'hasImageAsync',
        (): Promise<boolean> => this.perform(async (): Promise<boolean> => this.board.hasDataType(pasteboard.MIMETYPE_PIXELMAP)),
      )
      .asyncFunction(
        'getUrlAsync',
        (): Promise<string | null> =>
          this.perform(
            async (): Promise<string | null> =>
              this.withPasteData(
                [pasteboard.MIMETYPE_TEXT_URI],
                null,
                async (data: pasteboard.PasteData): Promise<string | null> =>
                  ((await readEntry(data, pasteboard.MIMETYPE_TEXT_URI)) as string | undefined) ?? null,
              ),
          ),
      )
      .asyncFunction(
        'setUrlAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          (url: string): Promise<void> =>
            this.perform(async (): Promise<void> => this.board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_URI, url))),
        ),
      )
      .asyncFunction(
        'hasUrlAsync',
        (): Promise<boolean> => this.perform(async (): Promise<boolean> => this.board.hasDataType(pasteboard.MIMETYPE_TEXT_URI)),
      )
      .onStartObserving((): void => {
        this.listening = true;
        this.startObservation();
      })
      .onStopObserving((): void => {
        this.listening = false;
        this.stopObservation();
      })
      .onForeground((): void => this.startObservation())
      .onBackground((): void => this.stopObservation())
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private async readText(format: StringFormat): Promise<string> {
    return this.withPasteData(
      [pasteboard.MIMETYPE_TEXT_PLAIN, pasteboard.MIMETYPE_TEXT_HTML, pasteboard.MIMETYPE_TEXT_URI],
      '',
      async (data: pasteboard.PasteData): Promise<string> => {
        if (format === StringFormat.HTML) {
          const html = await readEntry(data, pasteboard.MIMETYPE_TEXT_HTML);
          if (typeof html === 'string') return html;
        }

        const plain = await readEntry(data, pasteboard.MIMETYPE_TEXT_PLAIN);
        if (typeof plain === 'string') return format === StringFormat.HTML ? htmlFromPlainText(plain) : plain;

        const html = await readEntry(data, pasteboard.MIMETYPE_TEXT_HTML);
        if (typeof html === 'string') return await plainTextFromHtml(html);

        const uri = await readEntry(data, pasteboard.MIMETYPE_TEXT_URI);
        if (typeof uri !== 'string') return '';

        return format === StringFormat.HTML ? htmlFromPlainText(uri) : uri;
      },
    );
  }

  private async readImage(options: GetImageOptions): Promise<ClipboardImage | null> {
    return this.withPasteData([pasteboard.MIMETYPE_PIXELMAP], null, async (data: pasteboard.PasteData): Promise<ClipboardImage | null> => {
      const bitmap = (await readEntry(data, pasteboard.MIMETYPE_PIXELMAP)) as image.PixelMap | undefined;
      if (bitmap === undefined) return null;

      try {
        this.assertActive();
        return await this.encodeImage(bitmap, options);
      } finally {
        await this.cleanup(async (): Promise<void> => bitmap.release(), 'release clipboard PixelMap');
      }
    });
  }

  private async encodeImage(bitmap: image.PixelMap, options: GetImageOptions): Promise<ClipboardImage> {
    const info = await bitmap.getImageInfo();
    this.assertActive();

    const mime = options.format === ImageFormat.PNG ? 'image/png' : 'image/jpeg';
    const quality = options.format === ImageFormat.PNG ? IMAGE_QUALITY_MAX : Math.floor(options.jpegQuality * IMAGE_QUALITY_MAX);
    const packer = image.createImagePacker();
    let file: fileIo.File | undefined;
    let path: string | undefined;

    try {
      const name = `${this.context.uiAbilityContext.tempDir}/expo-clipboard-${util.generateRandomUUID()}`;
      file = await fileIo.open(name, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      path = name;

      // packToData has a fixed default buffer limit; files allow any size supported by ImageKit.
      await packer.packToFile(bitmap, file.fd, { format: mime, quality });
      this.assertActive();

      const bytes = await readImageFile(file.fd);
      const base64 = await new util.Base64Helper().encodeToString(bytes);

      return { data: `data:${mime};base64,${base64}`, size: info.size };
    } finally {
      await this.cleanup(async (): Promise<void> => packer.release(), 'release image encoder');
      if (file !== undefined) {
        const fd = file.fd;
        await this.cleanup(async (): Promise<void> => fileIo.close(fd), 'close clipboard image file');
      }
      if (path !== undefined) {
        const filename = path;
        await this.cleanup(async (): Promise<void> => fileIo.unlink(filename), 'remove clipboard image file');
      }
    }
  }

  private async writeImage(base64: string): Promise<void> {
    let source: image.ImageSource | undefined;
    let bitmap: image.PixelMap | undefined;

    try {
      try {
        const bytes = await new util.Base64Helper().decode(base64);
        this.assertActive();
        if (bytes.byteLength === 0) throw new Error('Empty image data.');

        source = image.createImageSource(bytes.buffer);
        bitmap = await source.createPixelMap();
      } catch (error) {
        if (error instanceof ExpoModuleError) throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
        throw new ExpoModuleError('ERR_INVALID_IMAGE', 'The provided base64 string is not a decodable image.', error);
      }

      this.assertActive();
      await this.board.setData(pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, bitmap));
    } finally {
      if (bitmap !== undefined) {
        const decoded = bitmap;
        await this.cleanup(async (): Promise<void> => decoded.release(), 'release copied PixelMap');
      }
      if (source !== undefined) {
        const decoder = source;
        await this.cleanup(async (): Promise<void> => decoder.release(), 'release image decoder');
      }
    }
  }

  private async withPasteData<T>(types: string[], empty: T, read: (data: pasteboard.PasteData) => Promise<T>): Promise<T> {
    if (!types.some((type: string): boolean => this.board.hasDataType(type))) return empty;

    if (this.context.permissionStatus(READ_PERMISSION) !== ExpoPermissionStatus.GRANTED) {
      if (this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
        throw new ExpoModuleError('ERR_NO_PERMISSION', 'Clipboard read permission can only be requested in the foreground.');
      }

      const result = await this.context.requestPermissions([READ_PERMISSION]);
      this.assertActive();
      if (result.authResults[0] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        throw new ExpoModuleError('ERR_NO_PERMISSION', 'Clipboard read permission was not granted.');
      }
    }

    const data = await this.board.getData();
    try {
      data.pasteStart();
      this.assertActive();
      return await read(data);
    } finally {
      await this.cleanup(async (): Promise<void> => data.pasteComplete(), 'complete clipboard paste');
    }
  }

  // HarmonyOS rejects overlapping copy/paste operations. A failed task must not poison the queue.
  private perform<T>(operation: () => Promise<T>, code: string = 'ERR_CLIPBOARD'): Promise<T> {
    const next = this.pending.then(async (): Promise<T> => {
      this.assertActive();
      try {
        const result = await operation();
        this.assertActive();
        return result;
      } catch (error) {
        if (error instanceof ExpoModuleError) throw new ExpoModuleError(error.code, error.message, error.cause, error.path);

        // Expo's bridge expects string error codes; retain the system's numeric code in the message.
        const cause = error as BusinessError;
        throw new ExpoModuleError(
          cause.code === PERMISSION_DENIED ? 'ERR_NO_PERMISSION' : code,
          `HarmonyOS clipboard operation failed (${cause.code}): ${cause.message}`,
          error,
        );
      }
    });

    this.pending = next.then(
      (): void => {},
      (): void => {},
    );

    return next;
  }

  private assertActive(): void {
    if (this.destroyed || !this.context.isValid)
      throw new ExpoModuleError('ERR_CLIPBOARD_DESTROYED', 'The Expo Clipboard runtime has been destroyed.');
  }

  private startObservation(): void {
    if (this.destroyed || !this.listening || this.observing || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) return;

    this.board.on('update', this.changed);
    this.observing = true;
  }

  private stopObservation(): void {
    if (!this.observing) return;

    try {
      this.board.off('update', this.changed);
      this.observing = false;
    } catch (error) {
      this.warn('unsubscribe from clipboard updates', error);
    }
  }

  private destroy(): void {
    this.destroyed = true;
    this.listening = false;
    this.stopObservation();
  }

  private async cleanup(action: () => Promise<void>, description: string): Promise<void> {
    try {
      await action();
    } catch (error) {
      this.warn(description, error);
    }
  }

  private warn(action: string, error: Object): void {
    if (this.context.isValid) this.context.logger.warn(`Unable to ${action}: ${(error as BusinessError).message}`);
  }
}

async function plainTextFromHtml(html: string): Promise<string> {
  return html.length === 0 ? '' : (await StyledString.fromHtml(html)).getString();
}

function htmlFromPlainText(text: string): string {
  if (text.length === 0) return '';

  // StyledString.toHtml does not escape text; paragraphs also work before API 20's <br> support.
  const escaped = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  return `<p>${escaped.replace(/\r\n|\r|\n/g, '</p><p>')}</p>`;
}

async function readEntry(data: pasteboard.PasteData, type: string): Promise<pasteboard.ValueType | undefined> {
  for (let index = 0; index < data.getRecordCount(); index += 1) {
    const record = data.getRecord(index);
    if (record.getValidTypes([type]).length > 0) return await record.getData(type);
  }

  return undefined;
}

async function readImageFile(fd: number): Promise<Uint8Array> {
  const size = (await fileIo.stat(fd)).size;
  if (!Number.isSafeInteger(size) || size <= 0) throw new ExpoModuleError('ERR_PASTE_FAILURE', 'The encoded clipboard image is empty or too large.');

  const bytes = new Uint8Array(size);
  const chunk = new ArrayBuffer(Math.min(FILE_READ_CHUNK_SIZE, size));
  fileIo.lseek(fd, 0, fileIo.WhenceType.SEEK_SET);
  let offset = 0;

  while (offset < size) {
    const count = await fileIo.read(fd, chunk, { length: Math.min(chunk.byteLength, size - offset) });
    if (count <= 0) throw new ExpoModuleError('ERR_PASTE_FAILURE', 'The encoded clipboard image could not be read completely.');
    bytes.set(new Uint8Array(chunk, 0, count), offset);
    offset += count;
  }

  return bytes;
}
