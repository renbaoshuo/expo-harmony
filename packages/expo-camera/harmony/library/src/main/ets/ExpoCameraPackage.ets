import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNComponentContext, RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceRegistry, ExpoViewAdapter, ExpoViewAdapterRegistry, ExpoViewContentContext } from '@expo-harmony/expo-modules-core';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';
import { media } from '@kit.MediaKit';
import { http } from '@kit.NetworkKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import { ExpoCameraError } from './ExpoCameraError';
import { encodeExifMetadata } from './ExpoCameraExif';
import { buildExpoCameraView, ExpoCameraViewRegistry, ExpoCameraViewState } from './ExpoCameraView';

const SERVICE_NAME: string = 'ExpoCameraService';
const COMPONENT_NAME: string = 'ViewManagerAdapter_ExpoCamera';
const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const SCAN_CAPABILITY: string = 'SystemCapability.Multimedia.Scan.ScanBarcode';
const BARCODE_IMAGE_LIMIT: number = 10 * 1024 * 1024;
let registered: boolean = false;
let fileSequence: number = 0;

class BarcodePoint {
  x: number;
  y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

class BarcodeSize {
  width: number;
  height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}

class BarcodeBounds {
  origin: BarcodePoint;
  size: BarcodeSize;

  constructor(origin: BarcodePoint, size: BarcodeSize) {
    this.origin = origin;
    this.size = size;
  }
}

class BarcodeResult {
  type: string;
  data: string;
  raw: string;
  cornerPoints: BarcodePoint[];
  bounds: BarcodeBounds;

  constructor(type: string, data: string, points: BarcodePoint[], bounds: BarcodeBounds) {
    this.type = type;
    this.data = data;
    this.raw = data;
    this.cornerPoints = points;
    this.bounds = bounds;
  }
}

interface SavePictureOptions {
  quality?: number;
  base64?: boolean;
  metadata?: Record<string, ESObject>;
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

async function writeBuffer(path: string, buffer: ArrayBuffer): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  let offset = 0;

