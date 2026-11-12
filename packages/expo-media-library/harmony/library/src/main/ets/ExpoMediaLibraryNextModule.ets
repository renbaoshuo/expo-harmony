/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError,
  ExpoSharedObject, ExpoSharedObjectClassDefinition, ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { deviceInfo } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ImageMetadata, LocationRecord, readAssetImageMetadata } from './MediaLibraryAssets';
import { CHANGE_EVENT_NAME, mediaLibraryDefinition } from './MediaLibraryModuleDefinition';
import {
  AssetField, MediaLibraryNativeQuery, QUERY_FIELD, QUERY_PAGE_SIZE, QUERY_SORT, QUERY_VALUE, QueryOperator, QuerySort,
} from './MediaLibraryNativeQuery';
import { AssetShape, NextAssetInfo, NextAssetMetadata, requireShape, resolveShape } from './MediaLibraryNextAssets';
import { READ_PERMISSION, WRITE_PERMISSION } from './MediaLibraryPermissions';
import { requireString } from './MediaLibraryQuery';
import { MediaLibraryRepository } from './MediaLibraryRepository';

// Earlier SDKs expose favorite mutation only to system apps. Do not call that private API.
const PUBLIC_SET_FAVORITE_API: number = 26;
const IDENTIFIER = ExpoValueTypes.custom<string>('non-empty identifier', requireString, (value: string): ESObject => value);

class MediaLibraryAsset extends ExpoSharedObject {
  readonly id: string;
  readonly repository: MediaLibraryRepository;

  constructor(context: ExpoModuleContext, id: string, repository: MediaLibraryRepository) {
    super(context);
    this.id = id;
    this.repository = repository;
  }

  metadata(): Promise<NextAssetMetadata> {
    return this.repository.read(async (): Promise<NextAssetMetadata> => new NextAssetMetadata(await this.repository.requireAsset(this.id)));
  }

  info(): Promise<NextAssetInfo> {
    return this.repository.read(async (): Promise<NextAssetInfo> => {
      const asset = await this.repository.requireAsset(this.id);
      return new NextAssetInfo(new NextAssetMetadata(asset), await requireShape(asset));
    });
  }

  shape(required: boolean): Promise<AssetShape | null> {
    return this.repository.read(async (): Promise<AssetShape | null> => {
      const asset = await this.repository.requireAsset(this.id);
      return required ? await requireShape(asset) : await resolveShape(asset);
    });
  }

  imageMetadata(): Promise<ImageMetadata | undefined> {
    return this.repository.read(async (): Promise<ImageMetadata | undefined> => await readAssetImageMetadata(
      await this.repository.requireAsset(this.id), this.repository.permissions.canReadLocation(),
    ));
  }

  favorite(value: boolean): Promise<void> {
    return this.repository.write(async (): Promise<void> => {
      if (deviceInfo.sdkApiVersion < PUBLIC_SET_FAVORITE_API) {
        throw new ExpoModuleError('ERR_MEDIA_LIBRARY_UNAVAILABLE', 'Setting favorites requires the public HarmonyOS API 26 or newer.');
      }

      const request = new photoAccessHelper.MediaAssetChangeRequest(await this.repository.requireAsset(this.id));
      request.setFavorite(value);
      await this.repository.helper.applyChanges(request);
    });
  }
}

class MediaLibraryAlbum extends ExpoSharedObject {
  readonly id: string;

  constructor(context: ExpoModuleContext, id: string) {
    super(context);
    this.id = id;
  }
}

function unsupportedAlbumOperation(): never {
  throw new ExpoModuleError('ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION', 'HarmonyOS exposes no public third-party API to create or delete albums.');
}

