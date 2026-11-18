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
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { ExpoImageRecord } from './ContactsRecords';
import { ExpoModuleContext, ExpoModuleError, fileUriFromPath } from '@expo-harmony/expo-modules-core';
import { ContactsNativeError, ExpoContactsError } from './ContactsError';

const CACHE_DIRECTORY: string = 'expo-contacts';
export const CONTACT_THUMBNAIL_MAX_DIMENSION: number = 256;
const FILE_EXISTS: number = 13900015;
const FILE_MISSING: number = 13900002;
const IMAGE_DATA_ABNORMAL: number = 62980101;
const IMAGE_DATA_UNSUPPORTED: number = 62980103;
const IMAGE_FORMAT_UNKNOWN: number = 62980113;
const IMAGE_DECODE_FAILED: number = 62980116;
const IMAGE_HEADER_DECODE_FAILED: number = 62980122;

interface EncodedPortrait {
  bytes: ArrayBuffer;
  width: number;
  height: number;
}

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

export async function writeCacheFile(
  context: ExpoModuleContext,
  extension: string,
  bytes: ArrayBuffer,
  validate?: () => void,
  key?: string,
): Promise<string> {
  const directory = `${context.cachePath}/${CACHE_DIRECTORY}`;
  context.assertFileAccess(directory, 'write');

  try {
    await fileIo.mkdir(directory, true);
  } catch (error) {
    if ((error as BusinessError).code !== FILE_EXISTS || !(await fileIo.stat(directory)).isDirectory()) {
      throw new ContactsNativeError(error as Object);
    }
  }

  const path = `${directory}/${util.generateRandomUUID()}.${extension}`;
  const destination = key === undefined ? path : `${directory}/${key}.${extension}`;
  context.assertFileAccess(path, 'write');
  context.assertFileAccess(destination, 'write');

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
    if (destination !== path) await fileIo.rename(path, destination);
  } catch (error) {
    try {
      await fileIo.unlink(path);
    } catch (failure) {
      console.warn('[expo-contacts] Unable to remove an incomplete cache file.', failure);
    }

    if (error instanceof ExpoContactsError) {
      throw new ExpoContactsError(error.code, error.message, error.cause ?? error);
    }
    if (error instanceof ExpoModuleError) {
      throw new ExpoModuleError(error.code, error.message, error.cause ?? error, error.path);
    }

    throw new ExpoContactsError('ERR_CONTACTS_FILE_WRITE', 'Unable to write the contacts cache file.', error as Object);
  }

  return fileUriFromPath(destination);
}

async function encodePortrait(context: ExpoModuleContext, uri: string, maxDimension?: number): Promise<EncodedPortrait | undefined> {
  context.assertActive();

  // Contacts Kit supplies this authorized URI; it is not a JS-provided file path.
  let file: fileIo.File;

  try {
    file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
  } catch (error) {
    if ((error as BusinessError).code === FILE_MISSING) return undefined;

    throw new ExpoContactsError('ERR_CONTACTS_FILE_READ', 'Unable to open the contact portrait.', error as Object);
  }

  let source: image.ImageSource | undefined;
  let packer: image.ImagePacker | undefined;
  let pixels: image.PixelMap | undefined;

  return await withCleanup(async (): Promise<EncodedPortrait | undefined> => {
    try {
      source = image.createImageSource(file.fd);
      const size = (await source.getImageInfo()).size;

      const ratio = maxDimension === undefined ? 1 : Math.min(1, maxDimension / Math.max(size.width, size.height));
      const width = Math.max(1, Math.round(size.width * ratio));
      const height = Math.max(1, Math.round(size.height * ratio));

      const options: image.PackingOption = { format: 'image/jpeg', quality: 100 };
      packer = image.createImagePacker();

      if (maxDimension === undefined || ratio === 1) return { bytes: await packer.packToData(source, options), width, height };

      pixels = await source.createPixelMap({ desiredSize: { width, height } });

      return { bytes: await packer.packToData(pixels, options), width, height };
    } catch (error) {
      const code = (error as BusinessError).code;

      if ([IMAGE_DATA_ABNORMAL, IMAGE_DATA_UNSUPPORTED, IMAGE_FORMAT_UNKNOWN, IMAGE_DECODE_FAILED, IMAGE_HEADER_DECODE_FAILED].includes(code)) {
        return undefined;
      }

      throw new ExpoContactsError('ERR_CONTACTS_FILE', 'The contact file operation failed.', error as Object);
    }
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

export async function cachePortrait(context: ExpoModuleContext, uri: string, maxDimension?: number): Promise<ExpoImageRecord | undefined> {
  const portrait = await encodePortrait(context, uri, maxDimension);
  context.assertActive();
  if (portrait === undefined) return undefined;

  // Key the file by its contents so a changed portrait produces a different URI.
  const hash = cryptoFramework.createMd('SHA256');
  await hash.update({ data: new Uint8Array(portrait.bytes) });
  const digest = (await hash.digest()).data;
  const key = Array.from(digest).map((value: number): string => value.toString(16).padStart(2, '0')).join('');

  const result = new ExpoImageRecord();
  result.uri = await writeCacheFile(context, 'jpg', portrait.bytes, (): void => context.assertActive(), key);
  result.width = portrait.width;
  result.height = portrait.height;

  return result;
}

export async function encodePortraitBase64(context: ExpoModuleContext, uri: string): Promise<string> {
  const portrait = await encodePortrait(context, uri);
  context.assertActive();

  return portrait === undefined ? '' : new util.Base64Helper().encodeToStringSync(new Uint8Array(portrait.bytes));
}

export async function withContactImage<Result>(
  context: ExpoModuleContext,
  uri: string,
  operation: (pixels: image.PixelMap) => Promise<Result>,
): Promise<Result> {
  const path = context.fileSourceForRead(uri);
  const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);

  let source: image.ImageSource | undefined;
  let pixels: image.PixelMap | undefined;

  return await withCleanup(async (): Promise<Result> => {
    context.readPathForDescriptor(path, file);
    if (!(await fileIo.stat(file.fd)).isFile()) {
      throw new ExpoContactsError('ERR_CONTACTS_FILE_READ', 'The contact image must be a regular file.');
    }

    source = image.createImageSource(file.fd);
    pixels = await source.createPixelMap();

    context.assertActive();
    return await operation(pixels);
  }, [
    async (): Promise<void> => { await pixels?.release(); },
    async (): Promise<void> => { await source?.release(); },
    async (): Promise<void> => { await fileIo.close(file); },
  ]);
}
