/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoModuleError, ExpoSharedObject, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { dataSharePredicates } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ASSET_FETCH_COLUMNS, memberNumber } from './MediaLibraryAssets';
import { optionalRecord } from './MediaLibraryQuery';
import { MediaLibraryRepository } from './MediaLibraryRepository';

export enum AssetField {
  CREATION_TIME = 'creationTime',
  MODIFICATION_TIME = 'modificationTime',
  MEDIA_TYPE = 'mediaType',
  WIDTH = 'width',
  HEIGHT = 'height',
  DURATION = 'duration',
  IS_FAVORITE = 'isFavorite',
}

export enum QueryOperator {
  EQ = 'eq', WITHIN = 'within', GT = 'gt', GTE = 'gte', LT = 'lt', LTE = 'lte',
}

const QUERY_FIELDS: AssetField[] = [
  AssetField.CREATION_TIME, AssetField.MODIFICATION_TIME, AssetField.MEDIA_TYPE,
  AssetField.WIDTH, AssetField.HEIGHT, AssetField.DURATION, AssetField.IS_FAVORITE,
];

class ExpoMediaLibraryQueryError extends ExpoModuleError {
  constructor(message: string) {
    super('ERR_MEDIA_LIBRARY_INVALID_QUERY', message);
  }
}

export const QUERY_FIELD = ExpoValueTypes.custom<AssetField>('AssetField', readField, (value: AssetField): ESObject => value);
export const QUERY_VALUE = ExpoValueTypes.custom<string | number | boolean>(
  'media type, integer or boolean',
  (value: ESObject): string | number | boolean => {
    if (typeof value === 'string' || typeof value === 'boolean') return value;
    return readInteger(value);
  },
  (value: string | number | boolean): ESObject => value,
);
export const QUERY_PAGE_SIZE = ExpoValueTypes.custom<number>(
  'non-negative integer',
  (value: ESObject): number => {
    const result = readInteger(value);
    if (result < 0) throw new ExpoMediaLibraryQueryError('Limit and offset must be non-negative.');
    return result;
  },
  (value: number): ESObject => value,
);

export class QuerySort {
  key: AssetField;
  ascending: boolean;

  constructor(key: AssetField, ascending: boolean = true) {
    this.key = key;
    this.ascending = ascending;
  }
}

export const QUERY_SORT = ExpoValueTypes.custom<QuerySort>(
  'SortDescriptor or AssetField',
  (value: ESObject): QuerySort => {
    if (typeof value === 'string') return new QuerySort(readField(value));

    const record = optionalRecord(value);
    if (record === undefined) throw new ExpoMediaLibraryQueryError('A sort descriptor is required.');

    const ascending: ESObject = record['ascending'];
    if (ascending !== undefined && ascending !== null && typeof ascending !== 'boolean') {
      throw new ExpoMediaLibraryQueryError('ascending must be a boolean.');
    }

    return new QuerySort(readField(record['key']), ascending ?? true);
  },
  (value: QuerySort): ESObject => value,
);

class QueryFilter {
  readonly field: AssetField;
  readonly operator: QueryOperator;
  readonly values: number[];

  constructor(field: AssetField, operator: QueryOperator, values: number[]) {
    this.field = field;
    this.operator = operator;
    this.values = values;
  }
}

const MAX_NATIVE_PAGE_SIZE: number = 2147483647;
const PUBLIC_RANGE_PREDICATES_API: number = 23;

export class MediaLibraryNativeQuery extends ExpoSharedObject {
  private filters: QueryFilter[] = [];
  private sorts: QuerySort[] = [];
  private maximum?: number;
  private start: number = 0;
  private albumId?: string;

  private readonly repository: MediaLibraryRepository;

  constructor(context: ExpoModuleContext, repository: MediaLibraryRepository) {
    super(context);
    this.repository = repository;
  }

