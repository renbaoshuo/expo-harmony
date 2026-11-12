/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoModuleError, ExpoSharedRef, fileUriFromPath } from '@expo-harmony/expo-modules-core';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

import { ImageFormat, SaveOptions } from './ImageManipulatorArguments';
import { releasePixelMap } from './ImageManipulatorPixels';

const READ_BUFFER_SIZE: number = 64 * 1024;

export interface ImageResult {
  uri: string;
  width: number;
  height: number;
  base64: string | null;
}

export class ImageRef extends ExpoSharedRef<image.PixelMap> {
  private released: boolean = false;
  private saves: number = 0;
  private tail: Promise<void> = Promise.resolve();

  constructor(context: ExpoModuleContext, pixel: image.PixelMap) {
    super(context, 'image', pixel);
  }

  save(options: SaveOptions): Promise<ImageResult> {
    this.context.assertActive();
    if (this.released) throw new ExpoModuleError('ERR_SHARED_OBJECT_RELEASED', 'The image has already been released.');
    if (options.compress < 0 || options.compress > 1) {
      throw new ExpoModuleError('ERR_IMAGE_INVALID_ARGUMENT', 'Compression must be between 0 and 1.');
    }

    // Keep the bitmap alive until every queued save finishes, even after release().
    this.saves += 1;
    const result = this.tail
      .then((): Promise<ImageResult> => this.write(options))
      .finally((): void => {
        this.saves -= 1;
        if (this.released && this.saves === 0) releasePixelMap(this.value);
      });

    this.tail = result.then(
      (): void => {},
      (): void => {},
    );

    return result;
  }

  override getAdditionalMemoryPressure(): number {
    return this.value.getPixelBytesNumber();
  }

  override sharedObjectWillRelease(): void {
    if (this.released) return;

    this.released = true;
    if (this.saves === 0) releasePixelMap(this.value);
  }

  private async write(options: SaveOptions): Promise<ImageResult> {
    this.context.assertActive();

    const format = options.format === ImageFormat.JPG ? ImageFormat.JPEG : options.format;
    const extension = format === ImageFormat.JPEG ? 'jpg' : format;
    const directory = `${this.context.cachePath}/ImageManipulator`;
    let path: string | undefined;
    let file: fileIo.File | undefined;
    let created: boolean = false;
    let saved: boolean = false;

    try {
      const size = this.value.getImageInfoSync().size;
      const mimeType = `image/${format}`;
      const packer = image.createImagePacker();

      try {
        if (!packer.supportedFormats.includes(mimeType)) {
          throw new ExpoModuleError('ERR_IMAGE_UNSUPPORTED_FORMAT', `The device does not support encoding ${mimeType} images.`);
        }

        path = `${directory}/${util.generateRandomUUID(true)}.${extension}`;
        try {
          await fileIo.mkdir(directory, true);
        } catch (error) {
          if (!(await fileIo.stat(directory)).isDirectory()) {
            throw new ExpoModuleError('ERR_IMAGE_WRITE_FAILED', 'Could not create the image cache directory.', error as Object);
          }
        }

        this.context.assertActive();

        file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        created = true;

        this.context.assertActive();

        const packing: image.PackingOption = { format: mimeType, quality: Math.trunc(options.compress * 100) };
        // packToFile avoids packToData's default 25 MiB output limit.
        await packer.packToFile(this.value, file.fd, packing);
      } finally {
        try {
          await packer.release();
        } catch (error) {
          console.warn(`ImageManipulator could not release its encoder: ${String(error)}`);
        }
      }

      this.context.assertActive();

      if (options.base64) fileIo.lseek(file.fd, 0, fileIo.WhenceType.SEEK_SET);
      const base64 = options.base64 ? await this.readBase64(file) : null;

      await fileIo.close(file);
      file = undefined;

      this.context.assertActive();
      const result: ImageResult = { uri: fileUriFromPath(path), width: size.width, height: size.height, base64 };
      saved = true;

      return result;
    } catch (error) {
      if (error instanceof ExpoModuleError) throw error;
      throw new ExpoModuleError('ERR_IMAGE_WRITE_FAILED', 'Writing image data to the file has failed.', error as Object);
    } finally {
      if (file !== undefined) {
        try {
          await fileIo.close(file);
        } catch (error) {
          console.warn(`ImageManipulator could not close its output: ${String(error)}`);
        }
      }

      if (created && !saved && path !== undefined) {
        try {
          await fileIo.unlink(path);
        } catch (error) {
          console.warn(`ImageManipulator could not remove its incomplete output: ${String(error)}`);
        }
      }
    }
  }

  private async readBase64(file: fileIo.File): Promise<string> {
    const data = new Uint8Array((await fileIo.stat(file.fd)).size);
    const buffer = new ArrayBuffer(Math.min(data.byteLength, READ_BUFFER_SIZE));
    let offset = 0;

    while (offset < data.byteLength) {
      this.context.assertActive();

      const count = await fileIo.read(file.fd, buffer, { length: Math.min(buffer.byteLength, data.byteLength - offset) });
      if (count <= 0) throw new Error('The saved image ended before all bytes could be read.');

      data.set(new Uint8Array(buffer, 0, count), offset);
      offset += count;
    }

    return new util.Base64Helper().encodeToString(data);
  }
}
