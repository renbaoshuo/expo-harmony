/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoAppLifecycleState,
  ExpoModuleContext,
  ExpoModuleError,
  ExpoPermissionStatus,
  ExpoRuntimePermissionsKey,
} from '@expo-harmony/expo-modules-core';
import { common } from '@kit.AbilityKit';
import { dataSharePredicates, uniformTypeDescriptor } from '@kit.ArkData';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AlbumRecord, AssetRecord, ASSET_FETCH_COLUMNS, mapAsset, MEDIA_URI_PREFIX, PagedAssetResult } from './MediaLibraryAssets';
import {
  AlbumQueryOptions,
  AssetQueryOptions,
  AssetSortDescriptor,
  applyMediaTypeFilter,
  applyNativeSort,
  cursorStart,
  cursorStartInAssets,
  materializedAssets,
  readSortDescriptors,
} from './MediaLibraryQuery';
import { MediaLibraryPermissions, READ_PERMISSION, WRITE_PERMISSION } from './MediaLibraryPermissions';
import { queryIdentity, MediaLibraryPaging } from './MediaLibraryPaging';

// The public deleteAssets API accepts at most 300 URIs per system confirmation.
const DELETE_BATCH_LIMIT: number = 300;
const FETCH_RESULT_INDEX_API: number = 23;
// Media Library Kit changed its permission-denied code in API 14.
const PERMISSION_DENIED: number = 201;
const LEGACY_PERMISSION_DENIED: number = 13900012;
const pendingSaveDialogs: WeakSet<common.UIAbilityContext> = new WeakSet();

export class MediaLibraryRepository {
  readonly permissions: MediaLibraryPermissions;
  private readonly paging: MediaLibraryPaging = new MediaLibraryPaging();
  private library?: photoAccessHelper.PhotoAccessHelper;
  private warn?: (message: string) => void;
  private observing: boolean = false;
  private registered: boolean = false;
  private foreground: boolean;
  private refreshOnForeground: boolean = false;
  private destroyed: boolean = false;
  private pending: number = 0;
  private readonly changed = (change: photoAccessHelper.ChangeData): void => {
    if (!this.destroyed && this.observing && this.foreground && this.context.isValid && this.permissions.canReadLibrary()) {
      this.emitChange(change);
    }
  };

  readonly context: ExpoModuleContext;
  private readonly emitChange: (change?: photoAccessHelper.ChangeData) => void;

  constructor(context: ExpoModuleContext, emitChange: (change?: photoAccessHelper.ChangeData) => void) {
    this.context = context;
    this.emitChange = emitChange;
    this.permissions = new MediaLibraryPermissions(context);
    this.foreground = context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND;
  }

  startObserving(): void {
    this.observing = true;
    this.startSystemObservation();
  }

  stopObserving(): void {
    this.observing = false;
    this.refreshOnForeground = false;
    this.stopSystemObservation();
  }

  setForeground(foreground: boolean): void {
    if (this.foreground === foreground) return;
    this.foreground = foreground;

    if (!foreground) {
      this.refreshOnForeground = this.registered;
      this.stopSystemObservation();
      return;
    }

    this.startSystemObservation();

    if ((this.refreshOnForeground || this.registered) && this.observing && this.context.isValid) {
      this.emitChange();
    }
    this.refreshOnForeground = false;
  }

  permissionsChanged(): void {
    if (this.permissions.canReadLibrary()) this.startSystemObservation();
    else this.stopSystemObservation();
  }

  assertActive(): void {
    if (this.destroyed || !this.context.isValid)
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_DESTROYED', 'The media library module has been destroyed.');
  }

  read<T>(operation: () => Promise<T>): Promise<T> {
    return this.run(async (): Promise<T> => {
      this.permissions.ensureGranted([READ_PERMISSION]);
      return await operation();
    });
  }

  write<T>(operation: () => Promise<T>): Promise<T> {
    return this.run(async (): Promise<T> => {
      this.permissions.ensureGranted([READ_PERMISSION, WRITE_PERMISSION]);
      return await operation();
    });
  }

  writeOnly<T>(operation: () => Promise<T>): Promise<T> {
    return this.run(async (): Promise<T> => {
      this.permissions.ensureGranted([WRITE_PERMISSION]);
      return await operation();
    });
  }

