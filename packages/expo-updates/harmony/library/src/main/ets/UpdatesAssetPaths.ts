/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { UpdateAsset, UpdateRecord } from './UpdatesProtocol';

export const domBundleDirectory = 'www.bundle';

export function isSafeFilename(filename: string): boolean {
  return filename.length > 0 && filename !== '.' && filename !== '..' && !/[/\\\0]/.test(filename);
}

export function isSafeAssetFilename(key: string | null, extension: string): boolean {
  return !/[/\\\0]/.test(extension) && (key === null || isSafeFilename(key + extension));
}

export function isAssetPath(directory: string, path: string): boolean {
  const prefix = directory + '/';
  return path.startsWith(prefix) && isSafeFilename(path.slice(prefix.length));
}

export function isUpdateId(id: string): boolean {
  return /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(id);
}

export function assetFileUrl(path: string): string {
  return 'file://' + path.split('/').map(segment => encodeURIComponent(segment)).join('/');
}

export function localAssetFiles(update: UpdateRecord | undefined, embedded: UpdateAsset[] = []): Record<string, string> {
  if (!update) return {};

  const files = new Map<string, string>();

  for (const asset of [...embedded, ...update.assets]) {
    if (asset.key === null) continue;
    const path = update.domAssets?.files.get(asset.key) ?? asset.path;
    if (path) files.set(asset.key, assetFileUrl(path));
  }

  return Object.fromEntries(files);
}
