/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { util } from '@kit.ArkTS';
import { isRnohRawfileResourceUri, rawResourcePathFromUri } from '@expo-harmony/expo-modules-core';

export enum ImageLoaderSourceType {
  HTTP,
  DATA,
  RAW_RESOURCE,
  FILE,
}

export class ImageLoaderSource {
  readonly type: ImageLoaderSourceType;
  readonly value: string;
  readonly fallback?: string;

  constructor(type: ImageLoaderSourceType, value: string, fallback?: string) {
    this.type = type;
    this.value = value;
    this.fallback = fallback;
  }
}

export function resolveImageLoaderSource(url: string): ImageLoaderSource {
  if (url.length === 0 || url.includes('\0')) throw new Error('The image source is empty or contains a null character.');

  if (/^https?:\/\//i.test(url)) return new ImageLoaderSource(ImageLoaderSourceType.HTTP, url);
  if (/^data:/i.test(url)) return new ImageLoaderSource(ImageLoaderSourceType.DATA, url);
  if (url.startsWith('/') || /^file:\/\//i.test(url)) return new ImageLoaderSource(ImageLoaderSourceType.FILE, url);
  if (isRnohRawfileResourceUri(url)) {
    return new ImageLoaderSource(ImageLoaderSourceType.RAW_RESOURCE, rawResourcePathFromUri(url));
  }

  const scheme = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(url);
  if (scheme !== null && !/^(?:asset|rawfile):\/\//i.test(url)) throw new Error('The image URI scheme is unsupported.');

  if (!/^asset:\/\//i.test(url)) {
    return new ImageLoaderSource(ImageLoaderSourceType.RAW_RESOURCE, rawResourcePathFromUri(url, true));
  }

  // RNOH can emit either literal or URL-encoded asset names.
  let path: string;
  try {
    path = rawResourcePathFromUri(url);
  } catch (_) {
    return new ImageLoaderSource(ImageLoaderSourceType.RAW_RESOURCE, rawResourcePathFromUri(url, true));
  }

  let fallback: string | undefined;
  try {
    const decoded = rawResourcePathFromUri(url, true);
    if (decoded !== path) fallback = decoded;
  } catch (_) {}

  return new ImageLoaderSource(ImageLoaderSourceType.RAW_RESOURCE, path, fallback);
}

export async function decodeImageDataURL(url: string): Promise<ArrayBuffer> {
  const comma = url.indexOf(',');
  if (comma < 0 || !/^data:image\/[a-z0-9!#$%&'*+.^_`{|}~-]+(?:;[^,]*)?;base64$/i.test(url.slice(0, comma))) {
    throw new Error('Expected a base64-encoded image data URI.');
  }

  let encoded = url.slice(comma + 1).replace(/\s/g, '');
  const remainder = encoded.length % 4;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded) || remainder === 1 || (remainder !== 0 && encoded.endsWith('='))) {
    throw new Error('Invalid base64 image data.');
  }

  // Base64Helper expects complete four-character groups.
  if (remainder !== 0) encoded = encoded.padEnd(encoded.length + 4 - remainder, '=');
  const bytes = await new util.Base64Helper().decode(encoded);

  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}