  try {
    while (offset < buffer.byteLength) {
      const chunk = buffer.slice(offset, Math.min(offset + 64 * 1024, buffer.byteLength));
      const count = await fs.write(file.fd, chunk, { offset });
      if (count <= 0) throw new ExpoCameraError('ERR_CAMERA_FILE_WRITE', `Unable to write '${path}'.`);
      offset += count;
    }
  } finally {
    await fs.close(file.fd);
  }
}

async function ensureDirectory(path: string): Promise<void> {
  if (!(await fs.access(path))) await fs.mkdir(path, true);
}

async function readBuffer(path: string): Promise<ArrayBuffer> {
  const stat = await fs.stat(path);
  const buffer = new ArrayBuffer(stat.size);
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  let offset = 0;

  try {
    while (offset < buffer.byteLength) {
      const chunk = new ArrayBuffer(Math.min(64 * 1024, buffer.byteLength - offset));
      const count = await fs.read(file.fd, chunk, { length: chunk.byteLength });
      if (count <= 0) break;

      new Uint8Array(buffer).set(new Uint8Array(chunk, 0, count), offset);
      offset += count;
    }
  } finally {
    await fs.close(file.fd);
  }

  if (offset !== buffer.byteLength) {
    throw new ExpoCameraError('ERR_CAMERA_FILE_READ', `Unable to read '${path}'.`);
  }

  return buffer;
}

function uniquePath(dir: string, prefix: string, extension: string): string {
  fileSequence = (fileSequence + 1) % 1_000_000;

  return `${dir}/${prefix}-${Date.now()}-${fileSequence}.${extension}`;
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

function barcodeType(type: scanCore.ScanType): string {
  if (type === scanCore.ScanType.AZTEC_CODE) return 'aztec';
  if (type === scanCore.ScanType.CODABAR_CODE) return 'codabar';
  if (type === scanCore.ScanType.CODE39_CODE) return 'code39';
  if (type === scanCore.ScanType.CODE93_CODE) return 'code93';
  if (type === scanCore.ScanType.CODE128_CODE) return 'code128';
  if (type === scanCore.ScanType.DATAMATRIX_CODE) return 'datamatrix';
  if (type === scanCore.ScanType.EAN8_CODE) return 'ean8';
  if (type === scanCore.ScanType.EAN13_CODE) return 'ean13';
  if (type === scanCore.ScanType.ITF14_CODE) return 'itf14';
  if (type === scanCore.ScanType.PDF417_CODE) return 'pdf417';
  if (type === scanCore.ScanType.QR_CODE) return 'qr';
  if (type === scanCore.ScanType.UPC_A_CODE) return 'upc_a';
  if (type === scanCore.ScanType.UPC_E_CODE) return 'upc_e';
  return 'unknown';
}

function scanType(type: string): scanCore.ScanType | undefined {
  if (type === 'aztec') return scanCore.ScanType.AZTEC_CODE;
  if (type === 'codabar') return scanCore.ScanType.CODABAR_CODE;
  if (type === 'code39') return scanCore.ScanType.CODE39_CODE;
  if (type === 'code93') return scanCore.ScanType.CODE93_CODE;
  if (type === 'code128') return scanCore.ScanType.CODE128_CODE;
  if (type === 'datamatrix') return scanCore.ScanType.DATAMATRIX_CODE;
  if (type === 'ean8') return scanCore.ScanType.EAN8_CODE;
  if (type === 'ean13') return scanCore.ScanType.EAN13_CODE;
  if (type === 'itf14') return scanCore.ScanType.ITF14_CODE;
  if (type === 'pdf417') return scanCore.ScanType.PDF417_CODE;
  if (type === 'qr') return scanCore.ScanType.QR_CODE;
  if (type === 'upc_a') return scanCore.ScanType.UPC_A_CODE;
  if (type === 'upc_e') return scanCore.ScanType.UPC_E_CODE;
  return undefined;
}

function scanTypes(value?: ESObject, allWhenEmpty: boolean = true): scanCore.ScanType[] {
  if (!Array.isArray(value)) return allWhenEmpty ? [scanCore.ScanType.ALL] : [];

  const types = (value as string[])
    .map((type: string): scanCore.ScanType | undefined => scanType(type))
    .filter((type: scanCore.ScanType | undefined): boolean => type !== undefined) as scanCore.ScanType[];

  return types.length === 0 && allWhenEmpty ? [scanCore.ScanType.ALL] : types;
}

function barcodeResult(value: scanBarcode.ScanResult): BarcodeResult {
  const rect = value.scanCodeRect;
  const left = rect?.left ?? 0;
  const top = rect?.top ?? 0;
  const right = rect?.right ?? left;
  const bottom = rect?.bottom ?? top;
  const bounds = new BarcodeBounds(new BarcodePoint(left, top), new BarcodeSize(right - left, bottom - top));
  const points = value.cornerPoints?.map((point: scanBarcode.Point): BarcodePoint => {
    return new BarcodePoint(point.x, point.y);
  }) ?? [new BarcodePoint(left, top), new BarcodePoint(right, top), new BarcodePoint(right, bottom), new BarcodePoint(left, bottom)];

  return new BarcodeResult(barcodeType(value.scanType), value.originalValue, points, bounds);
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

class ExpoCameraViewAdapter implements ExpoViewAdapter {
  readonly componentName: string = COMPONENT_NAME;
  readonly content: WrappedBuilder<[ExpoViewContentContext]> = wrapBuilder(buildExpoCameraView);

  create(context: RNComponentContext, tag: number, _: string): ESObject {
    const state = new ExpoCameraViewState(context, tag);
    ExpoCameraViewRegistry.add(state);
    return state;
  }

  updateProps(view: ESObject, props: Record<string, ESObject>): void {
    (view as ExpoCameraViewState).updateProps(props);
  }

  destroy(view: ESObject): void {
    const state = view as ExpoCameraViewState;
    ExpoCameraViewRegistry.remove(state.instanceId, state.tag);
  }
}

class ExpoCameraService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;

  constructor(context: UITurboModuleContext) {
    this.context = context;
  }

  invokeSync(method: string, _: ESObject[]): ESObject {
    if (method === 'isModernBarcodeScannerAvailable') return canIUse(SCAN_CAPABILITY);

    throw new ExpoCameraError('ERR_CAMERA_UNKNOWN_METHOD', `Unknown synchronous Expo Camera method '${method}'.`);
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'isAvailable') {
      return camera.getCameraManager(this.context.uiAbilityContext).getSupportedCameras().length > 0;
    }

    if (method === 'getCameraPermissions') return this.getPermission(CAMERA_PERMISSION);
    if (method === 'requestCameraPermissions') return await this.requestPermission(CAMERA_PERMISSION);
    if (method === 'getMicrophonePermissions') return this.getPermission(MICROPHONE_PERMISSION);
    if (method === 'requestMicrophonePermissions') return await this.requestPermission(MICROPHONE_PERMISSION);
    if (method === 'getAvailableVideoCodecs') return await this.getAvailableVideoCodecs();
    if (method === 'savePicture') return await this.savePicture(String(args[0] ?? ''), args[1] as SavePictureOptions | undefined);

    if (method === 'scanFromURL') return await this.scanFromURL(String(args[0] ?? ''), args[1]);
    if (method === 'dismissScanner') return null;
    if (method === 'launchScanner') return await this.launchScanner(args[0]);

    if (method === 'destroy') {
      ExpoCameraViewRegistry.destroyInstance(this.context.rnInstance.getId());

      return null;
    }
    if (method === 'background') {
      ExpoCameraViewRegistry.onBackground(this.context.rnInstance.getId());

      return null;
    }
    if (method === 'foreground') {
      ExpoCameraViewRegistry.onForeground(this.context.rnInstance.getId());

      return null;
    }

    if (
      method === 'takePicture' ||
      method === 'getAvailablePictureSizes' ||
      method === 'getAvailableLenses' ||
      method === 'record' ||
      method === 'toggleRecording' ||
      method === 'stopRecording' ||
      method === 'resumePreview' ||
      method === 'pausePreview' ||
      method === 'launchModernScanner'
    ) {
      const tag = Number(args[0]);
      if (!Number.isFinite(tag)) throw new ExpoCameraError('ERR_CAMERA_VIEW_NOT_FOUND', 'Camera view tag is invalid.');

      return await ExpoCameraViewRegistry.require(this.context.rnInstance.getId(), tag).invoke(method, args.slice(1));
    }

    throw new ExpoCameraError('ERR_CAMERA_UNKNOWN_METHOD', `Unknown Expo Camera method '${method}'.`);
  }

  onDestroy(): void {
    ExpoCameraViewRegistry.destroyInstance(this.context.rnInstance.getId());
  }

  private getPermission(permission: Permissions): PermissionRecord {
    const manager = abilityAccessCtrl.createAtManager();

    try {
      const status = manager.getSelfPermissionStatus(permission);
      if (status === abilityAccessCtrl.PermissionStatus.GRANTED) return new PermissionRecord('granted', true);
      if (status === abilityAccessCtrl.PermissionStatus.NOT_DETERMINED) return new PermissionRecord('undetermined', true);

      return new PermissionRecord('denied', false);
    } catch (_) {
      const token = this.context.uiAbilityContext.applicationInfo.accessTokenId;
      const granted = manager.checkAccessTokenSync(token, permission) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;

      return new PermissionRecord(granted ? 'granted' : 'denied', true);
    }
  }

  private async requestPermission(permission: Permissions): Promise<PermissionRecord> {
    try {
      await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context.uiAbilityContext, [permission]);

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

  private async scanFromURL(url: string, types: ESObject): Promise<BarcodeResult[]> {
    if (url.length === 0) throw new ExpoCameraError('ERR_CAMERA_INVALID_URL', 'The barcode image URL is empty.');
    if (!canIUse(SCAN_CAPABILITY)) {
      throw new ExpoCameraError('ERR_CAMERA_SCANNER_UNAVAILABLE', 'Barcode scanning is not supported on this device.');
    }

    const requested = scanTypes(types, false);
    let uri = url;
    let path: string | undefined;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      const request = http.createHttp();

      try {
        const response = await request.request(url, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 15000,
          readTimeout: 30000,
          maxLimit: BARCODE_IMAGE_LIMIT,
        });
        if (response.responseCode < 200 || response.responseCode >= 300 || !(response.result instanceof ArrayBuffer)) {
          throw new ExpoCameraError('ERR_CAMERA_IMAGE_DOWNLOAD', 'Could not download the barcode image.');
        }
        if (response.result.byteLength > BARCODE_IMAGE_LIMIT) {
          throw new ExpoCameraError('ERR_CAMERA_IMAGE_TOO_LARGE', 'The barcode image exceeds the 10 MB limit.');
        }

        const dir = `${this.context.uiAbilityContext.cacheDir}/expo-camera`;
        await ensureDirectory(dir);
        path = uniquePath(dir, 'barcode', 'img');

        await writeBuffer(path, response.result);

        uri = `file://${path}`;
      } catch (error) {
        console.error(`Expo Camera barcode image download failed: ${String(error)}`);
        if (error instanceof ExpoCameraError && error.code === 'ERR_CAMERA_IMAGE_TOO_LARGE') {
          throw new ExpoCameraError('ERR_CAMERA_IMAGE_TOO_LARGE', 'The barcode image exceeds the 10 MB limit.');
        }

        throw new ExpoCameraError('ERR_CAMERA_IMAGE_DOWNLOAD', 'Could not download the barcode image.');
      } finally {
        request.destroy();
      }
    } else if (url.startsWith('data:')) {
      const separator = url.indexOf(',');
      if (separator < 0 || !url.slice(0, separator).includes(';base64')) {
        throw new ExpoCameraError('ERR_CAMERA_INVALID_URL', 'The barcode data URL must contain a base64-encoded image.');
      }

      let data: Uint8Array;
      try {
        data = await new util.Base64Helper().decode(url.slice(separator + 1));
      } catch (error) {
        console.error(`Expo Camera could not decode a barcode data URL: ${String(error)}`);

        throw new ExpoCameraError('ERR_CAMERA_INVALID_URL', 'The barcode data URL is not valid base64.');
      }
      if (data.byteLength > BARCODE_IMAGE_LIMIT) {
        throw new ExpoCameraError('ERR_CAMERA_IMAGE_TOO_LARGE', 'The barcode image exceeds the 10 MB limit.');
      }

      const dir = `${this.context.uiAbilityContext.cacheDir}/expo-camera`;
      await ensureDirectory(dir);
      path = uniquePath(dir, 'barcode', 'img');

      await writeBuffer(path, data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));

      uri = `file://${path}`;
    }