  get helper(): photoAccessHelper.PhotoAccessHelper {
    this.assertActive();

    if (!canIUse('SystemCapability.FileManagement.PhotoAccessHelper.Core')) {
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_UNAVAILABLE', 'The HarmonyOS photo library capability is unavailable on this device.');
    }

    if (this.library === undefined) {
      const logger = this.context.logger;
      this.warn = (message: string): void => logger.warn(message);
      this.library = photoAccessHelper.getPhotoAccessHelper(this.context.uiAbilityContext);
    }

    return this.library;
  }

  async run<T>(operation: () => Promise<T>): Promise<T> {
    this.assertActive();

    this.pending++;

    try {
      const result = await operation();
      this.assertActive();

      return result;
    } catch (error) {
      if (error instanceof ExpoModuleError) throw new ExpoModuleError(error.code, error.message, error.cause, error.path);

      const cause = error as BusinessError;

      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_OPERATION', `HarmonyOS media library operation failed (${cause.code}): ${cause.message}`, error);
    } finally {
      this.pending--;
      if (this.pending === 0 && this.destroyed) this.releaseHelper();
    }
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.paging.destroy();
    this.permissions.destroy();
    this.observing = false;
    this.stopSystemObservation();

    // A pending system dialog retains the helper without blocking a JS reload.
    if (this.pending === 0) this.releaseHelper();
  }

  private async releaseHelper(): Promise<void> {
    const helper = this.library;
    this.library = undefined;

    try {
      await helper?.release();
    } catch (error) {
      this.warn?.(`Unable to release MediaLibrary: ${(error as BusinessError).message}`);
    }
  }

  private startSystemObservation(): void {
    if (this.destroyed || !this.foreground || !this.observing || this.registered) return;
    if (!this.permissions.canReadLibrary()) return;

    try {
      this.helper.registerChange(photoAccessHelper.DefaultChangeUri.DEFAULT_PHOTO_URI, true, this.changed);
      this.registered = true;
    } catch (error) {
      this.warn?.(`Unable to observe media library changes: ${(error as BusinessError).message}`);
    }
  }

  private stopSystemObservation(): void {
    if (!this.registered) return;

    try {
      this.library?.unRegisterChange(photoAccessHelper.DefaultChangeUri.DEFAULT_PHOTO_URI, this.changed);
      this.registered = false;
    } catch (error) {
      this.warn?.(`Unable to stop observing media library changes: ${(error as BusinessError).message}`);
    }
  }

  async getAssets(options: AssetQueryOptions): Promise<PagedAssetResult> {
    const album = options.album === undefined ? undefined : await this.requireAlbum(options.album);
    const predicates = new dataSharePredicates.DataSharePredicates();
    const matches = applyMediaTypeFilter(predicates, options.mediaType);
    const sorts = readSortDescriptors(options.sortBy);

    if (!matches) {
      if (options.after !== undefined) {
        throw new ExpoModuleError('ERR_MEDIA_LIBRARY_INVALID_CURSOR', `The pagination cursor '${options.after}' is not present in this media query.`);
      }
      return new PagedAssetResult([], null, false, 0);
    }

    const materialize = sorts.some((sort: AssetSortDescriptor): boolean => sort.key === 'creationTime');
    if (!materialize) applyNativeSort(predicates, sorts);

    const query: photoAccessHelper.FetchOptions = {
      fetchColumns: ASSET_FETCH_COLUMNS,
      predicates,
    };
    const fetch = album === undefined ? await this.helper.getAssets(query) : await album.getAssets(query);

    try {
      const items = await materializedAssets(fetch, options, sorts, materialize);

      const identity = queryIdentity(options.album, options.sortBy, options.mediaType, options.createdAfter, options.createdBefore);
      const locate =
        deviceInfo.sdkApiVersion >= FETCH_RESULT_INDEX_API
          ? async (uri: string): Promise<number> => {
              const asset = await this.findAsset(uri, []);

              return asset === undefined ? -1 : await fetch.getIndex(asset);
            }
          : undefined;

      const total = items === undefined ? fetch.getCount() : items.length;
      const start =
        items === undefined ? await cursorStart(fetch, options.after, identity, this.paging, locate) : cursorStartInAssets(items, options.after);
      const end = Math.min(start + options.first, total);

      const readLocation = options.resolveWithFullInfo && this.permissions.canReadLocation();
      const assets: AssetRecord[] = [];

      for (let i = start; i < end; i += 1) {
        const asset = items === undefined ? await fetch.getObjectByPosition(i) : items[i];

        assets.push(await mapAsset(asset, options.resolveWithFullInfo, readLocation));
      }

      const cursor = assets.length > 0 ? assets[assets.length - 1].id : (options.after ?? null);

      if (items === undefined && assets.length > 0) this.paging.remember(identity, assets[assets.length - 1].id, end - 1);

      return new PagedAssetResult(assets, cursor, end < total, total);
    } finally {
      fetch.close();
    }
  }

