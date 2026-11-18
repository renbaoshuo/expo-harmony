/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

export const MEDIA_URI_PREFIX: string = `${photoAccessHelper.DefaultChangeUri.DEFAULT_PHOTO_URI}/`;
const GPS_COORDINATE_KEYS: image.PropertyKey[] = [
  image.PropertyKey.GPS_LATITUDE,
  image.PropertyKey.GPS_LATITUDE_REF,
  image.PropertyKey.GPS_LONGITUDE,
  image.PropertyKey.GPS_LONGITUDE_REF,
];

export const ASSET_FETCH_COLUMNS: string[] = [
  photoAccessHelper.PhotoKeys.URI,
  photoAccessHelper.PhotoKeys.PHOTO_TYPE,
  photoAccessHelper.PhotoKeys.DISPLAY_NAME,
  photoAccessHelper.PhotoKeys.WIDTH,
  photoAccessHelper.PhotoKeys.HEIGHT,
  photoAccessHelper.PhotoKeys.DATE_ADDED_MS,
  photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS,
  photoAccessHelper.PhotoKeys.DATE_TAKEN_MS,
  photoAccessHelper.PhotoKeys.DURATION,
  photoAccessHelper.PhotoKeys.ORIENTATION,
  photoAccessHelper.PhotoKeys.FAVORITE,
];

export class LocationRecord {
  latitude: number;
  longitude: number;

