/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleDefinition,
  ExpoPermissionStatus,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { common } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { cropImage } from './ExpoImagePickerCrop';
import { ExpoImagePickerError } from './ExpoImagePickerError';
import { IMAGE_PICKER_OPTIONS, ImagePickerOptions, allowsCrop, selectsImages, selectsVideos } from './ImagePickerOptions';
import { PermissionResponse, cameraPickerPermission, hasCameraPicker, hasPhotoPicker, mediaLibraryPermission } from './ImagePickerPermissions';
import { ImagePickerAsset, removeAssets, removeCapture, createCapture, exportImage, exportMovingPhoto, exportVideo } from './ExpoImagePickerMedia';

const PHOTO_PICKER_MAX_SELECTION: number = 500;
const CAMERA_RESULT_OK: number = 0;
const CAMERA_RESULT_CANCELLED: number = -1;
const CAMERA_MAX_VIDEO_DURATION: number = 0x7fffffff;
const MOVING_PHOTO_BADGE_API: number = 22;
const ADVANCED_PHOTO_PICKER_API: number = 26;
const MEDIA_LOCATION_PERMISSION = 'ohos.permission.MEDIA_LOCATION';

// Keep the lock until the system picker settles, including across RN reloads.
const pickers: WeakSet<common.UIAbilityContext> = new WeakSet();

class ImagePickerResult {
  canceled: boolean;
  assets: ImagePickerAsset[] | null;

  constructor(assets: ImagePickerAsset[] = []) {
    this.canceled = assets.length === 0;
    this.assets = this.canceled ? null : assets;
  }
}

