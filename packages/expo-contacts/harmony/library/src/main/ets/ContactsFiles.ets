import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { ExpoImageRecord } from './ContactsRecords';
import { ExpoModuleContext, ExpoModuleError, fileUriFromPath } from '@expo-harmony/expo-modules-core';
import { ExpoContactsError } from './ContactsError';

const CACHE_DIRECTORY: string = 'expo-contacts';

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

export async function writeCacheFile(context: ExpoModuleContext, extension: string, bytes: ArrayBuffer): Promise<string> {
  const directory = `${context.cachePath}/${CACHE_DIRECTORY}`;
  context.assertFileAccess(directory, 'write');

  if (!(await fileIo.access(directory))) await fileIo.mkdir(directory, true);

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
  } catch (error) {
    try {
      await fileIo.unlink(path);
    } catch (failure) {
      console.warn('[expo-contacts] Unable to remove an incomplete cache file.', failure);
    }

    throw new ExpoContactsError('ERR_CONTACTS_FILE_WRITE', 'Unable to write the contacts cache file.', error as Object);
  }

  return fileUriFromPath(path);
}

export async function cachePortrait(context: ExpoModuleContext, uri: string): Promise<ExpoImageRecord> {
  context.assertActive();

  // This URI comes from Contacts Kit under the contacts read grant, never from JS input.
  const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
  let source: image.ImageSource | undefined;
  let packer: image.ImagePacker | undefined;

  return await withCleanup(async (): Promise<ExpoImageRecord> => {
    source = image.createImageSource(file.fd);
    const info = await source.getImageInfo();

    packer = image.createImagePacker();
    const bytes = await packer.packToData(source, { format: 'image/jpeg', quality: 100 });

    const result = new ExpoImageRecord();
    result.uri = await writeCacheFile(context, 'jpg', bytes);
    result.width = info.size.width;
    result.height = info.size.height;

    return result;
  }, [
    async (): Promise<void> => {
      await packer?.release();
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
  const path = context.filePathForRead(uri);
  const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);

  return await withCleanup(async (): Promise<string> => {
    const size = (await fileIo.stat(file.fd)).size;
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
