/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { uniformTypeDescriptor } from '@kit.ArkData';
import type { BusinessError } from '@kit.BasicServicesKit';

export class UnsupportedDocumentTypeError extends Error {
  constructor(mimeType: string) {
    super(`HarmonyOS has no filename extensions registered for '${mimeType}'.`);
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
    const id = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(suffix);
    return uniformTypeDescriptor.getTypeDescriptor(id)?.mimeTypes[0];
  } catch (_) {
    return undefined;
  }
}

export function documentSuffixes(types: string[]): string[] | undefined {
  const normalized = types.map((type: string): string => type.trim().toLowerCase());
  if (normalized.includes('*/*')) return undefined;

  const suffixes: Set<string> = new Set<string>();
  for (const mime of normalized) {
    const extensions = extensionsForMimeType(mime);
    if (extensions.length === 0) {
      throw new UnsupportedDocumentTypeError(mime);
    }

    extensions.forEach((extension: string): void => {
      suffixes.add(extension);
    });
  }

  return Array.from(suffixes);
}

function extensionsForMimeType(mime: string): string[] {
  const wildcard = mime.endsWith('/*');
  const prefix = mime.slice(0, -1);
  let ids: string[];

  try {
    ids = wildcard ? Object.values(uniformTypeDescriptor.UniformDataType) : uniformTypeDescriptor.getUniformDataTypesByMIMEType(mime);
  } catch (error) {
    if ((error as BusinessError).code === 401) return [];

    throw error;
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
