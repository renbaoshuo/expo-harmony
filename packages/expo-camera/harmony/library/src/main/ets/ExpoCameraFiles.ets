/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { ExpoCameraError } from './ExpoCameraError';

let sequence: number = 0;

export async function writeBuffer(path: string, buffer: ArrayBuffer): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  let offset = 0;

  try {
    while (offset < buffer.byteLength) {
      const chunk = buffer.slice(offset, Math.min(offset + 64 * 1024, buffer.byteLength));
      const count = await fs.write(file.fd, chunk, { offset });
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
      const chunk = new ArrayBuffer(Math.min(64 * 1024, buffer.byteLength - offset));
      const count = await fs.read(file.fd, chunk, { length: chunk.byteLength });
      if (count <= 0) break;
      bytes.set(new Uint8Array(chunk, 0, count), offset);
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
  if (!(await fs.access(path))) await fs.mkdir(path, true);
}

export function uniquePath(dir: string, prefix: string, extension: string, tag?: number): string {
  sequence = (sequence + 1) % 1_000_000;

  return `${dir}/${prefix}-${Date.now()}${tag === undefined ? '' : `-${tag}`}-${sequence}.${extension}`;
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
