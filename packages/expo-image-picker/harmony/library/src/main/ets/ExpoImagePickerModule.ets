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
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { common } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ExpoImagePickerError } from './ExpoImagePickerError';
import { IMAGE_PICKER_OPTIONS, ImagePickerOptions, selectsImages, selectsVideos, validateEditing } from './ImagePickerOptions';
import { PermissionResponse, cameraPickerPermission, hasCameraPicker, mediaLibraryPermission } from './ImagePickerPermissions';
import { ImagePickerAsset, CaptureFile, removeAssets, removeCapture, createCapture, exportImage, exportMovingPhoto, exportVideo } from './ExpoImagePickerMedia';

const PHOTO_PICKER_MAX_SELECTION: number = 500;
const CAMERA_RESULT_OK: number = 0;
const CAMERA_RESULT_CANCELLED: number = -1;
const CAMERA_MAX_VIDEO_DURATION: number = 0x7fffffff;
const MOVING_PHOTO_BADGES_API: number = 22;

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

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExponentImagePicker')
      .asyncFunction('getCameraPermissionsAsync', async (): Promise<PermissionResponse> => {
        this.assertActive();
        return cameraPickerPermission();
      })
      .asyncFunction('requestCameraPermissionsAsync', async (): Promise<PermissionResponse> => {
        this.assertActive();
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
      .onDestroy((): void => {
        this.dispose();
      });
  }

  private async launch(options: ImagePickerOptions, capture: boolean): Promise<ImagePickerResult> {
    this.assertActive();

    const ability = this.context.uiAbilityContext;
    if (pickers.has(ability)) return new ImagePickerResult();

    this.assertActive(true);
    validateEditing(options, capture);

    const video = capture && selectsVideos(options) && !selectsImages(options);
    // CameraPicker reads whole seconds as a signed 32-bit value, with 0 meaning unlimited.
    const videoDuration = video ? Math.floor(options.videoMaxDuration) : 0;
    if (video && ((videoDuration === 0 && options.videoMaxDuration > 0) || videoDuration > CAMERA_MAX_VIDEO_DURATION)) {
      throw new ExpoImagePickerError('ERR_INVALID_ARGUMENT', 'videoMaxDuration must be 0 or at least 1 second and fit in a signed 32-bit integer.');
    }

    pickers.add(ability);
    const assets: ImagePickerAsset[] = [];
    let file: CaptureFile | undefined;

    try {
      if (capture) {
        if (!hasCameraPicker()) {
          throw new ExpoImagePickerError('ERR_IMAGE_PICKER_UNAVAILABLE', 'CameraPicker is unavailable on this device.');
        }

        file = await createCapture(this.context.cachePath, video ? 'video' : 'image');
        this.assertActive(true);

        const request = cameraPicker.pick(ability, [video ? cameraPicker.PickerMediaType.VIDEO : cameraPicker.PickerMediaType.PHOTO], {
          cameraPosition: options.cameraType === 'front' ? camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK,
          saveUri: file.uri,
          videoDuration,
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

        // CameraPicker reports back/cancel and an unsuccessful capture with -1.
        if (result.resultCode === CAMERA_RESULT_CANCELLED) return new ImagePickerResult();

        if (
          result.resultCode !== CAMERA_RESULT_OK ||
          result.resultUri !== file.uri ||
          result.mediaType !== (video ? cameraPicker.PickerMediaType.VIDEO : cameraPicker.PickerMediaType.PHOTO)
        ) {
          throw new ExpoImagePickerError('ERR_IMAGE_PICKER_CAMERA', 'CameraPicker returned an invalid capture result.');
        }

        assets.push(
          video ? await exportVideo(file.path, this.context.cachePath) : await exportImage(file.path, this.context.cachePath, options),
        );
        await removeCapture(file);
        file = undefined;
      } else {
        if (!canIUse('SystemCapability.FileManagement.PhotoAccessHelper.Core')) {
          throw new ExpoImagePickerError('ERR_IMAGE_PICKER_UNAVAILABLE', 'PhotoViewPicker is unavailable on this device.');
        }

        const livePhotos = !options.allowsEditing && options.mediaTypes.includes('livePhotos');
        const images = livePhotos ? options.mediaTypes.includes('images') : selectsImages(options);
        const videos = selectsVideos(options);
        const movingPhotoBadges = livePhotos && deviceInfo.sdkApiVersion >= MOVING_PHOTO_BADGES_API;
        const config = new photoAccessHelper.PhotoSelectOptions();
        config.MIMEType = videos
          ? images || livePhotos
            ? photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE
            : photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE
          : livePhotos && !images
            ? photoAccessHelper.PhotoViewMIMETypes.MOVING_PHOTO_IMAGE_TYPE
            : photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
        if (movingPhotoBadges) {
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
        config.maxSelectNumber = options.allowsMultipleSelection
          ? Math.min(options.selectionLimit || PHOTO_PICKER_MAX_SELECTION, PHOTO_PICKER_MAX_SELECTION)
          : 1;
        config.isEditSupported = options.allowsEditing && !options.allowsMultipleSelection && images;
        config.isPhotoTakingSupported = false;
        config.isOriginalSupported = true;

        const result = await new photoAccessHelper.PhotoViewPicker().select(config);
        this.assertActive();
        if (result == null || !Array.isArray(result.photoUris)) {
          throw new ExpoImagePickerError('ERR_IMAGE_PICKER', 'PhotoViewPicker did not return a selection result.');
        }

        const badges = movingPhotoBadges ? result.movingPhotoBadgeStates : undefined;

        for (let index = 0; index < result.photoUris.length; index++) {
          const badge = badges?.length === result.photoUris.length ? badges[index] : undefined;
          const asset = await this.readAsset(result.photoUris[index], options, images, livePhotos, badge);
          if (asset !== undefined) assets.push(asset);
          this.assertActive();
        }
      }

      this.assertActive();

      return new ImagePickerResult(assets);
    } catch (cause) {
      await removeAssets(assets);
      this.assertActive();

      if (cause instanceof ExpoImagePickerError) {
        throw new ExpoImagePickerError(cause.code, cause.message, cause);
      }

      throw new ExpoImagePickerError('ERR_IMAGE_PICKER', `Unable to ${capture ? 'capture' : 'select'} media: ${String(cause)}`, cause as Object);
    } finally {
      if (file !== undefined) await removeCapture(file);
      pickers.delete(ability);
    }
  }

  private async readAsset(
    uri: string,
    options: ImagePickerOptions,
    images: boolean,
    livePhotos: boolean,
    badge?: photoAccessHelper.MovingPhotoBadgeStateType,
  ): Promise<ImagePickerAsset | undefined> {
    if (typeof uri !== 'string' || uri.length === 0) {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER', 'PhotoViewPicker returned an invalid asset URI.');
    }

    const helper = photoAccessHelper.getPhotoAccessHelper(this.context.uiAbilityContext);
    let fetch: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined;
    let selected: photoAccessHelper.PhotoAsset;

    try {
      const predicates = new dataSharePredicates.DataSharePredicates();
      // PhotoViewPicker grants temporary access to this exact URI.
      predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);

      fetch = await helper.getAssets({ fetchColumns: [photoAccessHelper.PhotoKeys.DISPLAY_NAME], predicates });
      selected = await fetch.getFirstObject();
    } finally {
      try {
        fetch?.close();
      } finally {
        await helper.release();
      }
    }

    this.assertActive();
    if (selected == null) {
      throw new ExpoImagePickerError('ERR_IMAGE_PICKER', 'PhotoViewPicker returned a URI without a matching asset.');
    }

    const assetId = selected.uri || null;
    const name = selected.displayName;
    let asset: ImagePickerAsset;
    if (selected.photoType === photoAccessHelper.PhotoType.IMAGE) {
      const moving = livePhotos && (badge === undefined
        ? selected.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE) === photoAccessHelper.PhotoSubtype.MOVING_PHOTO
        : badge === photoAccessHelper.MovingPhotoBadgeStateType.MOVING_PHOTO_ENABLED);
      if (moving) {
        const photo = await this.requestMovingPhoto(selected);
        this.assertActive();

        asset = await exportMovingPhoto(photo, this.context.cachePath, options, name);
        if (asset.pairedVideoAsset !== undefined) asset.pairedVideoAsset.assetId = assetId;
      } else {
        // Before API 22 the mixed moving-photo/video picker also shows stills.
        if (livePhotos && !images) return undefined;
        asset = await exportImage(uri, this.context.cachePath, options, name);
      }
    } else if (selected.photoType === photoAccessHelper.PhotoType.VIDEO) {
      if (livePhotos && !selectsVideos(options)) return undefined;
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
