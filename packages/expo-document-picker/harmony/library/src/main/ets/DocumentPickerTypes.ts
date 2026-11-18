/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { uniformTypeDescriptor } from '@kit.ArkData';
import type { BusinessError } from '@kit.BasicServicesKit';

const INVALID_PARAMETER = 401;

class DocumentTypeLookupError extends Error {
  readonly code: number;
  readonly cause: BusinessError;

  constructor(cause: BusinessError) {
    super(cause.message);
    this.code = cause.code;
    this.cause = cause;
  }
}

export class UnsupportedDocumentTypeError extends Error {
  constructor(mimeTypes: string[]) {
    super(`HarmonyOS has no filename extensions registered for: ${mimeTypes.join(', ')}.`);
  }
}

export function filenameExtension(name: string): string {
  const dot = name.lastIndexOf('.');

  return dot > 0 && dot < name.length - 1 ? name.slice(dot) : '';
}

export function mimeTypeForName(name: string): string | undefined {
  const suffix = filenameExtension(name).toLowerCase();
  if (suffix.length === 0) return undefined;

  try {
    for (const id of uniformTypeDescriptor.getUniformDataTypesByFilenameExtension(suffix)) {
      const mime = uniformTypeDescriptor.getTypeDescriptor(id)?.mimeTypes[0];
      if (mime) return mime;
    }
  } catch (_) {
    return undefined;
  }

  return undefined;
}

export function documentSuffixes(types: string[]): string[] | undefined {
  const mimes = new Set(types.map((type: string): string => type.trim().toLowerCase()));
  if (mimes.has('*/*')) return undefined;

  const suffixes: Set<string> = new Set<string>();
  for (const mime of mimes) {
    for (const extension of extensionsForMimeType(mime)) {
      suffixes.add(extension);
    }
  }

  if (suffixes.size === 0) throw new UnsupportedDocumentTypeError([...mimes]);

  return Array.from(suffixes);
}

function extensionsForMimeType(mime: string): string[] {
  const wildcard = mime.endsWith('/*');
  const prefix = mime.slice(0, -1);
  let ids: string[];

  try {
    ids = wildcard
      ? Object.values(uniformTypeDescriptor.UniformDataType)
      : uniformTypeDescriptor.getUniformDataTypesByMIMEType(mime);
  } catch (error) {
    const failure = error as BusinessError;
    if (failure.code === INVALID_PARAMETER) return [];

    throw new DocumentTypeLookupError(failure);
  }

  const extensions: string[] = [];

  for (const id of ids) {
    try {
      const descriptor = uniformTypeDescriptor.getTypeDescriptor(id);
      if (!descriptor || (wildcard && !descriptor.mimeTypes.some((type: string): boolean => type.toLowerCase().startsWith(prefix)))) continue;

      for (const extension of descriptor.filenameExtensions) {
        if (extension.startsWith('.') && extension.length > 1 && !/[*,|/\\\s\0]/.test(extension)) extensions.push(extension.toLowerCase());
      }
    } catch (_) {
      // An enum value introduced in a newer SDK may not have a descriptor on this device.
    }
  }

  return extensions;
}
