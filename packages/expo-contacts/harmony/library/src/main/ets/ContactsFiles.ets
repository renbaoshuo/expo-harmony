/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { ExpoImageRecord } from './ContactsRecords';
import { ExpoModuleContext, ExpoModuleError, fileUriFromPath } from '@expo-harmony/expo-modules-core';
import { ExpoContactsError } from './ContactsError';

const CACHE_DIRECTORY: string = 'expo-contacts';
const FILE_EXISTS: number = 13900015;

async function withCleanup<Result>(operation: () => Promise<Result>, releases: (() => Promise<void>)[]): Promise<Result> {
  let failed = false;

  try {
    return await operation();
  } catch (error) {
    failed = true;

    if (error instanceof ExpoModuleError) throw new ExpoContactsError(error.code, error.message, error);

    throw new ExpoContactsError('ERR_CONTACTS_FILE', 'The contact file operation failed.', error as Object);
  } finally {
    let failure: Object | undefined;

    for (const release of releases) {
      try {
        await release();
      } catch (error) {
        if (!failed && failure === undefined) {
          failure = error as Object;
        } else console.warn('[expo-contacts] Additional resource cleanup failure.', error);
      }
    }

    if (failure !== undefined) {
      throw new ExpoContactsError('ERR_CONTACTS_FILE_CLEANUP', 'Unable to release contact file resources.', failure);
    }
  }
}

export async function writeCacheFile(context: ExpoModuleContext, extension: string, bytes: ArrayBuffer, validate?: () => void): Promise<string> {
  const directory = `${context.cachePath}/${CACHE_DIRECTORY}`;
  context.assertFileAccess(directory, 'write');

  try {
    await fileIo.mkdir(directory, true);
  } catch (error) {
    if ((error as BusinessError).code !== FILE_EXISTS || !(await fileIo.stat(directory)).isDirectory()) throw error as Error;
  }

  const path = `${directory}/${util.generateRandomUUID()}.${extension}`;
  context.assertFileAccess(path, 'write');

  const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);

  try {
    await withCleanup(async (): Promise<void> => {
      let written = 0;

      while (written < bytes.byteLength) {
        const count = await fileIo.write(file.fd, bytes.slice(written));
        if (count <= 0) throw new ExpoContactsError('ERR_CONTACTS_FILE_WRITE', 'Unable to finish writing the contacts cache file.');

        written += count;
      }
    }, [
      async (): Promise<void> => {
        await fileIo.close(file);
      },
    ]);
    validate?.();
  } catch (error) {
    try {
      await fileIo.unlink(path);
    } catch (failure) {
      console.warn('[expo-contacts] Unable to remove an incomplete cache file.', failure);
    }

    if (error instanceof ExpoContactsError && error.code === 'ERR_CONTACTS_MISSING_PERMISSION') {
      throw new ExpoContactsError(error.code, error.message, error);
    }

    throw new ExpoContactsError('ERR_CONTACTS_FILE_WRITE', 'Unable to write the contacts cache file.', error as Object);
  }

  return fileUriFromPath(path);
}

export async function cachePortrait(context: ExpoModuleContext, uri: string, maxDimension?: number): Promise<ExpoImageRecord> {
  context.assertActive();

  // Contacts Kit supplies this authorized URI; it is not a JS-provided file path.
  const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);

  let source: image.ImageSource | undefined;
  let packer: image.ImagePacker | undefined;
  let pixels: image.PixelMap | undefined;

  return await withCleanup(async (): Promise<ExpoImageRecord> => {
    source = image.createImageSource(file.fd);
    const info = await source.getImageInfo();

    packer = image.createImagePacker();
    const ratio = maxDimension === undefined ? 1 : Math.min(1, maxDimension / Math.max(info.size.width, info.size.height));
    const width = Math.max(1, Math.round(info.size.width * ratio));
    const height = Math.max(1, Math.round(info.size.height * ratio));
    let bytes: ArrayBuffer;
    if (maxDimension === undefined) bytes = await packer.packToData(source, { format: 'image/jpeg', quality: 100 });
    else {
      pixels = await source.createPixelMap({ desiredSize: { width, height } });
      bytes = await packer.packToData(pixels, { format: 'image/jpeg', quality: 100 });
    }

    const output = await writeCacheFile(context, 'jpg', bytes);

    const result = new ExpoImageRecord();
    result.uri = output;
    result.width = width;
    result.height = height;

    return result;
  }, [
    async (): Promise<void> => {
      await packer?.release();
    },
    async (): Promise<void> => {
      await pixels?.release();
    },
    async (): Promise<void> => {
      await source?.release();
    },
    async (): Promise<void> => {
      await fileIo.close(file);
    },
  ]);
}

export async function readBase64(context: ExpoModuleContext, uri: string): Promise<string> {
  const source = context.fileSourceForRead(uri);
  const file = await fileIo.open(source, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);

  return await withCleanup(async (): Promise<string> => {
    if (source.startsWith('/') && file.path !== source) context.assertFileAccess(file.path);
    const stat = await fileIo.stat(file.fd);
    if (!stat.isFile()) throw new ExpoContactsError('ERR_CONTACTS_FILE_READ', 'The contact image must be a regular file.');

    const size = stat.size;
    const bytes = new Uint8Array(size);
    let offset = 0;

    while (offset < size) {
      const chunk = new ArrayBuffer(size - offset);
      const count = await fileIo.read(file.fd, chunk);
      if (count <= 0) throw new ExpoContactsError('ERR_CONTACTS_FILE_READ', 'Unable to read the complete contact image.');

      bytes.set(new Uint8Array(chunk, 0, count), offset);
      offset += count;
    }

    return new util.Base64Helper().encodeToStringSync(bytes);
  }, [
    async (): Promise<void> => {
      await fileIo.close(file);
    },
  ]);
}
