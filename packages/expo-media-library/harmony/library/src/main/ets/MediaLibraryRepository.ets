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
} from '@expo-harmony/expo-modules-core';
import { common } from '@kit.AbilityKit';
import { dataSharePredicates, uniformTypeDescriptor } from '@kit.ArkData';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AlbumRecord, AssetRecord, ASSET_FETCH_COLUMNS, mapAsset, MediaLibraryChangeEvent, PagedAssetResult } from './MediaLibraryAssets';
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
const pendingSaveDialogs: WeakSet<common.UIAbilityContext> = new WeakSet();

export class MediaLibraryRepository {
  readonly permissions: MediaLibraryPermissions;
  private readonly paging: MediaLibraryPaging = new MediaLibraryPaging();
  private library?: photoAccessHelper.PhotoAccessHelper;
  private warn?: (message: string) => void;
  private observing: boolean = false;
  private registered: boolean = false;
  private foreground: boolean;
  private destroyed: boolean = false;
  private pending: number = 0;
  private idle?: () => void;
  private release?: Promise<void>;
  private readonly changed = (_change: photoAccessHelper.ChangeData): void => {
    if (!this.destroyed && this.observing && this.foreground && this.context.isValid) {
      this.emitChange(new MediaLibraryChangeEvent());
    }
  };

  readonly context: ExpoModuleContext;
  private readonly emitChange: (event: MediaLibraryChangeEvent) => void;

  constructor(context: ExpoModuleContext, emitChange: (event: MediaLibraryChangeEvent) => void) {
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
    this.stopSystemObservation();
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    if (foreground) this.startSystemObservation();
    else this.stopSystemObservation();
  }

