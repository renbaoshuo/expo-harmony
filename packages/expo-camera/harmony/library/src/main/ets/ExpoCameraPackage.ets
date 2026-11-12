/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  fileUriFromPath,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoPermissionStatus,
  ExpoSharedObjectClassDefinition,
  ExpoSharedRef,
  ExpoValueType,
  ExpoValueTypes,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import { ImageLoaderInterfaceKey } from '@expo-harmony/expo-image-loader';
import { Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';
import { media } from '@kit.MediaKit';
import { detectBarcode, scanBarcode } from '@kit.ScanKit';
import deviceInfo from '@ohos.deviceInfo';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import { BarcodeResult, barcodeResult, SCAN_CAPABILITY, scanTypes } from './ExpoCameraBarcode';
import { ExpoCameraError } from './ExpoCameraError';
import { ensureDirectory, packPicture, readBuffer, uniquePath } from './ExpoCameraFiles';
import { encodeExifMetadata } from './ExpoCameraExif';
import { BarcodeScannerSettings, buildExpoCameraView, ExpoCameraViewState, PictureOptions, RecordingOptions } from './ExpoCameraView';

const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
// Scan Kit BusinessError: the user cancelled the system scanner UI.
const SCANNER_CANCELLED_ERROR_CODE: number = 1000500002;

interface SavePictureOptions {
  quality?: number;
  base64?: boolean;
  metadata?: Record<string, ESObject>;
}

type ScannerOptions = BarcodeScannerSettings;

function requireRecord(value: ESObject, path: string): Record<string, ESObject> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected an object, received ${value === null ? 'null' : typeof value}.`);
  }
  return value as Record<string, ESObject>;
}

function optionalField<Value>(record: Record<string, ESObject>, key: string, type: ExpoValueType<Value>, path: string): Value | undefined {
  const value: ESObject = record[key];
  return value === undefined ? undefined : type.decode(value, `${path}.${key}`);
}

function inputRecordType<Value>(name: string, decode: (record: Record<string, ESObject>, path: string) => Value): ExpoValueType<Value> {
  return new ExpoValueType<Value>(
    name,
    (value: ESObject, path: string): Value => decode(requireRecord(value, path), path),
    (value: Value): ESObject => value as ESObject,
  );
}

const COPY_RECORD_TYPE: ExpoValueType<Record<string, ESObject>> = inputRecordType(
  'plain object',
  (record: Record<string, ESObject>): Record<string, ESObject> => record,
);
const STRING_ARRAY_TYPE = ExpoValueTypes.array(ExpoValueTypes.string());
const SAVE_PICTURE_OPTIONS_TYPE: ExpoValueType<SavePictureOptions> = inputRecordType(
  'SavePictureOptions',
  (record: Record<string, ESObject>, path: string): SavePictureOptions => ({
    quality: optionalField(record, 'quality', ExpoValueTypes.number(), path),
    base64: optionalField(record, 'base64', ExpoValueTypes.boolean(), path),
    metadata: optionalField(record, 'metadata', COPY_RECORD_TYPE, path),
  }),
);
const PICTURE_OPTIONS_TYPE: ExpoValueType<PictureOptions> = inputRecordType(
  'PictureOptions',
  (record: Record<string, ESObject>, path: string): PictureOptions => ({
    quality: optionalField(record, 'quality', ExpoValueTypes.number(), path),
    base64: optionalField(record, 'base64', ExpoValueTypes.boolean(), path),
    exif: optionalField(record, 'exif', ExpoValueTypes.boolean(), path),
    additionalExif: optionalField(record, 'additionalExif', COPY_RECORD_TYPE, path),
    id: optionalField(record, 'id', ExpoValueTypes.number(), path),
    fastMode: optionalField(record, 'fastMode', ExpoValueTypes.boolean(), path),
    mirror: optionalField(record, 'mirror', ExpoValueTypes.boolean(), path),
    skipProcessing: optionalField(record, 'skipProcessing', ExpoValueTypes.boolean(), path),
    imageType: optionalField(record, 'imageType', ExpoValueTypes.string(), path),
    pictureRef: optionalField(record, 'pictureRef', ExpoValueTypes.boolean(), path),
    shutterSound: optionalField(record, 'shutterSound', ExpoValueTypes.boolean(), path),
    maxDownsampling: optionalField(record, 'maxDownsampling', ExpoValueTypes.number(), path),
  }),
);
const RECORDING_OPTIONS_TYPE: ExpoValueType<RecordingOptions> = inputRecordType(
  'RecordingOptions',
  (record: Record<string, ESObject>, path: string): RecordingOptions => ({
    maxDuration: optionalField(record, 'maxDuration', ExpoValueTypes.number(), path),
    maxFileSize: optionalField(record, 'maxFileSize', ExpoValueTypes.number(), path),
    mirror: optionalField(record, 'mirror', ExpoValueTypes.boolean(), path),
    codec: optionalField(record, 'codec', ExpoValueTypes.string(), path),
  }),
);
const SCANNER_OPTIONS_TYPE: ExpoValueType<ScannerOptions> = inputRecordType(
  'ScannerOptions',
  (record: Record<string, ESObject>, path: string): ScannerOptions => ({
    barcodeTypes: optionalField(record, 'barcodeTypes', STRING_ARRAY_TYPE, path),
  }),
);

class CameraPictureRef extends ExpoSharedRef<image.PixelMap> {
  readonly width: number;
  readonly height: number;
  private readonly saveBody: (pixel: image.PixelMap, options: SavePictureOptions) => Promise<SavedPicture>;

  constructor(
    context: ExpoModuleContext,
    pixel: image.PixelMap,
    width: number,
    height: number,
    saveBody: (pixel: image.PixelMap, options: SavePictureOptions) => Promise<SavedPicture>,
  ) {
    super(context, 'image', pixel);
    this.width = width;
    this.height = height;
    this.saveBody = saveBody;
  }

  async savePictureAsync(options: SavePictureOptions): Promise<SavedPicture> {
    return await this.saveBody(this.value, options);
  }

  override sharedObjectWillRelease(): void {
    this.value.release().catch((): void => {});
  }
}

class SavedPicture {
  uri: string;
  width: number;
  height: number;
  base64?: string;

  constructor(uri: string, width: number, height: number) {
    this.uri = uri;
    this.width = width;
    this.height = height;
  }
}

async function writeMetadata(path: string, metadata?: Record<string, ESObject>): Promise<void> {
  const records = encodeExifMetadata(metadata);
  if (Object.keys(records).length === 0) return;

  const source = image.createImageSource(path);
  try {
    await source.modifyImageProperties(records);
  } finally {
    await source.release();
  }
}

class PermissionRecord {
  status: string;
  granted: boolean;
  expires: string = 'never';
  canAskAgain: boolean;

  constructor(status: string, canAskAgain: boolean) {
    this.status = status;
    this.granted = status === 'granted';
    this.canAskAgain = canAskAgain;
  }
}

export class ExpoCameraModule extends ExpoModule {
  private readonly mountedViews: Set<ExpoCameraViewState> = new Set<ExpoCameraViewState>();

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const pictureClass = new ExpoSharedObjectClassDefinition<CameraPictureRef>('Picture')
      .sharedRef('image')
      .property('width', ExpoValueTypes.number(), (picture: CameraPictureRef): number => picture.width)
      .property('height', ExpoValueTypes.number(), (picture: CameraPictureRef): number => picture.height)
      .asyncFunction(
        'savePictureAsync',
        ExpoFunction.ownedTyped1(
          SAVE_PICTURE_OPTIONS_TYPE.defaulted({}),
          async (picture: CameraPictureRef, options: SavePictureOptions): Promise<SavedPicture> => await picture.savePictureAsync(options),
        ),
      );

    const cameraView = new ExpoViewDefinition<ExpoCameraViewState>(
      'Default',
      (viewContext: ExpoViewContext): ExpoCameraViewState =>
        new ExpoCameraViewState(
          viewContext,
          (pixel: image.PixelMap, width: number, height: number): CameraPictureRef =>
            pictureClass.instance(
              new CameraPictureRef(
                this.context,
                pixel,
                width,
                height,
                async (picturePixel: image.PixelMap, options: SavePictureOptions): Promise<SavedPicture> =>
                  await this.savePicture(picturePixel, options),
              ),
            ),
        ),
      wrapBuilder(buildExpoCameraView),
    )
      .prop(
        'facing',
        ExpoValueTypes.string(),
        (view: ExpoCameraViewState, value: string): void => {
          view.setFacing(value);
        },
        'back',
      )
      .prop(
        'flashMode',
        ExpoValueTypes.string(),
        (view: ExpoCameraViewState, value: string): void => {
          view.setFlashMode(value);
        },
        'off',
      )
      .prop(
        'selectedLens',
        ExpoValueTypes.string().nullable(),
        (view: ExpoCameraViewState, value: string | null): void => view.setSelectedLens(value),
        null,
      )
      .prop(
        'enableTorch',
        ExpoValueTypes.boolean(),
        (view: ExpoCameraViewState, value: boolean): void => {
          view.setEnableTorch(value);
        },
        false,
      )
      .prop(
        'pictureSize',
        ExpoValueTypes.string().nullable(),
        (view: ExpoCameraViewState, value: string | null): void => view.setPictureSize(value),
        null,
      )
      .prop(
        'zoom',
        ExpoValueTypes.number(),
        (view: ExpoCameraViewState, value: number): void => {
          view.setZoom(value);
        },
        0,
      )
      .prop(
        'mode',
        ExpoValueTypes.string(),
        (view: ExpoCameraViewState, value: string): void => {
          view.setMode(value);
        },
        'picture',
      )
      .prop(
        'barcodeScannerEnabled',
        ExpoValueTypes.boolean(),
        (view: ExpoCameraViewState, value: boolean): void => view.setBarcodeScannerEnabled(value),
        false,
      )
      .prop(
        'barcodeScannerSettings',
        SCANNER_OPTIONS_TYPE.nullable(),
        (view: ExpoCameraViewState, value: ScannerOptions | null): void => view.setBarcodeScannerSettings(value),
        null,
      )
      .prop(
        'mute',
        ExpoValueTypes.boolean(),
        (view: ExpoCameraViewState, value: boolean): void => {
          view.setMute(value);
        },
        false,
      )
      .prop('animateShutter', ExpoValueTypes.boolean(), (view: ExpoCameraViewState, value: boolean): void => view.setAnimateShutter(value), true)
      .prop(
        'videoQuality',
        ExpoValueTypes.string(),
        (view: ExpoCameraViewState, value: string): void => {
          view.setVideoQuality(value);
        },
        '1080p',
      )
      .prop(
        'videoStabilizationMode',
        ExpoValueTypes.string().nullable(),
        (view: ExpoCameraViewState, value: string | null): void => view.setVideoStabilizationMode(value),
        null,
      )
      .prop(
        'autoFocus',
        ExpoValueTypes.string(),
        (view: ExpoCameraViewState, value: string): void => {
          view.setAutoFocus(value);
        },
        'off',
      )
      .prop(
        'responsiveOrientationWhenOrientationLocked',
        ExpoValueTypes.boolean(),
        (view: ExpoCameraViewState, value: boolean): void => view.setResponsiveOrientation(value),
        false,
      )
      .prop(
        'mirror',
        ExpoValueTypes.boolean(),
        (view: ExpoCameraViewState, value: boolean): void => {
          view.setMirror(value);
        },
        false,
      )
      .prop(
        'active',
        ExpoValueTypes.boolean(),
        (view: ExpoCameraViewState, value: boolean): void => {
          view.setActive(value);
        },
        true,
      )
      .prop(
        'videoBitrate',
        ExpoValueTypes.number().nullable(),
        (view: ExpoCameraViewState, value: number | null): void => view.setVideoBitrate(value),
        null,
      )
      .prop('ratio', ExpoValueTypes.string().nullable(), (view: ExpoCameraViewState, value: string | null): void => view.setRatio(value), null)
      .events(['onCameraReady', 'onMountError', 'onPictureSaved', 'onBarcodeScanned', 'onResponsiveOrientationChanged', 'onAvailableLensesChanged'])
      .asyncFunction(
        'takePicture',
        ExpoFunction.ownedTyped1(
          PICTURE_OPTIONS_TYPE.defaulted({}),
          async (view: ExpoCameraViewState, options: PictureOptions): Promise<ESObject> => await view.takePictureAsync(options),
        ),
      )
      .asyncFunction(
        'getAvailablePictureSizes',
        ExpoFunction.ownedTyped0(async (view: ExpoCameraViewState): Promise<string[]> => await view.getAvailablePictureSizesAsync()).returns(
          STRING_ARRAY_TYPE,
        ),
      )
      .asyncFunction(
        'getAvailableLenses',
        ExpoFunction.ownedTyped0(async (view: ExpoCameraViewState): Promise<string[]> => await view.getAvailableLensesAsync()).returns(
          STRING_ARRAY_TYPE,
        ),
      )
      .asyncFunction(
        'record',
        ExpoFunction.ownedTyped1(
          RECORDING_OPTIONS_TYPE.defaulted({}),
          async (view: ExpoCameraViewState, options: RecordingOptions): Promise<ESObject> => await view.recordAsync(options),
        ),
      )
      .asyncFunction(
        'toggleRecording',
        ExpoFunction.ownedTyped0(async (view: ExpoCameraViewState): Promise<ESObject> => await view.toggleRecordingAsync()),
      )
      .asyncFunction(
        'stopRecording',
        ExpoFunction.ownedTyped0(async (view: ExpoCameraViewState): Promise<ESObject> => await view.stopRecordingAsync()),
      )
      .asyncFunction(
        'resumePreview',
        ExpoFunction.ownedTyped0(async (view: ExpoCameraViewState): Promise<ESObject> => await view.resumePreviewAsync()),
      )
      .asyncFunction(
        'pausePreview',
        ExpoFunction.ownedTyped0(async (view: ExpoCameraViewState): Promise<ESObject> => await view.pausePreviewAsync()),
      )
      .asyncFunction(
        'launchModernScanner',
        ExpoFunction.ownedTyped0(async (view: ExpoCameraViewState): Promise<ESObject> => await view.launchModernScannerAsync()),
      )
      .onCreate((view: ExpoCameraViewState): void => {
        this.mountedViews.add(view);
      })
      .onDidUpdateProps((view: ExpoCameraViewState): void => view.commitProps())
      .onDestroy((view: ExpoCameraViewState): void => {
        this.mountedViews.delete(view);
        view.destroy();
      });

    return new ExpoModuleDefinition()
      .name('ExpoCamera')
      .constant('Type', { front: 'front', back: 'back' })
      .constant('FlashMode', { off: 'off', on: 'on', auto: 'auto', screen: 'screen' })
      .property('isModernBarcodeScannerAvailable', ExpoValueTypes.boolean(), (): boolean => canIUse(SCAN_CAPABILITY))
      .property('toggleRecordingAsyncAvailable', ExpoValueTypes.boolean(), (): boolean => true)
      .events(['onModernBarcodeScanned'])
      .sharedObjectClass(pictureClass)
      .asyncFunction(
        'isAvailableAsync',
        ExpoFunction.typed0(
          async (): Promise<boolean> => camera.getCameraManager(this.context.uiAbilityContext).getSupportedCameras().length > 0,
        ).returns(ExpoValueTypes.boolean()),
      )
      .asyncFunction('getCameraPermissionsAsync', async (): Promise<PermissionRecord> => this.getPermission(CAMERA_PERMISSION))
      .asyncFunction('requestCameraPermissionsAsync', async (): Promise<PermissionRecord> => await this.requestPermission(CAMERA_PERMISSION))
      .asyncFunction('getMicrophonePermissionsAsync', async (): Promise<PermissionRecord> => this.getPermission(MICROPHONE_PERMISSION))
      .asyncFunction('requestMicrophonePermissionsAsync', async (): Promise<PermissionRecord> => await this.requestPermission(MICROPHONE_PERMISSION))
      .asyncFunction(
        'getAvailableVideoCodecsAsync',
        ExpoFunction.typed0(async (): Promise<string[]> => await this.getAvailableVideoCodecs()).returns(STRING_ARRAY_TYPE),
      )
      .asyncFunction(
        'scanFromURLAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          STRING_ARRAY_TYPE.optional(),
          async (uri: string, types?: string[]): Promise<BarcodeResult[]> => await this.scanFromURL(uri, types),
        ),
      )
      .asyncFunction(
        'launchScanner',
        ExpoFunction.typed1(SCANNER_OPTIONS_TYPE.defaulted({}), async (options: ScannerOptions): Promise<void> => {
          const result: BarcodeResult = await this.launchScanner(options);
          this.sendEvent('onModernBarcodeScanned', result);
        }),
      )
      .asyncFunction('dismissScanner', async (): Promise<null> => {
        throw new ExpoCameraError(
          'ERR_CAMERA_SCANNER_DISMISS_UNSUPPORTED',
          'HarmonyOS Scan Kit does not expose programmatic dismissal for its system scanner UI.',
        );
      })
      .view(cameraView)
      .onBackground((): void => {
        this.mountedViews.forEach((view: ExpoCameraViewState): void => view.onBackground());
      })
      .onForeground((): void => {
        this.mountedViews.forEach((view: ExpoCameraViewState): void => view.onForeground());
      })
      .onDestroy((): void => {
        this.mountedViews.forEach((view: ExpoCameraViewState): void => view.destroy());
        this.mountedViews.clear();
      });
  }

  private getPermission(permission: Permissions): PermissionRecord {
    const status = this.context.permissionStatus(permission);
    if (status === ExpoPermissionStatus.GRANTED) return new PermissionRecord('granted', true);
    if (status === ExpoPermissionStatus.NOT_DETERMINED) return new PermissionRecord('undetermined', true);
    // Older SDKs cannot distinguish a first request from a permanent denial.
    return new PermissionRecord('denied', deviceInfo.sdkApiVersion < 20);
  }

  private async requestPermission(permission: Permissions): Promise<PermissionRecord> {
    try {
      await this.context.requestPermissions([permission]);

      return this.getPermission(permission);
    } catch (error) {
      console.error(`Expo Camera permission request failed: ${String(error)}`);

      throw new ExpoCameraError('ERR_CAMERA_PERMISSION_REQUEST', 'The camera permission request could not be completed.');
    }
  }

  private async getAvailableVideoCodecs(): Promise<string[]> {
    const recorder = await media.createAVRecorder();

    try {
      const encoders = await recorder.getAvailableEncoder();
      const codecs: string[] = [];

      if (encoders.some((encoder: media.EncoderInfo): boolean => encoder.type === 'video' && encoder.mimeType === media.CodecMimeType.VIDEO_AVC))
        codecs.push('avc1');
      if (encoders.some((encoder: media.EncoderInfo): boolean => encoder.type === 'video' && encoder.mimeType === media.CodecMimeType.VIDEO_HEVC))
        codecs.push('hvc1');

      return codecs;
    } finally {
      await recorder.release();
    }
  }

  private async scanFromURL(url: string, types?: string[]): Promise<BarcodeResult[]> {
    if (url.length === 0) throw new ExpoCameraError('ERR_CAMERA_INVALID_URL', 'The barcode image URL is empty.');
    if (!canIUse(SCAN_CAPABILITY)) {
      throw new ExpoCameraError('ERR_CAMERA_SCANNER_UNAVAILABLE', 'Barcode scanning is not supported on this device.');
    }

    const formats = scanTypes(types ?? ['qr'], false);
    if (formats.length === 0) return [];

    let path: string | undefined;

    try {
      const loader = this.context.services.require(ImageLoaderInterfaceKey);
      const pixel = await loader.loadImageForManipulationFromURL(url);
      try {
        this.context.assertActive();

        const dir = `${this.context.cachePath}/expo-camera`;
        await ensureDirectory(dir);
        this.context.assertActive();

        // Scan Kit requires the pixels to be staged at a local URI.
        path = uniquePath(dir, 'barcode', 'png');
        await packPicture(path, pixel, { format: 'image/png', quality: 100 });
      } finally {
        await pixel.release().catch((): void => {});
      }

      this.context.assertActive();
      const results = await detectBarcode.decode({ uri: fileUriFromPath(path) }, { scanTypes: formats });
      this.context.assertActive();

      return results.map((result: scanBarcode.ScanResult): BarcodeResult => barcodeResult(result));
    } catch (error) {
      if (error instanceof ExpoModuleError) throw new ExpoModuleError(error.code, error.message, error.cause, error.path);

      console.error(`Expo Camera barcode scan failed: ${String(error)}`);
      throw new ExpoCameraError('ERR_CAMERA_BARCODE_SCAN', 'The barcode image could not be scanned.');
    } finally {
      if (path !== undefined) {
        try {
          fs.unlinkSync(path);
        } catch (_) {}
      }
    }
  }

  private async launchScanner(options: ScannerOptions = {}): Promise<BarcodeResult> {
    if (!canIUse(SCAN_CAPABILITY)) {
      throw new ExpoCameraError('ERR_CAMERA_SCANNER_UNAVAILABLE', 'The modern barcode scanner is not supported on this device.');
    }

    try {
      const result = await scanBarcode.startScanForResult(this.context.uiAbilityContext, {
        scanTypes: scanTypes(options.barcodeTypes),
      });

      return barcodeResult(result);
    } catch (error) {
      console.error(`Expo Camera barcode scanner failed: ${String(error)}`);
      const code = (error as BusinessError).code;
      if (code === SCANNER_CANCELLED_ERROR_CODE) {
        throw new ExpoCameraError('ERR_CAMERA_SCANNER_CANCELLED', 'The barcode scanner was cancelled.');
      }

      throw new ExpoCameraError('ERR_CAMERA_SCANNER', 'The barcode scanner could not complete.');
    }
  }

  private async savePicture(pixel: image.PixelMap, options: SavePictureOptions = {}): Promise<SavedPicture> {
    if (options.quality !== undefined && (!Number.isFinite(options.quality) || options.quality < 0 || options.quality > 1)) {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', 'Photo quality must be a number between 0 and 1.');
    }

    let path: string | undefined;
    let saved = false;

    try {
      const info = await pixel.getImageInfo();
      const dir = `${this.context.cachePath}/expo-camera`;
      await ensureDirectory(dir);
      path = uniquePath(dir, 'picture-ref', 'jpg');

      await packPicture(path, pixel, {
        format: 'image/jpeg',
        quality: Math.round((options.quality ?? 1) * 100),
        needsPackProperties: options.metadata !== undefined,
      });
      await writeMetadata(path, options.metadata);

      const result = new SavedPicture(fileUriFromPath(path), info.size.width, info.size.height);
      if (options.base64 === true) {
        const bytes = await readBuffer(path);
        result.base64 = await new util.Base64Helper().encodeToString(new Uint8Array(bytes));
      }

      saved = true;
      return result;
    } finally {
      if (!saved && path !== undefined) {
        try {
          fs.unlinkSync(path);
        } catch (_) {}
      }
    }
  }
}