    try {
      if (requested.length === 0) return [];

      const results = await detectBarcode.decode({ uri }, { scanTypes: requested });

      return results.map((result: scanBarcode.ScanResult): BarcodeResult => barcodeResult(result));
    } catch (error) {
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

  private async launchScanner(value: ESObject): Promise<BarcodeResult> {
    if (!canIUse(SCAN_CAPABILITY)) {
      throw new ExpoCameraError('ERR_CAMERA_SCANNER_UNAVAILABLE', 'The modern barcode scanner is not supported on this device.');
    }

    const options = value as Record<string, ESObject> | undefined;

    try {
      const result = await scanBarcode.startScanForResult(this.context.uiAbilityContext, {
        scanTypes: scanTypes(options?.barcodeTypes),
      });

      return barcodeResult(result);
    } catch (error) {
      console.error(`Expo Camera barcode scanner failed: ${String(error)}`);
      const code = (error as BusinessError).code;
      if (code === 1000500002) {
        throw new ExpoCameraError('ERR_CAMERA_SCANNER_CANCELLED', 'The barcode scanner was cancelled.');
      }

      throw new ExpoCameraError('ERR_CAMERA_SCANNER', 'The barcode scanner could not complete.');
    }
  }

  private async savePicture(uri: string, options: SavePictureOptions = {}): Promise<SavedPicture> {
    if (!uri.startsWith('file://')) {
      throw new ExpoCameraError('ERR_CAMERA_PICTURE_REF', 'The picture reference no longer points to a local image.');
    }
    if (options.quality !== undefined && (!Number.isFinite(options.quality) || options.quality < 0 || options.quality > 1)) {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', 'Photo quality must be a number between 0 and 1.');
    }

    const source = image.createImageSource(uri.slice('file://'.length));
    const pixel = await source.createPixelMap();
    const packer = image.createImagePacker();

    try {
      const info = await pixel.getImageInfo();
      const buffer = await packer.packToData(pixel, {
        format: 'image/jpeg',
        quality: Math.round((options.quality ?? 1) * 100),
        bufferSize: 25 * 1024 * 1024,
        needsPackProperties: options.metadata !== undefined,
      });

      const dir = `${this.context.uiAbilityContext.cacheDir}/expo-camera`;
      await ensureDirectory(dir);
      const path = uniquePath(dir, 'picture-ref', 'jpg');

      await writeBuffer(path, buffer);
      await writeMetadata(path, options.metadata);

      const result = new SavedPicture(`file://${path}`, info.size.width, info.size.height);
      if (options.base64 === true) {
        const saved = options.metadata === undefined ? buffer : await readBuffer(path);
        result.base64 = await new util.Base64Helper().encodeToString(new Uint8Array(saved));
      }

      return result;
    } finally {
      try {
        await packer.release();
      } catch (_) {}
      try {
        await pixel.release();
      } catch (_) {}
      try {
        await source.release();
      } catch (_) {}
    }
  }
}

function registerNativeAdapters(): void {
  if (registered) return;

  ExpoViewAdapterRegistry.register(new ExpoCameraViewAdapter());
  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new ExpoCameraService(context),
  });

  registered = true;
}

export class ExpoCameraPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    registerNativeAdapters();
    super(context);
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-camera';
  }
}