  constructor(latitude: number, longitude: number) {
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

export class AssetRecord {
  id: string;
  filename: string;
  uri: string;
  mediaType: string;
  width: number;
  height: number;
  creationTime: number;
  modificationTime: number;
  duration: number;
  localUri?: string;
  location?: LocationRecord | null;
  exif?: Record<string, ESObject>;
  isFavorite?: boolean;

  constructor(
    id: string,
    filename: string,
    mediaType: string,
    width: number,
    height: number,
    creationTime: number,
    modificationTime: number,
    duration: number,
  ) {
    this.id = id;
    this.filename = filename;
    this.uri = id;
    this.mediaType = mediaType;
    this.width = width;
    this.height = height;
    this.creationTime = creationTime;
    this.modificationTime = modificationTime;
    this.duration = duration;
  }
}

export class AlbumRecord {
  id: string;
  title: string;
  assetCount: number;
  type: string;

  constructor(album: photoAccessHelper.Album) {
    this.id = album.albumUri;
    this.title = album.albumName;
    this.assetCount = album.count;
    this.type = album.albumType === photoAccessHelper.AlbumType.SYSTEM ? 'smartAlbum' : 'album';
  }
}

export class PagedAssetResult {
  assets: AssetRecord[];
  endCursor: string | null;
  hasNextPage: boolean;
  totalCount: number;

  constructor(assets: AssetRecord[], endCursor: string | null, hasNextPage: boolean, totalCount: number) {
    this.assets = assets;
    this.endCursor = endCursor;
    this.hasNextPage = hasNextPage;
    this.totalCount = totalCount;
  }
}

export class MediaLibraryChangeEvent {
  hasIncrementalChanges: boolean = false;
}

export class NextMediaLibraryChangeEvent extends MediaLibraryChangeEvent {
  insertedAssets?: string[];
  deletedAssets?: string[];
  updatedAssets?: string[];

  constructor(change?: photoAccessHelper.ChangeData) {
    super();

    if (change?.uris === undefined || change.uris.length === 0 ||
      !change.uris.every((uri: string): boolean => uri.startsWith(MEDIA_URI_PREFIX))) return;

    const ids = Array.from(new Set<string>(change.uris));
    switch (change.type) {
      case photoAccessHelper.NotifyType.NOTIFY_ADD: this.insertedAssets = ids; break;
      case photoAccessHelper.NotifyType.NOTIFY_REMOVE: this.deletedAssets = ids; break;
      case photoAccessHelper.NotifyType.NOTIFY_UPDATE: this.updatedAssets = ids; break;
      default: return;
    }

    this.hasIncrementalChanges = true;
  }
}

export async function mapAsset(asset: photoAccessHelper.PhotoAsset, details: boolean, readLocation: boolean = false): Promise<AssetRecord> {
  let width = memberNumber(asset, photoAccessHelper.PhotoKeys.WIDTH);
  let height = memberNumber(asset, photoAccessHelper.PhotoKeys.HEIGHT);
  const orientation = memberNumber(asset, photoAccessHelper.PhotoKeys.ORIENTATION);

  if (Math.abs(orientation) % 180 === 90) {
    const previous = width;
    width = height;
    height = previous;
  }

  const record = new AssetRecord(
    asset.uri,
    asset.displayName,
    assetMediaType(asset),
    width,
    height,
    effectiveCreationTime(asset),
    memberNumber(asset, photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS),
    memberNumber(asset, photoAccessHelper.PhotoKeys.DURATION) / 1000,
  );

  if (details) {
    record.localUri = asset.uri;
    record.location = null;
    record.isFavorite = memberBoolean(asset, photoAccessHelper.PhotoKeys.FAVORITE);

    const keys = exifKeys(readLocation);
    const props = await readImageProperties(asset, keys);
    if (props !== undefined) {
      record.exif = decodeExif(keys, props);
      if (readLocation) record.location = decodeLocation(props);
    }
  }

  return record;
}

function assetMediaType(asset: photoAccessHelper.PhotoAsset): string {
  if (asset.photoType === photoAccessHelper.PhotoType.IMAGE) return 'photo';
  if (asset.photoType === photoAccessHelper.PhotoType.VIDEO) return 'video';
  return 'unknown';
}

export async function readAssetExif(asset: photoAccessHelper.PhotoAsset, readLocation: boolean): Promise<Record<string, ESObject>> {
  const keys = exifKeys(readLocation);
  const props = await readImageProperties(asset, keys);
  return props === undefined ? {} : decodeExif(keys, props);
}

export async function readAssetLocation(asset: photoAccessHelper.PhotoAsset): Promise<LocationRecord | null> {
  const props = await readImageProperties(asset, GPS_COORDINATE_KEYS);
  return props === undefined ? null : decodeLocation(props);
}

function exifKeys(readLocation: boolean): image.PropertyKey[] {
  const keys = Object.values(image.PropertyKey);
  return readLocation ? keys : keys.filter((key: image.PropertyKey): boolean => !key.startsWith('GPS'));
}

async function readImageProperties(
  asset: photoAccessHelper.PhotoAsset,
  keys: image.PropertyKey[],
): Promise<Record<image.PropertyKey, string | null> | undefined> {
  if (asset.photoType !== photoAccessHelper.PhotoType.IMAGE) return undefined;

  let file: fileIo.File | undefined;
  let source: image.ImageSource | undefined;

  try {
    file = await fileIo.open(asset.uri, fileIo.OpenMode.READ_ONLY);
    source = image.createImageSource(file.fd);

    return (await source.getImageProperties(keys)) ?? undefined;
  } catch (_) {
    return undefined;
  } finally {
    if (source !== undefined) {
      try {
        await source.release();
      } catch (_) {}
    }

    if (file !== undefined) {
      try {
        await fileIo.close(file.fd);
      } catch (_) {}
    }
  }
}

function decodeExif(keys: image.PropertyKey[], props: Record<image.PropertyKey, string | null>): Record<string, ESObject> {
  const exif: Record<string, ESObject> = {};
  keys.forEach((key: image.PropertyKey): void => {
    const value = props[key];
    if (value !== undefined && value !== null) exif[key] = decodedExifValue(key, value);
  });

  return exif;
}

function decodeLocation(props: Record<image.PropertyKey, string | null>): LocationRecord | null {
  const lat = coordinate(props[image.PropertyKey.GPS_LATITUDE], props[image.PropertyKey.GPS_LATITUDE_REF], true);
  const lon = coordinate(props[image.PropertyKey.GPS_LONGITUDE], props[image.PropertyKey.GPS_LONGITUDE_REF], false);
  return lat === undefined || lon === undefined ? null : new LocationRecord(lat, lon);
}

function decodedExifValue(key: image.PropertyKey, value: string): ESObject {
  if (
    key === image.PropertyKey.ORIENTATION ||
    key === image.PropertyKey.IMAGE_LENGTH ||
    key === image.PropertyKey.IMAGE_WIDTH ||
    key === image.PropertyKey.ISO_SPEED_RATINGS ||
    key === image.PropertyKey.FLASH
  ) {
    const number = Number(value);
    return Number.isInteger(number) && value.trim().length > 0 ? number : value;
  }

  if (
    key === image.PropertyKey.EXPOSURE_TIME ||
    key === image.PropertyKey.F_NUMBER ||
    key === image.PropertyKey.FOCAL_LENGTH ||
    key === image.PropertyKey.GPS_ALTITUDE
  ) {
    return rationalNumber(value) ?? value;
  }

  return value;
}

export function memberNumber(asset: photoAccessHelper.PhotoAsset, key: photoAccessHelper.PhotoKeys): number {
  const value = asset.get(key);
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

export function memberBoolean(asset: photoAccessHelper.PhotoAsset, key: photoAccessHelper.PhotoKeys): boolean {
  const value = asset.get(key);
  return value === true || value === 1;
}

export function effectiveCreationTime(asset: photoAccessHelper.PhotoAsset): number {
  const taken = memberNumber(asset, photoAccessHelper.PhotoKeys.DATE_TAKEN_MS);
  return taken !== 0 ? taken : memberNumber(asset, photoAccessHelper.PhotoKeys.DATE_ADDED_MS);
}

function rationalNumber(value: string): number | undefined {
  if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:\s*\/\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+))?$/.test(value.trim())) return undefined;

  const parts = value.trim().split('/');
  const numerator = Number(parts[0]);
  const denominator = parts.length > 1 ? Number(parts[1]) : 1;

  if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator === 0) return undefined;

  return numerator / denominator;
}

function coordinate(value: string | null | undefined, ref: string | null | undefined, latitude: boolean): number | undefined {
  if (value == null || ref == null) return undefined;

  const code = ref.trim().toUpperCase();
  const direction = /^\d{2}$/.test(code) ? String.fromCharCode(Number(code)) : code;
  const positive = latitude ? 'N' : 'E';
  const negative = latitude ? 'S' : 'W';
  const limit = latitude ? 90 : 180;
  if (direction !== positive && direction !== negative) return undefined;

  const parts = value.split(',').map((part: string): number | undefined => rationalNumber(part));
  if (parts.length !== 3 || parts.some((part: number | undefined): boolean => part === undefined)) return undefined;

  const degrees = (parts[0] ?? 0) + (parts[1] ?? 0) / 60 + (parts[2] ?? 0) / 3600;

  if (
    (parts[0] as number) < 0 ||
    (parts[1] as number) < 0 ||
    (parts[1] as number) >= 60 ||
    (parts[2] as number) < 0 ||
    (parts[2] as number) >= 60 ||
    degrees > limit
  )
    return undefined;

  return direction === negative ? -degrees : degrees;
}
