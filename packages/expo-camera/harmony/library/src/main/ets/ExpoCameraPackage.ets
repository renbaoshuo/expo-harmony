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
  ExpoRecordShape,
  ExpoSharedObjectClassDefinition,
  ExpoSharedRef,
  ExpoValueType,
  ExpoValueTypes,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import { ImageLoaderInterfaceKey } from '@expo-harmony/expo-image-loader';
import { Permissions } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { BarcodeResult, barcodeResult, SCAN_CAPABILITY, scanTypes } from './ExpoCameraBarcode';
import { ExpoCameraError } from './ExpoCameraError';
import { ensureDirectory, packPicture, readBuffer, uniquePath } from './ExpoCameraFiles';
import { encodeExifMetadata } from './ExpoCameraExif';
import { BarcodeScannerSettings, buildExpoCameraView, ExpoCameraViewState, PictureOptions, RecordingOptions } from './ExpoCameraView';

const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const CAMERA_CAPABILITY = 'SystemCapability.Multimedia.Camera.Core';
const RECORDER_CAPABILITY = 'SystemCapability.Multimedia.Media.AVRecorder';

interface SavePictureOptions {
  quality?: number;
  base64?: boolean;
  metadata?: Record<string, ESObject>;
}

type ScannerOptions = BarcodeScannerSettings;

function optionsType<Value>(name: string, shape: ExpoRecordShape): ExpoValueType<Value> {
  return ExpoValueTypes.shapedRecord<Value>(
    name,
    shape,
    (fields: Record<string, ESObject>): Value => fields as ESObject as Value,
    (value: Value): Record<string, ESObject> => value as ESObject as Record<string, ESObject>,
  );
}

const METADATA_TYPE = ExpoValueTypes.record(ExpoValueTypes.any());
const STRING_ARRAY_TYPE = ExpoValueTypes.array(ExpoValueTypes.string());

const SAVE_PICTURE_OPTIONS_TYPE = optionsType<SavePictureOptions>(
  'SavePictureOptions',
  new ExpoRecordShape()
    .field('quality', ExpoValueTypes.number())
    .field('base64', ExpoValueTypes.boolean())
    .field('metadata', METADATA_TYPE),
);

const PICTURE_OPTIONS_TYPE = optionsType<PictureOptions>(
  'PictureOptions',
  new ExpoRecordShape()
    .field('quality', ExpoValueTypes.number())
    .field('base64', ExpoValueTypes.boolean())
    .field('exif', ExpoValueTypes.boolean())
    .field('additionalExif', METADATA_TYPE)
    .field('id', ExpoValueTypes.number())
    .field('fastMode', ExpoValueTypes.boolean())
    .field('mirror', ExpoValueTypes.boolean())
    .field('skipProcessing', ExpoValueTypes.boolean())
    .field('imageType', ExpoValueTypes.string())
    .field('pictureRef', ExpoValueTypes.boolean())
    .field('shutterSound', ExpoValueTypes.boolean())
    .field('maxDownsampling', ExpoValueTypes.number()),
);

const RECORDING_OPTIONS_TYPE = optionsType<RecordingOptions>(
  'RecordingOptions',
  new ExpoRecordShape()
    .field('maxDuration', ExpoValueTypes.number())
    .field('maxFileSize', ExpoValueTypes.number())
    .field('mirror', ExpoValueTypes.boolean())
    .field('codec', ExpoValueTypes.string()),
);

const SCANNER_OPTIONS_TYPE = optionsType<ScannerOptions>(
  'ScannerOptions',
  new ExpoRecordShape().field('barcodeTypes', STRING_ARRAY_TYPE),
);

class CameraPictureRef extends ExpoSharedRef<image.PixelMap> {
  readonly width: number;
  readonly height: number;
  private saves = 0;
  private released = false;

  constructor(
    context: ExpoModuleContext,
    pixel: image.PixelMap,
    width: number,
    height: number,
  ) {
    super(context, 'image', pixel);
    this.width = width;
    this.height = height;
  }

  async savePictureAsync(options: SavePictureOptions): Promise<SavedPicture> {
    if (this.released) throw new ExpoCameraError('ERR_CAMERA_PICTURE_RELEASED', 'The picture reference has been released.');

    this.saves += 1;
    try {
      return await this.savePicture(options);
    } finally {
      this.saves -= 1;
      if (this.released && this.saves === 0) this.releasePixelMap();
    }
  }

  override sharedObjectWillRelease(): void {
    this.released = true;
    if (this.saves === 0) this.releasePixelMap();
  }

  private releasePixelMap(): void {
    this.value.release().catch((): void => {});
  }

