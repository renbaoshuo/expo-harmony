/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoPermissionStatus,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { bundleManager, Permissions } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { ContentType, GET_IMAGE_OPTIONS, GET_STRING_OPTIONS, GetImageOptions, ImageFormat, SET_STRING_OPTIONS, StringFormat } from './ClipboardOptions';
import { defineClipboardPasteButton, PasteButtonResult } from './ClipboardPasteButton';

const CLIPBOARD_CHANGED_EVENT: string = 'onClipboardChanged';
const READ_PERMISSION: Permissions = 'ohos.permission.READ_PASTEBOARD';
const PERMISSION_DENIED: number = 201;
const PERMISSION_STATUS_API: number = 20;
const IMAGE_QUALITY_MAX: number = 100;
const FILE_READ_CHUNK_SIZE: number = 64 * 1024;
const HTML_TAG_END = /(?:[^"'<>]|"[^"]*"|'[^']*')*>/.source;
const HTML_MARKUP = new RegExp([
  /<!--[\s\S]*?(?:-->|$)/.source,
  /<(script|style)(?=[\s/>])/.source + HTML_TAG_END + '[\\s\\S]*?(?:</\\1\\s*>|$)',
  /<(?:!doctype|(\/?[a-z][\w:-]*))(?=[\s/>])/.source + HTML_TAG_END,
  '<',
].join('|'), 'gi');

interface ClipboardImage {
  data: string;
  size: image.Size;
}

export class ExpoClipboardModule extends ExpoModule {
  private readonly board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
  private pending: Promise<void> = Promise.resolve();
  private readonly pendingTransfers: Set<Promise<void>> = new Set<Promise<void>>();
  private destroyed: boolean = false;
  private observing: boolean = false;
  private listening: boolean = false;

  private readonly changed = (): void => {
    if (!this.listening || !this.observing || this.destroyed || !this.context.isValid || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) return;

    try {
      const html = this.board.hasDataType(pasteboard.MIMETYPE_TEXT_HTML);

      const types: ContentType[] = [];
      if (html || this.board.hasDataType(pasteboard.MIMETYPE_TEXT_PLAIN)) types.push(ContentType.PlainText);
      if (html) types.push(ContentType.HTML);
      if (this.board.hasDataType(pasteboard.MIMETYPE_PIXELMAP)) types.push(ContentType.Image);
      if (this.board.hasDataType(pasteboard.MIMETYPE_TEXT_URI)) types.push(ContentType.URL);

      const payload: Record<string, ESObject> = { 'contentTypes': types };
      this.sendEvent(CLIPBOARD_CHANGED_EVENT, payload);
    } catch (error) {
      this.warn('inspect clipboard changes', error);
    }
  };

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoClipboard')
      .constant('isPasteButtonAvailable', canIUse('SystemCapability.ArkUI.ArkUI.Full'))
      .view(defineClipboardPasteButton((types: ContentType[], options: GetImageOptions): Promise<PasteButtonResult | undefined> =>
        this.pasteFromButton(types, options)))
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
              let data: pasteboard.PasteData;
              if (format === StringFormat.HTML) {
                const plain = await plainTextFromHtml(text);

                const entries: Record<string, pasteboard.ValueType> = {};
                entries[pasteboard.MIMETYPE_TEXT_HTML] = text;
                entries[pasteboard.MIMETYPE_TEXT_PLAIN] = plain;
                data = pasteboard.createData(entries);
              } else {
                data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
              }

              await this.writePasteData(data);

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
          (base64: string): Promise<void> => this.perform(async (): Promise<void> => this.trackTransfer(this.writeImage(base64)), 'ERR_COPY_FAILURE'),
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
                async (data: pasteboard.PasteData): Promise<string | null> => {
                  const url = await readEntry(data, pasteboard.MIMETYPE_TEXT_URI);
                  return typeof url === 'string' ? url : null;
                },
              ),
          ),
      )
      .asyncFunction(
        'setUrlAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          (url: string): Promise<void> =>
            this.perform(async (): Promise<void> => this.writePasteData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_URI, url))),
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
      .onPrepareForReload(async (): Promise<void> => {
        this.destroy();
        // Finish native transfers and their cleanup without waiting for a permission dialog.
        await Promise.all(Array.from(this.pendingTransfers));
      })
      .onAbilityDestroy((): void => this.destroy())
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

        if (typeof html === 'string') {
          this.assertActive();
          return await plainTextFromHtml(html);
        }

        const uri = await readEntry(data, pasteboard.MIMETYPE_TEXT_URI);
        if (typeof uri !== 'string') return '';

        return format === StringFormat.HTML ? htmlFromPlainText(uri) : uri;
      },
    );
  }

  private async readImage(options: GetImageOptions): Promise<ClipboardImage | null> {
    return this.withPasteData([pasteboard.MIMETYPE_PIXELMAP], null,
      (data: pasteboard.PasteData): Promise<ClipboardImage | null> => this.readImageData(data, options));
  }

  private async readImageData(data: pasteboard.PasteData, options: GetImageOptions): Promise<ClipboardImage | null> {
    const bitmap = (await readEntry(data, pasteboard.MIMETYPE_PIXELMAP)) as image.PixelMap | undefined;
    if (bitmap === undefined || bitmap === null) return null;

    try {
      this.assertActive();

      return await this.encodeImage(bitmap, options);
    } finally {
      await this.cleanup(async (): Promise<void> => bitmap.release(), 'release clipboard PixelMap');
    }
  }

  private async pasteFromButton(types: ContentType[], options: GetImageOptions): Promise<PasteButtonResult | undefined> {
    this.assertActive();
    if (this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) return undefined;

    // Capture the pasteboard at the authorized gesture, before queued operations or permission prompts.
    const payload = await this.trackTransfer(this.readPasteData(async (data: pasteboard.PasteData): Promise<PasteButtonResult | undefined> => {
      if (types.includes(ContentType.Image)) {
        const image = await this.readImageData(data, options);
        if (image !== null) return { type: 'image', data: image.data, size: image.size };
      }

      if (types.includes(ContentType.URL)) {
        const url = await readEntry(data, pasteboard.MIMETYPE_TEXT_URI);
        if (typeof url === 'string') return { type: 'text', text: url };
      }

      if (types.includes(ContentType.HTML)) {
        const html = await readEntry(data, pasteboard.MIMETYPE_TEXT_HTML);
        if (typeof html === 'string') return { type: 'text', text: html };
      }

      if (types.includes(ContentType.PlainText)) {
        const text = await readEntry(data, pasteboard.MIMETYPE_TEXT_PLAIN);
        if (typeof text === 'string') return { type: 'text', text: text };

        const html = await readEntry(data, pasteboard.MIMETYPE_TEXT_HTML);

        if (typeof html === 'string') {
          this.assertActive();
          return { type: 'text', text: await plainTextFromHtml(html) };
        }
      }

      return undefined;
    }));
    this.assertActive();
    return this.context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND ? payload : undefined;
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
      const name = `${this.context.temporaryPath}/expo-clipboard-${util.generateRandomUUID()}`;
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
        const name = path;
        await this.cleanup(async (): Promise<void> => fileIo.unlink(name), 'remove clipboard image file');
      }
    }
  }

  private async writeImage(base64: string): Promise<void> {
    let source: image.ImageSource | undefined;
    let bitmap: image.PixelMap | undefined;

    try {
      try {
        // Android's clipboard image output can include Base64 line breaks.
        const bytes = await new util.Base64Helper().decode(base64.replace(/[\t\n\r ]/g, ''));

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

    // A PasteButton grants temporary access at the OS level, even when the app has no ACL declaration.
    const details = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION).reqPermissionDetails;
    if (!details?.some((permission: bundleManager.ReqPermissionDetail): boolean => permission.name === READ_PERMISSION)) {
      throw new ExpoModuleError('ERR_NO_PERMISSION', 'Clipboard reads require READ_PASTEBOARD in the app manifest. For user-initiated paste, use ClipboardPasteButton.');
    }

    const permission = this.context.permissionStatus(READ_PERMISSION);
    if (permission !== ExpoPermissionStatus.GRANTED) {
      if (permission === ExpoPermissionStatus.INVALID || permission === ExpoPermissionStatus.RESTRICTED
        || (permission === ExpoPermissionStatus.DENIED && deviceInfo.sdkApiVersion >= PERMISSION_STATUS_API
          && this.context.systemPermissionStatus(READ_PERMISSION) === ExpoPermissionStatus.DENIED)) {
        throw new ExpoModuleError('ERR_NO_PERMISSION', 'Clipboard read permission is unavailable or was denied in system settings.');
      }
      if (this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
        throw new ExpoModuleError('ERR_NO_PERMISSION', 'Clipboard read permission can only be requested in the foreground.');
      }

      const result = await this.context.requestPermissions([READ_PERMISSION]);

      this.assertActive();
      if (result.authResults[0] !== ExpoPermissionStatus.GRANTED) {
        throw new ExpoModuleError('ERR_NO_PERMISSION', 'Clipboard read permission was not granted.');
      }

      // The clipboard can change while the system permission prompt is visible.
      if (!types.some((type: string): boolean => this.board.hasDataType(type))) return empty;
    }

    return this.trackTransfer(this.readPasteData(read));
  }

  private async readPasteData<T>(read: (data: pasteboard.PasteData) => Promise<T>): Promise<T> {
    const data = await this.board.getData();

    try {
      data.pasteStart();
      this.assertActive();

      return await read(data);
    } finally {
      await this.cleanup(async (): Promise<void> => data.pasteComplete(), 'complete clipboard paste');
    }
  }

  private writePasteData(data: pasteboard.PasteData): Promise<void> {
    this.assertActive();
    return this.trackTransfer(this.board.setData(data));
  }

  private trackTransfer<T>(transfer: Promise<T>): Promise<T> {
    const complete = transfer.then(
      (): void => {},
      (): void => {},
    );
    this.pendingTransfers.add(complete);
    void complete.then((): void => { this.pendingTransfers.delete(complete); });

    return transfer;
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
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoModuleError('ERR_CLIPBOARD_DESTROYED', 'The Expo Clipboard runtime has been destroyed.');
    }
  }

  private startObservation(): void {
    if (this.destroyed || !this.listening || this.observing || !this.context.isValid || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) return;

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
  // ArkUI loads image sources while parsing HTML. Pass only text and attribute-free layout tags to it.
  const textMarkup = html.replace(
    HTML_MARKUP,
    (tag: string, _nonTextTag?: string, name?: string): string => {
      if (tag === '<') return '&lt;';
      return name !== undefined && /^\/?(?:p|span|div|br|h[1-6]|[ou]l|li)$/i.test(name) ? `<${name}>` : '';
    },
  );
  return textMarkup.length === 0 ? '' : (await StyledString.fromHtml(textMarkup)).getString();
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
  let offset = 0;

  fileIo.lseek(fd, 0, fileIo.WhenceType.SEEK_SET);

  while (offset < size) {
    const count = await fileIo.read(fd, chunk, { length: Math.min(chunk.byteLength, size - offset) });
    if (count <= 0) throw new ExpoModuleError('ERR_PASTE_FAILURE', 'The encoded clipboard image could not be read completely.');

    bytes.set(new Uint8Array(chunk, 0, count), offset);
    offset += count;
  }

  return bytes;
}
