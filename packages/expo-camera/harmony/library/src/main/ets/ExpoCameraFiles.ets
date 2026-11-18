/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { ExpoCameraError } from './ExpoCameraError';

export async function writeBuffer(path: string, buffer: ArrayBuffer): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  let offset = 0;

  try {
    while (offset < buffer.byteLength) {
      const chunk = offset === 0 ? buffer : buffer.slice(offset);
      const count = await fs.write(file.fd, chunk);
      if (count <= 0) throw new ExpoCameraError('ERR_CAMERA_FILE_WRITE', `Unable to write '${path}'.`);

      offset += count;
    }
  } finally {
    await fs.close(file.fd);
  }
}

export async function readBuffer(path: string): Promise<ArrayBuffer> {
  const stat = await fs.stat(path);
  const buffer = new ArrayBuffer(stat.size);
  const bytes = new Uint8Array(buffer);

  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  let offset: number = 0;

  try {
    while (offset < buffer.byteLength) {
      const chunk = offset === 0 ? buffer : new ArrayBuffer(buffer.byteLength - offset);
      const count = await fs.read(file.fd, chunk);
      if (count <= 0) break;

      if (offset !== 0) bytes.set(new Uint8Array(chunk, 0, count), offset);
      offset += count;
    }
  } finally {
    await fs.close(file.fd);
  }

  if (offset !== buffer.byteLength) {
    throw new ExpoCameraError('ERR_CAMERA_FILE_READ', `Unable to read '${path}'.`);
  }

  return buffer;
}

export async function ensureDirectory(path: string): Promise<void> {
  try {
    await fs.mkdir(path, true);
  } catch (error) {
    const exists = await fs.stat(path).then((stat: fs.Stat): boolean => stat.isDirectory(), (): boolean => false);
    if (!exists) {
      throw new ExpoCameraError('ERR_CAMERA_FILE_WRITE', `Unable to create '${path}'.`, error as Object);
    }
  }
}

export function uniquePath(dir: string, prefix: string, extension: string): string {
  return `${dir}/${prefix}-${util.generateRandomUUID()}.${extension}`;
}

export async function packPicture(path: string, pixel: image.PixelMap, options: image.PackingOption): Promise<void> {
  const packer = image.createImagePacker();

  try {
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      await packer.packToFile(pixel, file.fd, options);
    } finally {
      await fs.close(file.fd);
    }
  } finally {
    await packer.release().catch((): void => {});
  }
}