  filter(field: AssetField, operator: QueryOperator, values: (string | number | boolean)[]): MediaLibraryNativeQuery {
    this.repository.assertActive();

    const numbers: number[] = [];

    for (const value of values) {
      if (field === AssetField.MEDIA_TYPE) {
        // PhotoAccessHelper exposes only images and videos. Other types match nothing.
        if (value === 'image') numbers.push(photoAccessHelper.PhotoType.IMAGE);
        else if (value === 'video') numbers.push(photoAccessHelper.PhotoType.VIDEO);
        else if (value !== 'audio' && value !== 'unknown') {
          throw new ExpoMediaLibraryQueryError('mediaType must be image, video, audio or unknown.');
        }
      } else if (field === AssetField.IS_FAVORITE) {
        if (typeof value !== 'boolean') throw new ExpoMediaLibraryQueryError('isFavorite requires a boolean.');
        numbers.push(value ? 1 : 0);
      } else {
        numbers.push(readInteger(value));
      }
    }

    this.filters.push(new QueryFilter(field, operator, numbers));

    return this;
  }

  limit(value: number): MediaLibraryNativeQuery {
    this.repository.assertActive();
    this.maximum = value;
    return this;
  }

  offset(value: number): MediaLibraryNativeQuery {
    this.repository.assertActive();
    this.start = value;
    return this;
  }

  album(id: string): MediaLibraryNativeQuery {
    this.repository.assertActive();
    this.albumId = id;
    return this;
  }

  orderBy(sort: QuerySort): MediaLibraryNativeQuery {
    this.repository.assertActive();
    this.sorts.push(sort);
    return this;
  }

  execute(metadata: boolean = false): Promise<photoAccessHelper.PhotoAsset[]> {
    // Snapshot at invocation so a later builder call cannot mutate an in-flight query.
    const filters = this.filters.slice();
    const sorts = this.sorts.slice();
    const maximum = this.maximum;
    const start = this.start;
    const albumId = this.albumId;

    return this.repository.read(async (): Promise<photoAccessHelper.PhotoAsset[]> => {
      const album = albumId === undefined ? undefined : await this.repository.requireAlbum(albumId);
      // Validate the album even for limit(0), matching the SDK 56/57 fix.
      if (maximum === 0 || filters.some((filter: QueryFilter): boolean => filter.values.length === 0)) return [];

      const predicates = new dataSharePredicates.DataSharePredicates();
      const localFilters: QueryFilter[] = [];

      for (const filter of filters) {
        // Older Media Library Kit versions rewrite the millisecond column but lose its IN arguments.
        if ((filter.operator === QueryOperator.WITHIN && isTimestamp(filter.field)) ||
          (isRange(filter.operator) && deviceInfo.sdkApiVersion < PUBLIC_RANGE_PREDICATES_API)) localFilters.push(filter);
        else applyFilter(predicates, filter);
      }

      for (const sort of sorts) {
        const column = sortColumn(sort.key);
        if (sort.ascending) predicates.orderByAsc(column);
        else predicates.orderByDesc(column);
      }

      // DataShare expects signed 32-bit pagination parameters.
      const nativePage = localFilters.length === 0 && start <= MAX_NATIVE_PAGE_SIZE &&
        (maximum !== undefined ? maximum <= MAX_NATIVE_PAGE_SIZE : start > 0);
      if (nativePage) predicates.limit(maximum ?? MAX_NATIVE_PAGE_SIZE, start);

      const fetchColumns = metadata ? ASSET_FETCH_COLUMNS : localFilters.map((filter: QueryFilter): string => nativeColumn(filter.field));
      const options: photoAccessHelper.FetchOptions = { fetchColumns, predicates };
      const fetch = album === undefined ? await this.repository.helper.getAssets(options) : await album.getAssets(options);

      try {
        const count = fetch.getCount();
        if (count === 0) return [];

        if (localFilters.length > 0) {
          const assets = await fetch.getAllObjects();
          return assets.filter((asset: photoAccessHelper.PhotoAsset): boolean => localFilters.every((filter: QueryFilter): boolean =>
            matches(memberNumber(asset, nativeColumn(filter.field)), filter)))
            .slice(start, maximum === undefined ? undefined : start + maximum);
        }

        const end = maximum === undefined ? count : Math.min(count, start + maximum);
        if (nativePage || (start === 0 && end === count)) return await fetch.getAllObjects();

        const assets: photoAccessHelper.PhotoAsset[] = [];
        for (let i = start; i < end; i++) assets.push(await fetch.getObjectByPosition(i));

        return assets;
      } finally {
        fetch.close();
      }
    });
  }
}

