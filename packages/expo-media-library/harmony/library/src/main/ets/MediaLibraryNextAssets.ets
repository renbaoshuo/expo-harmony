/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { memberNumber } from './MediaLibraryAssets';

export class AssetShape {
  width: number;
  height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}

/** No file I/O: this is also the contract of Query.exeForMetadata(). */
export class NextAssetMetadata {
  id: string;
  filename: string;
  mediaType: string;
  width: number | null;
  height: number | null;
  duration: number | null;
  creationTime: number | null;
  modificationTime: number | null;
  isFavorite: boolean;

  constructor(asset: photoAccessHelper.PhotoAsset) {
    this.id = asset.uri;
    this.filename = asset.displayName;
    this.mediaType = asset.photoType === photoAccessHelper.PhotoType.IMAGE ? 'image' :
      asset.photoType === photoAccessHelper.PhotoType.VIDEO ? 'video' : 'unknown';

    const width = positiveOrNull(memberNumber(asset, photoAccessHelper.PhotoKeys.WIDTH));
    const height = positiveOrNull(memberNumber(asset, photoAccessHelper.PhotoKeys.HEIGHT));
    const rotated = Math.abs(memberNumber(asset, photoAccessHelper.PhotoKeys.ORIENTATION)) % 180 === 90;
    this.width = rotated ? height : width;
    this.height = rotated ? width : height;
    this.duration = asset.photoType === photoAccessHelper.PhotoType.VIDEO
      ? positiveOrNull(memberNumber(asset, photoAccessHelper.PhotoKeys.DURATION)) : null;

    const creationTime = memberNumber(asset, photoAccessHelper.PhotoKeys.DATE_TAKEN_MS);
    const modificationTime = memberNumber(asset, photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS);
    this.creationTime = creationTime === 0 ? null : creationTime;
    this.modificationTime = modificationTime === 0 ? null : modificationTime;
    const favorite = asset.get(photoAccessHelper.PhotoKeys.FAVORITE);
    this.isFavorite = favorite === true || favorite === 1;
  }
}

export class NextAssetInfo {
  id: string;
  filename: string;
  uri: string;
  mediaType: string;
  width: number;
  height: number;
  duration: number | null;
  creationTime: number | null;
  modificationTime: number | null;
  isFavorite: boolean;

  constructor(metadata: NextAssetMetadata, shape: AssetShape) {
    this.id = metadata.id;
    this.uri = metadata.id;
    this.filename = metadata.filename;
    this.mediaType = metadata.mediaType;
    this.width = shape.width;
    this.height = shape.height;
    this.duration = metadata.duration;
    this.creationTime = metadata.creationTime;
    this.modificationTime = metadata.modificationTime;
    this.isFavorite = metadata.isFavorite;
  }
}

export function storedShape(asset: photoAccessHelper.PhotoAsset): AssetShape | null {
  return displayShape(memberNumber(asset, photoAccessHelper.PhotoKeys.WIDTH), memberNumber(asset, photoAccessHelper.PhotoKeys.HEIGHT),
    memberNumber(asset, photoAccessHelper.PhotoKeys.ORIENTATION));
}

function displayShape(width: number, height: number, orientation: number): AssetShape | null {
  if (width <= 0 || height <= 0 || !Number.isFinite(width) || !Number.isFinite(height)) return null;
  return Math.abs(orientation) % 180 === 90 ? new AssetShape(height, width) : new AssetShape(width, height);
}

function positiveOrNull(value: number): number | null {
  return value > 0 ? value : null;
}

/** Individual getters may inspect a file header when the media store lacks dimensions. */
export async function resolveShape(asset: photoAccessHelper.PhotoAsset): Promise<AssetShape | null> {
  const stored = storedShape(asset);
  if (stored !== null) return stored;

  const isImage = asset.photoType === photoAccessHelper.PhotoType.IMAGE;
  const canExtractVideo = asset.photoType === photoAccessHelper.PhotoType.VIDEO && canIUse('SystemCapability.Multimedia.Media.AVMetadataExtractor');
  if (!isImage && !canExtractVideo) return null;

  let file: fileIo.File | undefined;
  let source: image.ImageSource | undefined;
  let extractor: media.AVMetadataExtractor | undefined;

  try {
    file = await fileIo.open(asset.uri, fileIo.OpenMode.READ_ONLY);
    if (isImage) {
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      return displayShape(info.size.width, info.size.height, memberNumber(asset, photoAccessHelper.PhotoKeys.ORIENTATION));
    }

    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: file.fd, offset: 0, length: (await fileIo.stat(file.fd)).size };
    const info = await extractor.fetchMetadata();
    return displayShape(Number(info.videoWidth), Number(info.videoHeight), Number(info.videoOrientation ?? 0));
  } catch (_) {
    return null;
  } finally {
    try { await source?.release(); } catch (_) {}
    try { await extractor?.release(); } catch (_) {}
    if (file !== undefined) {
      try { await fileIo.close(file.fd); } catch (_) {}
    }
  }
}

export async function requireShape(asset: photoAccessHelper.PhotoAsset): Promise<AssetShape> {
  const shape = await resolveShape(asset);
  if (shape === null) throw new ExpoModuleError('ERR_MEDIA_LIBRARY_ASSET_PROPERTY', 'The asset has no available dimensions.');
  return shape;
}