  async getAssetInfo(id: string): Promise<AssetRecord | null> {
    const asset = await this.findAsset(id);
    if (asset === undefined) return null;

    return await mapAsset(asset, true, this.permissions.canReadLocation());
  }

  async getAlbums(options: AlbumQueryOptions): Promise<AlbumRecord[]> {
    const albums = await this.queryAlbums(photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC);

    if (options.includeSmartAlbums) {
      const smart = await this.queryAlbums(photoAccessHelper.AlbumType.SYSTEM, photoAccessHelper.AlbumSubtype.ANY);

      smart.forEach((album: photoAccessHelper.Album): void => {
        albums.push(album);
      });
    }

    return albums.map((album: photoAccessHelper.Album): AlbumRecord => new AlbumRecord(album));
  }

  async getAlbum(title: string): Promise<AlbumRecord | null> {
    const album = await this.findAlbum(photoAccessHelper.AlbumKeys.ALBUM_NAME, title, false);
    return album === undefined ? null : new AlbumRecord(album);
  }

  async createAsset(input: string, id: string | undefined): Promise<AssetRecord> {
    const uri = await this.createAssetId(input, id);

    try {
      return await mapAsset(await this.requireAsset(uri), false);
    } catch (error) {
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_OPERATION', `Created media asset '${uri}', but could not read it: ${(error as BusinessError).message}`, error);
    }
  }

  async createAssetId(input: string, id?: string): Promise<string> {
    if (id === undefined && !this.hasWritePermission()) return await this.saveWithConfirmation(input);

    const album = id === undefined ? undefined : await this.requireWritableAlbum(id);
    const request = await this.importAsset(input);
    const created = request.getAsset();
    if (created === undefined || created === null) {
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_OPERATION', 'HarmonyOS did not return the newly created media asset.');
    }

    if (album !== undefined) {
      try {
        const change = new photoAccessHelper.MediaAlbumChangeRequest(album);
        change.addAssets([created]);
        await this.helper.applyChanges(change);
      } catch (error) {
        // The import has committed. Do not trigger a deletion dialog as rollback.
        throw new ExpoModuleError('ERR_MEDIA_LIBRARY_OPERATION', `Created media asset '${created.uri}', but could not add it to the album: ${(error as BusinessError).message}`, error);
      }
    }

    return created.uri;
  }

  async saveToLibrary(input: string): Promise<void> {
    if (this.hasWritePermission()) await this.importAsset(input);
    else await this.saveWithConfirmation(input);
  }

  private hasWritePermission(): boolean {
    return this.context.permissionStatus(WRITE_PERMISSION) === ExpoPermissionStatus.GRANTED;
  }

