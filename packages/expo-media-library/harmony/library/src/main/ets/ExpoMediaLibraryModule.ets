/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { AlbumRecord, AssetRecord, PagedAssetResult } from './MediaLibraryAssets';
import { AlbumQueryOptions, AssetQueryOptions, readAlbumQueryOptions, readAssetQueryOptions, requireString, optionalRecord } from './MediaLibraryQuery';
import { READ_PERMISSION, WRITE_PERMISSION } from './MediaLibraryPermissions';
import { MediaLibraryRepository } from './MediaLibraryRepository';
import { CHANGE_EVENT_NAME, mediaLibraryDefinition } from './MediaLibraryModuleDefinition';

const ASSET_OPTIONS = ExpoValueTypes.custom<AssetQueryOptions>('AssetsOptions', readAssetQueryOptions, (value: AssetQueryOptions): ESObject => value);
const ALBUM_OPTIONS = ExpoValueTypes.custom<AlbumQueryOptions>('AlbumsOptions', readAlbumQueryOptions, (value: AlbumQueryOptions): ESObject => value);
const INFO_OPTIONS = ExpoValueTypes.custom<Record<string, ESObject>>(
  'asset info options',
  (value: ESObject): Record<string, ESObject> => optionalRecord(value) ?? {},
  (value: Record<string, ESObject>): ESObject => value,
);
const IDENTIFIER = ExpoValueTypes.custom<string>(
  'non-empty identifier',
  (value: ESObject, path: string): string => requireString(value, path),
  (value: string): ESObject => value,
);

export class ExpoMediaLibraryModule extends ExpoModule {
  private readonly repository: MediaLibraryRepository;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.repository = new MediaLibraryRepository(context, (event): void => this.sendEvent(CHANGE_EVENT_NAME, event));
  }

  definition(): ExpoModuleDefinition {
    const definition = new ExpoModuleDefinition().name('ExpoMediaLibrary')
      .constant('MediaType', { audio: 'audio', photo: 'photo', video: 'video', unknown: 'unknown', all: 'all' })
      .constant('SortBy', {
        default: 'default', mediaType: 'mediaType', width: 'width', height: 'height',
        creationTime: 'creationTime', modificationTime: 'modificationTime', duration: 'duration',
      })
      .constant('CHANGE_LISTENER_NAME', CHANGE_EVENT_NAME)
      .events([CHANGE_EVENT_NAME]);
    // The upstream availability probe checks whether getAssetsAsync exists.
    if (!canIUse('SystemCapability.FileManagement.PhotoAccessHelper.Core')) return definition;

    return mediaLibraryDefinition(this.repository, 'ExpoMediaLibrary', definition)
      .asyncFunction(
        'getAssetsAsync',
        ExpoFunction.typed1(
          ASSET_OPTIONS,
          (options: AssetQueryOptions): Promise<PagedAssetResult> =>
            this.repository.run(async (): Promise<PagedAssetResult> => {
              this.repository.permissions.ensureGranted([READ_PERMISSION]);

              return await this.repository.getAssets(options);
            }),
        ),
      )
      .asyncFunction(
        'getAssetInfoAsync',
        ExpoFunction.typed2(
          IDENTIFIER,
          INFO_OPTIONS.optional(),
          (id: string, _options?: Record<string, ESObject>): Promise<AssetRecord | null> =>
            this.repository.run(async (): Promise<AssetRecord | null> => {
              this.repository.permissions.ensureGranted([READ_PERMISSION]);

              return await this.repository.getAssetInfo(id);
            }),
        ),
      )
      .asyncFunction(
        'getAlbumsAsync',
        ExpoFunction.typed1(
          ALBUM_OPTIONS,
          (options: AlbumQueryOptions): Promise<AlbumRecord[]> =>
            this.repository.run(async (): Promise<AlbumRecord[]> => {
              this.repository.permissions.ensureGranted([READ_PERMISSION]);

              return await this.repository.getAlbums(options);
            }),
        ),
      )
      .asyncFunction(
        'getAlbumAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          (title: string): Promise<AlbumRecord | null> =>
            this.repository.run(async (): Promise<AlbumRecord | null> => {
              this.repository.permissions.ensureGranted([READ_PERMISSION]);

              return await this.repository.getAlbum(title);
            }),
        ),
      )
      .asyncFunction(
        'createAssetAsync',
        ExpoFunction.typed2(
          IDENTIFIER,
          IDENTIFIER.nullable().optional(),
          (uri: string, album?: string | null): Promise<AssetRecord> =>
            this.repository.run(async (): Promise<AssetRecord> => {
              this.repository.permissions.ensureGranted([READ_PERMISSION, WRITE_PERMISSION]);

              return await this.repository.createAsset(uri, album ?? undefined);
            }),
        ),
      )
      .asyncFunction(
        'saveToLibraryAsync',
        ExpoFunction.typed1(
          IDENTIFIER,
          (uri: string): Promise<void> =>
            this.repository.run(async (): Promise<void> => {
              await this.repository.saveToLibrary(uri);
            }),
        ),
      )
      .asyncFunction(
        'addAssetsToAlbumAsync',
        ExpoFunction.typed3(
          ExpoValueTypes.array(IDENTIFIER),
          IDENTIFIER,
          ExpoValueTypes.boolean().optional(),
          (ids: string[], album: string, copy?: boolean): Promise<boolean> =>
            this.repository.run(async (): Promise<boolean> => {
              this.repository.permissions.ensureGranted([READ_PERMISSION, WRITE_PERMISSION]);

              return await this.repository.addAssetsToAlbum(ids, album, copy ?? true);
            }),
        ),
      )
      .asyncFunction(
        'removeAssetsFromAlbumAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.array(IDENTIFIER),
          IDENTIFIER,
          (ids: string[], album: string): Promise<boolean> =>
            this.repository.run(async (): Promise<boolean> => {
              this.repository.permissions.ensureGranted([READ_PERMISSION, WRITE_PERMISSION]);

              return await this.repository.removeAssetsFromAlbum(ids, album);
            }),
        ),
      )
      .asyncFunction(
        'deleteAssetsAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.array(IDENTIFIER),
          (ids: string[]): Promise<boolean> =>
            this.repository.run(async (): Promise<boolean> => {
              this.repository.permissions.ensureGranted([WRITE_PERMISSION]);

              return await this.repository.deleteAssets(ids);
            }),
        ),
      )
      .asyncFunction(
        'createAlbumAsync',
        ExpoFunction.typed4(
          ExpoValueTypes.string(),
          IDENTIFIER.nullable().optional(),
          ExpoValueTypes.boolean().optional(),
          IDENTIFIER.nullable().optional(),
          async (_name: string, _asset?: string | null, _copy?: boolean, _uri?: string | null): Promise<void> => {
            throw new ExpoModuleError(
              'ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION',
              'HarmonyOS exposes no public third-party API to create albums.',
            );
          },
        ),
      )
      .asyncFunction(
        'deleteAlbumsAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.array(IDENTIFIER),
          ExpoValueTypes.boolean().optional(),
          async (_albums: string[], _remove?: boolean): Promise<void> => {
            throw new ExpoModuleError(
              'ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION',
              'HarmonyOS exposes no public third-party API to delete albums.',
            );
          },
        ),
      );
  }
}