  permissionsChanged(): void {
    this.startSystemObservation();
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

    if (this.library === undefined) this.library = photoAccessHelper.getPhotoAccessHelper(this.context.uiAbilityContext);

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
      if (error instanceof ExpoModuleError) throw new ExpoModuleError(error.code, error.message, error.cause);

      const cause = error as BusinessError;

      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_OPERATION', `HarmonyOS media library operation failed (${cause.code}): ${cause.message}`, error);
    } finally {
      this.pending--;
      if (this.pending === 0) this.idle?.();
    }
  }

  destroy(): Promise<void> {
    if (this.release !== undefined) return this.release;

    this.destroyed = true;
    this.paging.destroy();
    this.permissions.destroy();
    this.observing = false;
    this.stopSystemObservation();

    this.release = this.releaseWhenIdle();

    return this.release;
  }

  private async releaseWhenIdle(): Promise<void> {
    // FetchResult and ImageSource cleanup finishes before releasing their helper.
    if (this.pending > 0)
      await new Promise<void>((resolve): void => {
        this.idle = resolve;
      });

    await this.library?.release();
    this.library = undefined;
  }

  private startSystemObservation(): void {
    if (this.destroyed || !this.foreground || !this.observing || this.registered) return;
    if (this.context.permissionStatus(READ_PERMISSION) !== ExpoPermissionStatus.GRANTED) return;

    const logger = this.context.logger;
    this.warn = (message: string): void => logger.warn(message);
    try {
      this.helper.registerChange(photoAccessHelper.DefaultChangeUri.DEFAULT_PHOTO_URI, true, this.changed);
      this.registered = true;
    } catch (error) {
      logger.warn(`Unable to observe media library changes: ${(error as BusinessError).message}`);
    }
  }

  private stopSystemObservation(): void {
    if (!this.registered) return;

    try {
      this.library?.unRegisterChange(photoAccessHelper.DefaultChangeUri.DEFAULT_PHOTO_URI, this.changed);
      this.registered = false;
    } catch (error) {
      // Reload can close public context access before unregistering the observer.
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
              const asset = await this.findAsset(uri);

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
      return await this.withImportSource(input, true, async (uri, config): Promise<string> => {
        this.assertCanShowSaveDialog();
        const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);

        try {
          this.assertCanShowSaveDialog();

          const destinations = await this.helper.showAssetsCreationDialog([uri], [config]);
          if (destinations.length === 0) {
            throw new ExpoModuleError('ERR_MEDIA_LIBRARY_SAVE_CANCELED', 'The user canceled the media library save.');
          }

          const destination = destinations[0];
          if (destinations.length !== 1 || typeof destination !== 'string' || !destination.startsWith('file://media/Photo/')) {
            throw new ExpoModuleError('ERR_MEDIA_LIBRARY_OPERATION', 'HarmonyOS did not return an authorized destination for the media library save.');
          }
          // The dialog has already created the asset. Finish the approved write even if
          // the JS runtime is replaced while the dialog is open.
          const output = await fileIo.open(destination, fileIo.OpenMode.WRITE_ONLY);

          try {
            await fileIo.copyFile(file.fd, output.fd);
          } finally {
            await fileIo.close(output);
          }

          return destination;
        } finally {
          try { await fileIo.close(file); } catch (_) {}
        }
      });
    } finally {
      pendingSaveDialogs.delete(ability);
    }
  }

  private importAsset(input: string): Promise<photoAccessHelper.MediaAssetChangeRequest> {
    return this.withImportSource(input, false, async (uri, config): Promise<photoAccessHelper.MediaAssetChangeRequest> => {
      const ability = this.context.uiAbilityContext;
      const request = config.photoType === photoAccessHelper.PhotoType.IMAGE
        ? photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(ability, uri)
        : photoAccessHelper.MediaAssetChangeRequest.createVideoAssetRequest(ability, uri);
      await this.helper.applyChanges(request);

      return request;
    });
  }

  private async withImportSource<T>(
    input: string,
    snapshot: boolean,
    operation: (uri: string, config: photoAccessHelper.PhotoCreationConfig) => Promise<T>,
  ): Promise<T> {
    const source = this.context.fileSourceForRead(input);
    const file = await fileIo.open(source, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);
    let stagingDirectory: string | undefined;

    try {
      const path = this.context.readPathForDescriptor(source, file);
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
      const descriptor = uniformTypeDescriptor.getTypeDescriptor(id);
      const isImage = descriptor.belongsTo(uniformTypeDescriptor.UniformDataType.IMAGE);
      if (!isImage && !descriptor.belongsTo(uniformTypeDescriptor.UniformDataType.VIDEO)) {
        throw new ExpoModuleError('ERR_MEDIA_LIBRARY_UNSUPPORTED_MEDIA_TYPE', 'HarmonyOS Media Library Kit imports only images and videos.');
      }

      const ability = this.context.uiAbilityContext;
      const authority = new fileUri.FileUri(ability.cacheDir).authority;
      let uri = path.startsWith('/') ? fileUri.getUriFromPath(path) : '';
      // The dialog must preview the same bytes that will be written. Media Library
      // Kit also needs a sandbox URI when the source comes from an external provider.
      if (snapshot || authority === '' || !uri.startsWith(`file://${authority}/`)) {
        stagingDirectory = await fileIo.mkdtemp(`${this.context.cachePath}/expo-media-import-XXXXXX`);
        const destination = `${stagingDirectory}/${name}`;
        await fileIo.copyFile(file.fd, destination);
        uri = fileUri.getUriFromPath(destination);
      }

      this.assertActive();

      const title = name.slice(0, dot);
      const config: photoAccessHelper.PhotoCreationConfig = {
        photoType: isImage ? photoAccessHelper.PhotoType.IMAGE : photoAccessHelper.PhotoType.VIDEO,
        fileNameExtension: extension,
      };
      if (title !== '.' && title !== '..' && !/[\\/:*?"'`<>|{}\[\]]/.test(title)) config.title = title;

      return await operation(uri, config);
    } finally {
      try { await fileIo.close(file); } catch (_) {}
      if (stagingDirectory !== undefined) {
        try { await fileIo.rmdir(stagingDirectory); } catch (_) {}
      }
    }
  }

  async getAssetAlbums(id: string): Promise<photoAccessHelper.Album[]> {
    await this.requireAsset(id);
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

  async addAssetsToAlbum(ids: string[], id: string, _copy: boolean): Promise<boolean> {
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
      assets.push(await this.requireAsset(unique[i]));
    }

    return assets;
  }

  async requireAsset(id: string): Promise<photoAccessHelper.PhotoAsset> {
    const asset = await this.findAsset(id);
    if (asset === undefined) {
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_ASSET_NOT_FOUND', `No media asset exists for identifier '${id}'.`);
    }

    return asset;
  }

  async findAsset(id: string): Promise<photoAccessHelper.PhotoAsset | undefined> {
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, id);

    const fetch = await this.helper.getAssets({ fetchColumns: ASSET_FETCH_COLUMNS, predicates });

    try {
      if (fetch.getCount() !== 1) return undefined;

      return await fetch.getFirstObject();
    } finally {
      fetch.close();
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