  private assertCanShowSaveDialog(): void {
    this.assertActive();
    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_SAVE_CONTEXT', 'Saving without media library write permission requires a foreground UIAbility.');
    }
  }

  private async saveWithConfirmation(input: string): Promise<string> {
    this.assertCanShowSaveDialog();

    const ability = this.context.uiAbilityContext;
    if (pendingSaveDialogs.has(ability)) {
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_SAVE_IN_PROGRESS', 'A media library save confirmation is already open.');
    }

    pendingSaveDialogs.add(ability);

    try {
      return await this.withImportSource(input, async (file, config): Promise<string> => {
        const dir = await fileIo.mkdtemp(`${this.context.cachePath}/expo-media-import-XXXXXX`);

        try {
          // Keep the content shown in the confirmation stable while it is open.
          const snapshot = `${dir}/asset.${config.fileNameExtension}`;
          await fileIo.copyFile(file.fd, snapshot);
          this.assertCanShowSaveDialog();

          const destinations = await this.helper.showAssetsCreationDialog([fileUri.getUriFromPath(snapshot)], [config]);
          if (destinations.length === 0) {
            throw new ExpoModuleError('ERR_MEDIA_LIBRARY_SAVE_CANCELED', 'The user canceled the media library save.');
          }

          const destination = destinations[0];
          if (destinations.length !== 1 || typeof destination !== 'string' || !destination.startsWith(MEDIA_URI_PREFIX)) {
            throw new ExpoModuleError('ERR_MEDIA_LIBRARY_OPERATION', 'HarmonyOS did not return an authorized destination for the media library save.');
          }

          // The dialog already created the asset, so finish the approved write across a JS runtime replacement.
          const output = await fileIo.open(destination, fileIo.OpenMode.WRITE_ONLY);
          try {
            await fileIo.copyFile(snapshot, output.fd);
          } finally {
            await fileIo.close(output);
          }

          return destination;
        } finally {
          try { await fileIo.rmdir(dir); } catch (_) {}
        }
      });
    } finally {
      pendingSaveDialogs.delete(ability);
    }
  }

  private importAsset(input: string): Promise<photoAccessHelper.MediaAssetChangeRequest> {
    return this.withImportSource(input, async (file, config): Promise<photoAccessHelper.MediaAssetChangeRequest> => {
      const request = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        this.context.uiAbilityContext, config.photoType, config.fileNameExtension, { title: config.title },
      );

      const output = await request.getWriteCacheHandler();
      try {
        await fileIo.copyFile(file.fd, output);
      } finally {
        await fileIo.close(output);
      }

      await this.helper.applyChanges(request);

      return request;
    });
  }

  private async withImportSource<T>(
    input: string,
    operation: (file: fileIo.File, config: photoAccessHelper.PhotoCreationConfig) => Promise<T>,
  ): Promise<T> {
    const source = this.context.fileSourceForRead(input);
    const file = await fileIo.open(source, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);

    try {
      this.context.readPathForDescriptor(source, file);
      if (!(await fileIo.stat(file.fd)).isFile()) {
        throw new ExpoModuleError('ERR_MEDIA_LIBRARY_INVALID_URI', 'The local media source must be a regular file.');
      }

      const name = file.name;
      const dot = name.lastIndexOf('.');
      if (dot <= 0 || dot === name.length - 1) {
        throw new ExpoModuleError('ERR_MEDIA_LIBRARY_MISSING_EXTENSION', 'The local media file must have a filename extension.');
      }
      if (name.includes('/') || name.includes('\\') || name.includes('\0')) {
        throw new ExpoModuleError('ERR_MEDIA_LIBRARY_INVALID_URI', 'The local media source must have a valid filename.');
      }

      const extension = name.slice(dot + 1).toLowerCase();
      const id = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(`.${extension}`);
      const type = uniformTypeDescriptor.getTypeDescriptor(id);
      const isImage = type.belongsTo(uniformTypeDescriptor.UniformDataType.IMAGE);
      if (!isImage && !type.belongsTo(uniformTypeDescriptor.UniformDataType.VIDEO)) {
        throw new ExpoModuleError('ERR_MEDIA_LIBRARY_UNSUPPORTED_MEDIA_TYPE', 'HarmonyOS Media Library Kit imports only images and videos.');
      }

      this.assertActive();

      const title = name.slice(0, dot);
      const config: photoAccessHelper.PhotoCreationConfig = {
        photoType: isImage ? photoAccessHelper.PhotoType.IMAGE : photoAccessHelper.PhotoType.VIDEO,
        fileNameExtension: extension,
      };
      if (title !== '.' && title !== '..' && !/[\\/:*?"'`<>|{}\[\]]/.test(title)) config.title = title;

      return await operation(file, config);
    } finally {
      try { await fileIo.close(file); } catch (_) {}
    }
  }

  async getAssetAlbums(id: string): Promise<photoAccessHelper.Album[]> {
    await this.requireAsset(id, []);

    const albums = await this.queryAlbums(photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC);
    const matches: photoAccessHelper.Album[] = [];

    for (const album of albums) {
      const predicates = new dataSharePredicates.DataSharePredicates();
      predicates.equalTo(photoAccessHelper.PhotoKeys.URI, id);
      const fetch = await album.getAssets({ fetchColumns: [], predicates });

      try {
        if (fetch.getCount() > 0) matches.push(album);
      } finally {
        fetch.close();
      }
    }

    return matches;
  }

  async addAssetsToAlbum(ids: string[], id: string): Promise<boolean> {
    if (ids.length === 0) return true;

    const album = await this.requireWritableAlbum(id);
    const assets = await this.requireAssets(ids);

    const change = new photoAccessHelper.MediaAlbumChangeRequest(album);
    change.addAssets(assets);

    await this.helper.applyChanges(change);

    return true;
  }

  async removeAssetsFromAlbum(ids: string[], id: string): Promise<boolean> {
    if (ids.length === 0) return true;

    const album = await this.requireWritableAlbum(id);
    const assets = await this.requireAssets(ids);

    const change = new photoAccessHelper.MediaAlbumChangeRequest(album);
    change.removeAssets(assets);

    await this.helper.applyChanges(change);

    return true;
  }

  async deleteAssets(ids: string[]): Promise<boolean> {
    const unique = uniqueStrings(ids);

    for (let start = 0; start < unique.length; start += DELETE_BATCH_LIMIT) {
      this.assertActive();

      await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(this.context.uiAbilityContext, unique.slice(start, start + DELETE_BATCH_LIMIT));
    }

    return true;
  }

  async requireAssets(ids: string[]): Promise<photoAccessHelper.PhotoAsset[]> {
    const assets: photoAccessHelper.PhotoAsset[] = [];
    const unique = uniqueStrings(ids);

    for (let i = 0; i < unique.length; i += 1) {
      assets.push(await this.requireAsset(unique[i], []));
    }

    return assets;
  }

  async requireAsset(id: string, columns: string[] = ASSET_FETCH_COLUMNS): Promise<photoAccessHelper.PhotoAsset> {
    const asset = await this.findAsset(id, columns);
    if (asset === undefined) {
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_ASSET_NOT_FOUND', `No media asset exists for identifier '${id}'.`);
    }

    return asset;
  }

  async findAsset(id: string, columns: string[] = ASSET_FETCH_COLUMNS): Promise<photoAccessHelper.PhotoAsset | undefined> {
    const scoped = !this.permissions.canReadLibrary();
    if (scoped) {
      // A URI grant must not bypass permissions masked by the runtime.
      if (this.context.services.get(ExpoRuntimePermissionsKey) !== undefined) {
        this.permissions.ensureGranted([READ_PERMISSION]);
      }
      if (!id.startsWith(MEDIA_URI_PREFIX)) {
        throw new ExpoModuleError('ERR_MEDIA_LIBRARY_INVALID_URI', 'Expected a HarmonyOS media asset URI.');
      }
      this.context.assertFileAccess(id);
    }

    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, id);

    try {
      // PhotoAccessHelper honors the URI-specific grant from PhotoViewPicker.
      const fetch = await this.helper.getAssets({ fetchColumns: columns, predicates });

      try {
        if (fetch.getCount() !== 1) return undefined;

        return await fetch.getFirstObject();
      } finally {
        fetch.close();
      }
    } catch (error) {
      const cause = error as BusinessError;
      if (scoped && (cause.code === PERMISSION_DENIED || cause.code === LEGACY_PERMISSION_DENIED)) {
        this.permissions.ensureGranted([READ_PERMISSION]);
      }

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_OPERATION', `HarmonyOS media library operation failed (${cause.code}): ${cause.message}`, error);
    }
  }

  async requireAlbum(id: string): Promise<photoAccessHelper.Album> {
    const album = await this.findAlbum(photoAccessHelper.AlbumKeys.URI, id, true);
    if (album === undefined) {
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_ALBUM_NOT_FOUND', `No media album exists for identifier '${id}'.`);
    }

    return album;
  }

  async requireWritableAlbum(id: string): Promise<photoAccessHelper.Album> {
    const album = await this.requireAlbum(id);

    if (album.albumType !== photoAccessHelper.AlbumType.USER) {
      throw new ExpoModuleError(
        'ERR_MEDIA_LIBRARY_UNSUPPORTED_ALBUM_OPERATION',
        'HarmonyOS system albums are read-only for third-party applications.',
      );
    }

    return album;
  }

  async findAlbum(key: photoAccessHelper.AlbumKeys, value: string, system: boolean): Promise<photoAccessHelper.Album | undefined> {
    const types: photoAccessHelper.AlbumType[] = system
      ? [photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumType.SYSTEM]
      : [photoAccessHelper.AlbumType.USER];

    for (let i = 0; i < types.length; i += 1) {
      const predicates = new dataSharePredicates.DataSharePredicates();
      predicates.equalTo(key, value);

      const fetch = await this.helper.getAlbums(types[i], photoAccessHelper.AlbumSubtype.ANY, {
        fetchColumns: [],
        predicates,
      });

      try {
        if (fetch.getCount() > 0) return await fetch.getFirstObject();
      } finally {
        fetch.close();
      }
    }

    return undefined;
  }

  async queryAlbums(type: photoAccessHelper.AlbumType, subtype: photoAccessHelper.AlbumSubtype): Promise<photoAccessHelper.Album[]> {
    const fetch = await this.helper.getAlbums(type, subtype, {
      fetchColumns: [],
      predicates: new dataSharePredicates.DataSharePredicates(),
    });

    try {
      return await fetch.getAllObjects();
    } finally {
      fetch.close();
    }
  }
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set<string>(values));
}