  private async savePicture(options: SavePictureOptions): Promise<SavedPicture> {
    if (options.quality !== undefined && (!Number.isFinite(options.quality) || options.quality < 0 || options.quality > 1)) {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', 'Photo quality must be a number between 0 and 1.');
    }

    let path: string | undefined;
    let saved = false;

    try {
      this.context.assertActive();

      const dir = `${this.context.cachePath}/expo-camera`;
      await ensureDirectory(dir);
      path = uniquePath(dir, 'picture-ref', 'jpg');

      await packPicture(path, this.value, {
        format: 'image/jpeg',
        quality: Math.round((options.quality ?? 1) * 100),
        needsPackProperties: options.metadata !== undefined,
      });
      await writeMetadata(path, options.metadata);

      const result = new SavedPicture(fileUriFromPath(path), this.width, this.height);
      if (options.base64 === true) {
        const bytes = await readBuffer(path);
        result.base64 = await new util.Base64Helper().encodeToString(new Uint8Array(bytes));
      }

      this.context.assertActive();
      saved = true;

      return result;
    } finally {
      if (!saved && path !== undefined) await fs.unlink(path).catch((): void => {});
    }
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
            pictureClass.instance(new CameraPictureRef(this.context, pixel, width, height)),
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
        'takePictureRef',
        ExpoFunction.ownedTyped1(
          PICTURE_OPTIONS_TYPE.defaulted({}),
          async (view: ExpoCameraViewState, options: PictureOptions): Promise<ESObject> => await view.takePictureRefAsync(options),
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
        ExpoFunction.ownedTyped0(async (_view: ExpoCameraViewState): Promise<void> => await this.launchScanner()),
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
      .property('toggleRecordingAsyncAvailable', ExpoValueTypes.boolean(), (): boolean => canIUse(RECORDER_CAPABILITY))
      .events(['onModernBarcodeScanned'])
      .sharedObjectClass(pictureClass)
      .asyncFunction(
        'isAvailableAsync',
        ExpoFunction.typed0(
          async (): Promise<boolean> => canIUse(CAMERA_CAPABILITY) &&
            camera.getCameraManager(this.context.uiAbilityContext).getSupportedCameras().length > 0,
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
        ExpoFunction.typed1(SCANNER_OPTIONS_TYPE.defaulted({}), async (options: ScannerOptions): Promise<void> => await this.launchScanner(options)),
      )
      // Scan Kit owns dismissal of the system UI.
      .asyncFunction('dismissScanner', async (): Promise<void> => {})
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
    const grant = this.context.getPermissionResponse(permission);
    if (grant.status === ExpoPermissionStatus.GRANTED) return new PermissionRecord('granted', grant.canAskAgain);
    if (grant.status === ExpoPermissionStatus.NOT_DETERMINED) return new PermissionRecord('undetermined', grant.canAskAgain);
    return new PermissionRecord('denied', grant.canAskAgain);
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
    if (!canIUse(RECORDER_CAPABILITY)) return [];

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

      const results = await detectBarcode.decode({ uri: fileUri.getUriFromPath(path) }, { scanTypes: formats, enableMultiMode: true });
      this.context.assertActive();

      return results
        .filter((result: scanBarcode.ScanResult): boolean => formats.includes(result.scanType))
        .map((result: scanBarcode.ScanResult): BarcodeResult => barcodeResult(result));
    } catch (error) {
      if (error instanceof ExpoCameraError) throw new ExpoCameraError(error.code, error.message, error.cause);
      if (error instanceof ExpoModuleError) throw new ExpoModuleError(error.code, error.message, error.cause, error.path);

      console.error(`Expo Camera barcode scan failed: ${String(error)}`);

      throw new ExpoCameraError('ERR_CAMERA_BARCODE_SCAN', 'The barcode image could not be scanned.');
    } finally {
      if (path !== undefined) await fs.unlink(path).catch((): void => {});
    }
  }

  private async launchScanner(options: ScannerOptions = {}): Promise<void> {
    if (!canIUse(SCAN_CAPABILITY)) {
      throw new ExpoCameraError('ERR_CAMERA_SCANNER_UNAVAILABLE', 'The modern barcode scanner is not supported on this device.');
    }

    const formats = scanTypes(options.barcodeTypes);
    if (formats.length === 0) {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', 'The barcode scanner requires at least one supported barcode type.');
    }

    let result: scanBarcode.ScanResult;
    try {
      result = await scanBarcode.startScanForResult(this.context.uiAbilityContext, { scanTypes: formats });
    } catch (error) {
      console.error(`Expo Camera barcode scanner failed: ${String(error)}`);

      const code = (error as BusinessError).code;
      if (code === scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED) {
        throw new ExpoCameraError('ERR_CAMERA_SCANNER_CANCELLED', 'The barcode scanner was cancelled.');
      }

      throw new ExpoCameraError('ERR_CAMERA_SCANNER', 'The barcode scanner could not complete.');
    }

    this.context.assertActive();
    const barcode = barcodeResult(result, false);
    this.sendEvent('onModernBarcodeScanned', { type: barcode.type, data: barcode.data, raw: barcode.raw });
  }

}