export class ExpoImagePickerModule extends ExpoModule {
  private destroyed: boolean = false;
  private cancelMovingPhoto?: () => void;
  private cancelCrop?: () => void;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExponentImagePicker')
      .asyncFunction('getCameraPermissionsAsync', async (): Promise<PermissionResponse> => {
        return cameraPickerPermission();
      })
      .asyncFunction('requestCameraPermissionsAsync', async (): Promise<PermissionResponse> => {
        return cameraPickerPermission();
      })
      .asyncFunction(
        'getMediaLibraryPermissionsAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.boolean().defaulted(false),
          async (_writeOnly: boolean): Promise<PermissionResponse> => mediaLibraryPermission(),
        ),
      )
      .asyncFunction(
        'requestMediaLibraryPermissionsAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.boolean().defaulted(false),
          async (_writeOnly: boolean): Promise<PermissionResponse> => mediaLibraryPermission(),
        ),
      )
      .asyncFunction('getPendingResultAsync', async (): Promise<null> => null)
      .asyncFunction(
        'launchCameraAsync',
        ExpoFunction.typed1(
          IMAGE_PICKER_OPTIONS,
          async (options: ImagePickerOptions): Promise<ImagePickerResult> => await this.launch(options, true),
        ),
      )
      .asyncFunction(
        'launchImageLibraryAsync',
        ExpoFunction.typed1(
          IMAGE_PICKER_OPTIONS,
          async (options: ImagePickerOptions): Promise<ImagePickerResult> => await this.launch(options, false),
        ),
      )
      .onPrepareForReload(async (): Promise<void> => {
        this.dispose();
      })
      .onAbilityDestroy((): void => {
        this.dispose();
      })
      .onWindowStageWillDestroy((): void => {
        this.cancelCrop?.();
      })
      .onDestroy((): void => {
        this.dispose();
      });
  }

  private async launch(options: ImagePickerOptions, capture: boolean): Promise<ImagePickerResult> {
    this.assertActive();

    const ability = this.context.uiAbilityContext;
    if (pickers.has(ability)) return new ImagePickerResult();

    this.assertActive(true);

    if (options.exif) {
      options.includeLocation = this.context.permissionStatus(MEDIA_LOCATION_PERMISSION) === ExpoPermissionStatus.GRANTED;
    }

    pickers.add(ability);
    const assets: ImagePickerAsset[] = [];

    try {
      if (capture) {
        const asset = await this.captureAsset(ability, options);
        if (asset !== undefined) assets.push(asset);
      } else {
        await this.selectAssets(ability, options, assets);
      }

      this.assertActive();

      return new ImagePickerResult(assets);
    } catch (cause) {
      await removeAssets(assets);
      this.assertActive();

      if (cause instanceof ExpoImagePickerError) throw new ExpoImagePickerError(cause.code, cause.message, cause.cause);

      throw new ExpoImagePickerError('ERR_IMAGE_PICKER', `Unable to ${capture ? 'capture' : 'select'} media: ${String(cause)}`, cause as Object);
    } finally {
      pickers.delete(ability);
    }
  }

  private async captureAsset(ability: common.UIAbilityContext, options: ImagePickerOptions): Promise<ImagePickerAsset | undefined> {
    if (!hasCameraPicker()) {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER_UNAVAILABLE', 'CameraPicker is unavailable on this device.');
    }

    const video = selectsVideos(options) && !selectsImages(options);
    // CameraPicker reads whole seconds, with 0 meaning unlimited.
    const duration = video ? Math.floor(options.videoMaxDuration) : 0;
    if (video && ((duration === 0 && options.videoMaxDuration > 0) || duration > CAMERA_MAX_VIDEO_DURATION)) {
      throw new ExpoImagePickerError('ERR_INVALID_ARGUMENT', 'videoMaxDuration must be 0 or at least 1 second and fit in a signed 32-bit integer.');
    }

    const file = await createCapture(this.context.cachePath, video ? 'video' : 'image');

    try {
      this.assertActive(true);

      const mediaType = video ? cameraPicker.PickerMediaType.VIDEO : cameraPicker.PickerMediaType.PHOTO;
      const request = cameraPicker.pick(ability, [mediaType], {
        cameraPosition: options.cameraType === 'front' ? camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: file.uri,
        videoDuration: duration,
      });

      // The native API can return no Promise when it cannot start the system ability.
      if (request == null) {
        throw new ExpoImagePickerError('ERR_IMAGE_PICKER_UNAVAILABLE', 'HarmonyOS could not start the system CameraPicker.');
      }

      const result = await request;
      this.assertActive();
      if (result == null) {
        throw new ExpoImagePickerError('ERR_IMAGE_PICKER_CAMERA', 'CameraPicker did not return a capture result.');
      }

      // CameraPicker uses -1 for both back/cancel and unsuccessful captures.
      if (result.resultCode === CAMERA_RESULT_CANCELLED) return undefined;

      if (result.resultCode !== CAMERA_RESULT_OK || result.resultUri !== file.uri || result.mediaType !== mediaType) {
        throw new ExpoImagePickerError('ERR_IMAGE_PICKER_CAMERA', 'CameraPicker returned an invalid capture result.');
      }

      return video ? await exportVideo(file.path, this.context.cachePath) : await this.processImage(ability, file.path, options);
    } finally {
      await removeCapture(file);
    }
  }

  private async selectAssets(
    ability: common.UIAbilityContext,
    options: ImagePickerOptions,
    assets: ImagePickerAsset[],
  ): Promise<void> {
    if (!hasPhotoPicker()) {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER_UNAVAILABLE', 'PhotoViewPicker is unavailable on this device.');
    }

    const livePhotos = !allowsCrop(options) && options.mediaTypes.includes('livePhotos');
    const images = livePhotos ? options.mediaTypes.includes('images') : selectsImages(options);
    const videos = selectsVideos(options);

    const config = new photoAccessHelper.PhotoSelectOptions();

    if (videos) {
      config.MIMEType = images || livePhotos
        ? photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE
        : photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
    } else {
      config.MIMEType = livePhotos && !images
        ? photoAccessHelper.PhotoViewMIMETypes.MOVING_PHOTO_IMAGE_TYPE
        : photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    }

    if (deviceInfo.sdkApiVersion >= MOVING_PHOTO_BADGE_API) {
      if (livePhotos) {
        config.isMovingPhotoBadgeShown = true;
        if (videos && !images) {
          // This union cannot be expressed with a single MIMEType.
          config.assetFilter = [
            { operationType: photoAccessHelper.OperationType.BEGIN_WRAP },
            { operationType: photoAccessHelper.OperationType.EQUAL_TO, field: photoAccessHelper.PhotoKeys.PHOTO_TYPE,
              value: [photoAccessHelper.PhotoType.VIDEO] },
            { operationType: photoAccessHelper.OperationType.OR },
            { operationType: photoAccessHelper.OperationType.EQUAL_TO, field: photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE,
              value: [photoAccessHelper.PhotoSubtype.MOVING_PHOTO] },
            { operationType: photoAccessHelper.OperationType.END_WRAP },
          ];
        }
      }
    }

    const limit = options.allowsMultipleSelection
      ? Math.min(options.selectionLimit || PHOTO_PICKER_MAX_SELECTION, PHOTO_PICKER_MAX_SELECTION)
      : 1;
    config.maxSelectNumber = limit;
    this.configureRepresentationAndOrder(config, options, limit);

    config.isEditSupported = false;
    config.isPhotoTakingSupported = false;
    config.isOriginalSupported = true;

    const result = await new photoAccessHelper.PhotoViewPicker().select(config);
    this.assertActive();

    if (result == null || !Array.isArray(result.photoUris)) {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER', 'PhotoViewPicker did not return a selection result.');
    }
    if (result.photoUris.length === 0) return;

    let movingPhotos: boolean[] | undefined;
    if (deviceInfo.sdkApiVersion >= MOVING_PHOTO_BADGE_API) {
      if (livePhotos) {
        const states = result.movingPhotoBadgeStates;
        if (states?.length === result.photoUris.length) {
          movingPhotos = states.map((state): boolean => state === photoAccessHelper.MovingPhotoBadgeStateType.MOVING_PHOTO_ENABLED);
        }
      }
    }

    const helper = photoAccessHelper.getPhotoAccessHelper(ability);

    try {
      // Gallery can return every frame in a burst even when the picker limit is one.
      for (let index = 0; index < result.photoUris.length && assets.length < limit; index++) {
        const asset = await this.readAsset(ability, helper, result.photoUris[index], options, images, livePhotos, movingPhotos?.[index]);

        if (asset !== undefined) {
          assets.push(asset);
        } else if (allowsCrop(options)) {
          return;
        }

        this.assertActive();
      }
    } finally {
      await helper.release().catch((): void => {});
    }
  }

  private configureRepresentationAndOrder(
    config: photoAccessHelper.PhotoSelectOptions,
    options: ImagePickerOptions,
    limit: number,
  ): void {
    // apiAvailable itself was introduced in API 26.
    if (deviceInfo.sdkApiVersion < ADVANCED_PHOTO_PICKER_API) return;

    if (deviceInfo.apiAvailable('26.0.0')) {
      if (limit > 1 && options.orderedSelection) {
        config.isSelectionNumberVisible = true;
        config.isSelectionOrderAdjustable = true;
      }

      if (options.preferredAssetRepresentationMode === 'current') {
        config.assetCompatibleCapability = {
          supportedHighResolution: true,
          supportedMimeType: ['image/heic'],
        };
        config.preferredCompatibleMode = photoAccessHelper.PreferredCompatibleMode.CURRENT;
      } else if (options.preferredAssetRepresentationMode === 'compatible') {
        config.preferredCompatibleMode = photoAccessHelper.PreferredCompatibleMode.COMPATIBLE;
      }
    }
  }

  private async processImage(
    ability: common.UIAbilityContext,
    uri: string,
    options: ImagePickerOptions,
    name?: string,
  ): Promise<ImagePickerAsset | undefined> {
    if (!allowsCrop(options)) return await exportImage(uri, this.context.cachePath, options, name);

    const crop = await cropImage(ability, uri, this.context.cachePath, options, (cancel): void => {
      this.cancelCrop = cancel;
    }).finally((): void => {
      this.cancelCrop = undefined;
    });
    if (crop === null) return undefined;

    try {
      this.assertActive();
      return await exportImage(uri, this.context.cachePath, options, name, crop);
    } finally {
      await crop.release().catch((): void => {});
    }
  }

  private async readAsset(
    ability: common.UIAbilityContext,
    helper: photoAccessHelper.PhotoAccessHelper,
    uri: string,
    options: ImagePickerOptions,
    images: boolean,
    livePhotos: boolean,
    movingPhotoSelected?: boolean,
  ): Promise<ImagePickerAsset | undefined> {
    if (typeof uri !== 'string' || uri.length === 0) {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER', 'PhotoViewPicker returned an invalid asset URI.');
    }

    // PhotoViewPicker grants access to the exact selected URI.
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);

    const fetch = await helper.getAssets({ fetchColumns: [], predicates });
    let selected: photoAccessHelper.PhotoAsset;

    try {
      selected = await fetch.getFirstObject();
    } finally {
      try {
        fetch.close();
      } catch (_) {}
    }

    this.assertActive();
    if (selected == null) {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER', 'PhotoViewPicker returned a URI without a matching asset.');
    }

    const assetId = selected.uri || null;
    const name = selected.displayName;
    let asset: ImagePickerAsset;

    if (selected.photoType === photoAccessHelper.PhotoType.IMAGE) {
      const moving = livePhotos && (movingPhotoSelected ??
        selected.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE) === photoAccessHelper.PhotoSubtype.MOVING_PHOTO);
      if (moving) {
        const photo = await this.requestMovingPhoto(selected);
        this.assertActive();

        asset = await exportMovingPhoto(photo, this.context.cachePath, options, name);
        if (asset.pairedVideoAsset !== undefined) asset.pairedVideoAsset.assetId = assetId;
      } else {
        // API 13–21 can show stills in a mixed moving-photo/video selection.
        if (!images) return undefined;

        const result = await this.processImage(ability, uri, options, name);
        if (result === undefined) return undefined;

        asset = result;
      }
    } else if (selected.photoType === photoAccessHelper.PhotoType.VIDEO) {
      if (!selectsVideos(options)) return undefined;

      asset = await exportVideo(uri, this.context.cachePath, name);
    } else {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER_MEDIA_TYPE', 'The selected asset is neither an image nor a video.');
    }

    asset.assetId = assetId;

    return asset;
  }

  private async requestMovingPhoto(asset: photoAccessHelper.PhotoAsset): Promise<photoAccessHelper.MovingPhoto> {
    const ability = this.context.uiAbilityContext;
    let requestId: string | undefined;
    let canceled = false;
    const cancelRequest = (id: string): void => {
      try {
        photoAccessHelper.MediaAssetManager.cancelRequest(ability, id).catch((): void => {});
      } catch (_) {}
    };

    try {
      return await new Promise<photoAccessHelper.MovingPhoto>((resolve, reject): void => {
        this.cancelMovingPhoto = (): void => {
          if (canceled) return;
          canceled = true;
          reject(new ExpoImagePickerError('ERR_IMAGE_PICKER_CONTEXT', 'The ImagePicker runtime was destroyed during a moving photo request.'));
          if (requestId !== undefined) cancelRequest(requestId);
        };

        let photo: photoAccessHelper.MovingPhoto | undefined;
        const handler: photoAccessHelper.MediaAssetDataHandler<photoAccessHelper.MovingPhoto> = {
          onDataPrepared: (data: photoAccessHelper.MovingPhoto): void => {
            if (canceled) return;
            if (data == null) {
              reject(new ExpoImagePickerError('ERR_IMAGE_PICKER_MEDIA_PROCESSING', 'The system did not return the selected moving photo.'));
              return;
            }

            photo = data;
            if (requestId !== undefined) resolve(data);
          },
        };
        photoAccessHelper.MediaAssetManager.requestMovingPhoto(ability, asset, {
          deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE,
        }, handler).then((id: string): void => {
          if (!id) {
            reject(new ExpoImagePickerError('ERR_IMAGE_PICKER_MEDIA_PROCESSING', 'The system did not start the moving photo request.'));
            return;
          }

          requestId = id;
          if (canceled) cancelRequest(id);
          else if (photo !== undefined) resolve(photo);
        }).catch((cause: Object): void => {
          reject(new ExpoImagePickerError('ERR_IMAGE_PICKER_MEDIA_PROCESSING', 'Failed to request the selected moving photo.', cause));
        });
      });
    } finally {
      this.cancelMovingPhoto = undefined;
    }
  }

  private dispose(): void {
    this.destroyed = true;
    this.cancelMovingPhoto?.();
    this.cancelCrop?.();
  }

  private assertActive(foreground: boolean = false): void {
    if (this.destroyed || !this.context.isValid || this.context.isHeadless) {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER_CONTEXT', 'ImagePicker requires an active UIAbility and Expo runtime.');
    }

    // A picker can background its host while delivering a result; only launching needs the foreground.
    if (foreground && this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER_CONTEXT', 'ImagePicker requires a foreground UIAbility to launch.');
    }
  }
}