function readInteger(value: ESObject): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value)) {
    throw new ExpoMediaLibraryQueryError('Expected a finite safe integer.');
  }
  return value;
}

function readField(value: ESObject): AssetField {
  if (typeof value !== 'string' || !QUERY_FIELDS.includes(value as AssetField)) {
    throw new ExpoMediaLibraryQueryError(`Unknown asset field '${value}'.`);
  }
  return value as AssetField;
}

function isTimestamp(field: AssetField): boolean {
  return field === AssetField.CREATION_TIME || field === AssetField.MODIFICATION_TIME;
}

function isRange(operator: QueryOperator): boolean {
  return operator !== QueryOperator.EQ && operator !== QueryOperator.WITHIN;
}

function sortColumn(field: AssetField): photoAccessHelper.PhotoKeys {
  // The public sort keys order the underlying timestamp columns. The _MS aliases are for reads and comparisons.
  if (field === AssetField.CREATION_TIME) return photoAccessHelper.PhotoKeys.DATE_TAKEN;
  if (field === AssetField.MODIFICATION_TIME) return photoAccessHelper.PhotoKeys.DATE_MODIFIED;
  return nativeColumn(field);
}

function nativeColumn(field: AssetField): photoAccessHelper.PhotoKeys {
  switch (field) {
    case AssetField.CREATION_TIME: return photoAccessHelper.PhotoKeys.DATE_TAKEN_MS;
    case AssetField.MODIFICATION_TIME: return photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS;
    case AssetField.MEDIA_TYPE: return photoAccessHelper.PhotoKeys.PHOTO_TYPE;
    case AssetField.WIDTH: return photoAccessHelper.PhotoKeys.WIDTH;
    case AssetField.HEIGHT: return photoAccessHelper.PhotoKeys.HEIGHT;
    case AssetField.DURATION: return photoAccessHelper.PhotoKeys.DURATION;
    case AssetField.IS_FAVORITE: return photoAccessHelper.PhotoKeys.FAVORITE;
  }
}

function applyFilter(predicates: dataSharePredicates.DataSharePredicates, filter: QueryFilter): void {
  const column = nativeColumn(filter.field);
  const value = filter.values[0];
  switch (filter.operator) {
    case QueryOperator.EQ: predicates.equalTo(column, value); break;
    case QueryOperator.WITHIN: predicates.in(column, filter.values); break;
    case QueryOperator.GT: predicates.greaterThan(column, value); break;
    case QueryOperator.GTE: predicates.greaterThanOrEqualTo(column, value); break;
    case QueryOperator.LT: predicates.lessThan(column, value); break;
    case QueryOperator.LTE: predicates.lessThanOrEqualTo(column, value); break;
  }
}

function matches(value: number, filter: QueryFilter): boolean {
  switch (filter.operator) {
    case QueryOperator.EQ: return value === filter.values[0];
    case QueryOperator.WITHIN: return filter.values.includes(value);
    case QueryOperator.GT: return value > filter.values[0];
    case QueryOperator.GTE: return value >= filter.values[0];
    case QueryOperator.LT: return value < filter.values[0];
    case QueryOperator.LTE: return value <= filter.values[0];
  }
}