export class ExpoMediaLibraryNextModule extends ExpoModule {
  private readonly repository: MediaLibraryRepository;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.repository = new MediaLibraryRepository(context, (event): void => this.sendEvent(CHANGE_EVENT_NAME, event));
  }

  definition(): ExpoModuleDefinition {
    const repository = this.repository;
    const asset = new ExpoSharedObjectClassDefinition<MediaLibraryAsset>('Asset');
    const album = new ExpoSharedObjectClassDefinition<MediaLibraryAlbum>('Album');
    const query = new ExpoSharedObjectClassDefinition<MediaLibraryNativeQuery>('Query');
    const makeAsset = (id: string): MediaLibraryAsset => asset.instance(new MediaLibraryAsset(this.context, id, repository));
    const makeAlbum = (id: string): MediaLibraryAlbum => album.instance(new MediaLibraryAlbum(this.context, id));

    asset
      .construct(ExpoFunction.ownedTyped1(IDENTIFIER, (context: ExpoModuleContext, id: string): MediaLibraryAsset => new MediaLibraryAsset(context, id, repository)))
      .property('id', ExpoValueTypes.string(), (object: MediaLibraryAsset): string => object.id)
      .asyncFunction('getCreationTime', async (object: MediaLibraryAsset): Promise<number | null> => (await object.metadata()).creationTime)
      .asyncFunction('getModificationTime', async (object: MediaLibraryAsset): Promise<number | null> => (await object.metadata()).modificationTime)
      .asyncFunction('getDuration', async (object: MediaLibraryAsset): Promise<number | null> => (await object.metadata()).duration)
      .asyncFunction('getFilename', async (object: MediaLibraryAsset): Promise<string> => (await object.metadata()).filename)
      .asyncFunction('getMediaType', async (object: MediaLibraryAsset): Promise<string> => (await object.metadata()).mediaType)
      .asyncFunction('getFavorite', async (object: MediaLibraryAsset): Promise<boolean> => (await object.metadata()).isFavorite)
      .asyncFunction('getUri', async (object: MediaLibraryAsset): Promise<string> => (await object.metadata()).id)
      .asyncFunction('getWidth', async (object: MediaLibraryAsset): Promise<number> => (await object.shape(true))!.width)
      .asyncFunction('getHeight', async (object: MediaLibraryAsset): Promise<number> => (await object.shape(true))!.height)
      .asyncFunction('getShape', (object: MediaLibraryAsset): Promise<AssetShape | null> => object.shape(false))
      .asyncFunction('getInfo', (object: MediaLibraryAsset): Promise<NextAssetInfo> => object.info())
      .asyncFunction('getExif', async (object: MediaLibraryAsset): Promise<Record<string, ESObject>> => (await object.imageMetadata())?.exif ?? {})
      .asyncFunction('getLocation', async (object: MediaLibraryAsset): Promise<LocationRecord | null> => (await object.imageMetadata())?.location ?? null)
      .asyncFunction('setFavorite', ExpoFunction.ownedTyped1(ExpoValueTypes.boolean(),
        (object: MediaLibraryAsset, value: boolean): Promise<void> => object.favorite(value)))
      .asyncFunction('getAlbums', ExpoFunction.ownedTyped0((object: MediaLibraryAsset): Promise<MediaLibraryAlbum[]> => repository.read(async (): Promise<MediaLibraryAlbum[]> => {
        const albums = await repository.getAssetAlbums(object.id);
        return albums.map((item: photoAccessHelper.Album): MediaLibraryAlbum => makeAlbum(item.albumUri));
      })).returns(ExpoValueTypes.array(album.valueType())))
      .asyncFunction('delete', (object: MediaLibraryAsset): Promise<void> => repository.writeOnly(async (): Promise<void> => {
        await repository.deleteAssets([object.id]);
      }))
      .staticAsyncFunction('create', ExpoFunction.ownedTyped2(IDENTIFIER, album.valueType().nullable().optional(),
        (_context: ExpoModuleContext, uri: string, target?: MediaLibraryAlbum | null): Promise<MediaLibraryAsset> => repository.run(async (): Promise<MediaLibraryAsset> => {
          if (target != null) repository.permissions.ensureGranted([READ_PERMISSION, WRITE_PERMISSION]);
          return makeAsset(await repository.createAssetId(uri, target?.id));
        })).returns(asset.valueType()))
      .staticAsyncFunction('delete', ExpoFunction.ownedTyped1(ExpoValueTypes.array(asset.valueType()),
        (_context: ExpoModuleContext, assets: MediaLibraryAsset[]): Promise<void> => repository.writeOnly(async (): Promise<void> => {
          const ids = assets.map((item: MediaLibraryAsset): string => item.id);
          await repository.deleteAssets(ids);
        })));

    // Native factories return the base class, so the upstream JS subclass guard does not run for those objects.
    for (const name of ['getMediaSubtypes', 'getLivePhotoVideoUri', 'getIsInCloud', 'getOrientation']) {
      asset.syncFunction(name, (_object: MediaLibraryAsset): never => {
        throw new ExpoModuleError('ERR_UNAVAILABLE', `MediaLibrary.${name} is only available on iOS.`);
      });
    }

    album
      .construct(ExpoFunction.ownedTyped1(IDENTIFIER, (context: ExpoModuleContext, id: string): MediaLibraryAlbum => new MediaLibraryAlbum(context, id)))
      .property('id', ExpoValueTypes.string(), (object: MediaLibraryAlbum): string => object.id)
      .asyncFunction('getTitle', (object: MediaLibraryAlbum): Promise<string> => repository.read(async (): Promise<string> => (await repository.requireAlbum(object.id)).albumName))
      .asyncFunction('getAssets', ExpoFunction.ownedTyped0((object: MediaLibraryAlbum): Promise<MediaLibraryAsset[]> => {
        const request = new MediaLibraryNativeQuery(this.context, repository).album(object.id);
        return this.queryAssets(request, makeAsset);
      }).returns(ExpoValueTypes.array(asset.valueType())))
      .asyncFunction('add', ExpoFunction.ownedTyped1(asset.valueType().or(ExpoValueTypes.array(asset.valueType())),
        (object: MediaLibraryAlbum, input: MediaLibraryAsset | MediaLibraryAsset[]): Promise<void> => repository.write(async (): Promise<void> => {
          const assets = Array.isArray(input) ? input : [input];
          await repository.addAssetsToAlbum(assets.map((item: MediaLibraryAsset): string => item.id), object.id, false);
        })))
      .asyncFunction('removeAssets', ExpoFunction.ownedTyped1(ExpoValueTypes.array(asset.valueType()),
        (object: MediaLibraryAlbum, assets: MediaLibraryAsset[]): Promise<void> => repository.write(async (): Promise<void> => {
          await repository.removeAssetsFromAlbum(assets.map((item: MediaLibraryAsset): string => item.id), object.id);
        })))
      .asyncFunction('delete', async (_object: MediaLibraryAlbum): Promise<void> => unsupportedAlbumOperation())
      .staticAsyncFunction('get', ExpoFunction.ownedTyped1(ExpoValueTypes.string(),
        (_context: ExpoModuleContext, title: string): Promise<MediaLibraryAlbum | null> => repository.read(async (): Promise<MediaLibraryAlbum | null> => {
          const found = await repository.getAlbum(title);
          return found === null ? null : makeAlbum(found.id);
        })).returns(album.valueType().nullable()))
      .staticAsyncFunction('getAll', ExpoFunction.ownedTyped0((_context: ExpoModuleContext): Promise<MediaLibraryAlbum[]> => repository.read(async (): Promise<MediaLibraryAlbum[]> => {
        const albums = await repository.queryAlbums(photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC);
        return albums.map((item: photoAccessHelper.Album): MediaLibraryAlbum => makeAlbum(item.albumUri));
      })).returns(ExpoValueTypes.array(album.valueType())))
      .staticAsyncFunction('create', ExpoFunction.ownedTyped3(ExpoValueTypes.string(),
        ExpoValueTypes.array(ExpoValueTypes.string()).or(ExpoValueTypes.array(asset.valueType())), ExpoValueTypes.boolean().optional(),
        async (_context: ExpoModuleContext, _name: string, _assets: string[] | MediaLibraryAsset[], _move?: boolean): Promise<MediaLibraryAlbum> => unsupportedAlbumOperation()))
      .staticAsyncFunction('delete', ExpoFunction.ownedTyped2(ExpoValueTypes.array(album.valueType()), ExpoValueTypes.boolean().optional(),
        async (_context: ExpoModuleContext, _albums: MediaLibraryAlbum[], _deleteAssets?: boolean): Promise<void> => unsupportedAlbumOperation()));

    query
      .construct((context: ExpoModuleContext): MediaLibraryNativeQuery => new MediaLibraryNativeQuery(context, repository))
      .syncFunction('eq', ExpoFunction.ownedTyped2(QUERY_FIELD, QUERY_VALUE,
        (object: MediaLibraryNativeQuery, field: AssetField, value: string | number | boolean): MediaLibraryNativeQuery => object.filter(field, QueryOperator.EQ, [value])).returns(query.valueType()))
      .syncFunction('within', ExpoFunction.ownedTyped2(QUERY_FIELD, ExpoValueTypes.array(QUERY_VALUE),
        (object: MediaLibraryNativeQuery, field: AssetField, values: (string | number | boolean)[]): MediaLibraryNativeQuery => object.filter(field, QueryOperator.WITHIN, values)).returns(query.valueType()))
      .syncFunction('limit', ExpoFunction.ownedTyped1(QUERY_PAGE_SIZE,
        (object: MediaLibraryNativeQuery, limit: number): MediaLibraryNativeQuery => object.limit(limit)).returns(query.valueType()))
      .syncFunction('offset', ExpoFunction.ownedTyped1(QUERY_PAGE_SIZE,
        (object: MediaLibraryNativeQuery, offset: number): MediaLibraryNativeQuery => object.offset(offset)).returns(query.valueType()))
      .syncFunction('album', ExpoFunction.ownedTyped1(album.valueType(),
        (object: MediaLibraryNativeQuery, target: MediaLibraryAlbum): MediaLibraryNativeQuery => object.album(target.id)).returns(query.valueType()))
      .syncFunction('orderBy', ExpoFunction.ownedTyped1(QUERY_SORT,
        (object: MediaLibraryNativeQuery, sort: QuerySort): MediaLibraryNativeQuery => object.orderBy(sort)).returns(query.valueType()))
      .asyncFunction('exe', ExpoFunction.ownedTyped0((object: MediaLibraryNativeQuery): Promise<MediaLibraryAsset[]> => this.queryAssets(object, makeAsset)).returns(ExpoValueTypes.array(asset.valueType())))
      .asyncFunction('exeForMetadata', async (object: MediaLibraryNativeQuery): Promise<NextAssetMetadata[]> => {
        const assets = await object.execute(true);
        return assets.map((item: photoAccessHelper.PhotoAsset): NextAssetMetadata => new NextAssetMetadata(item));
      });

    for (const operator of [QueryOperator.GT, QueryOperator.GTE, QueryOperator.LT, QueryOperator.LTE]) {
      query.syncFunction(operator, ExpoFunction.ownedTyped2(QUERY_FIELD, ExpoValueTypes.number(),
        (object: MediaLibraryNativeQuery, field: AssetField, value: number): MediaLibraryNativeQuery => object.filter(field, operator, [value])).returns(query.valueType()));
    }

    return mediaLibraryDefinition(repository, 'ExpoMediaLibraryNext')
      .sharedObjectClass(asset)
      .sharedObjectClass(album)
      .sharedObjectClass(query)
      // No limited grants exist on HarmonyOS, so the picker is a no-op as upstream specifies for full access.
      .asyncFunction('presentPermissionsPicker', ExpoFunction.typed1(ExpoValueTypes.array(ExpoValueTypes.string()).optional(),
        async (_types?: string[]): Promise<void> => repository.assertActive()));
  }

  private async queryAssets(query: MediaLibraryNativeQuery, makeAsset: (id: string) => MediaLibraryAsset): Promise<MediaLibraryAsset[]> {
    const assets = await query.execute();
    this.repository.assertActive();
    return assets.map((item: photoAccessHelper.PhotoAsset): MediaLibraryAsset => makeAsset(item.uri));
  }
}
