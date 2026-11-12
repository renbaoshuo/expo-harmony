/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import image from '@ohos.multimedia.image';

export const SCAN_CAPABILITY: string = 'SystemCapability.Multimedia.Scan.ScanBarcode';

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

export class BarcodeResult {
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

export function scanTypes(value?: string[], allWhenEmpty: boolean = true): scanCore.ScanType[] {
  if (value === undefined) return allWhenEmpty ? [scanCore.ScanType.ALL] : [];

  const types = value
    .map((type: string): scanCore.ScanType | undefined => scanType(type))
    .filter((type: scanCore.ScanType | undefined): boolean => type !== undefined) as scanCore.ScanType[];

  return types.length === 0 && allWhenEmpty ? [scanCore.ScanType.ALL] : types;
}

export function barcodeResult(value: scanBarcode.ScanResult, includeGeometry: boolean = true): BarcodeResult {
  const rect = includeGeometry ? value.scanCodeRect : undefined;
  const left = rect?.left ?? 0;
  const top = rect?.top ?? 0;
  const right = rect?.right ?? left;
  const bottom = rect?.bottom ?? top;
  const bounds = new BarcodeBounds(new BarcodePoint(left, top), new BarcodeSize(right - left, bottom - top));
  const points =
    includeGeometry ? value.cornerPoints?.map((point: scanBarcode.Point): BarcodePoint => {
      return new BarcodePoint(point.x, point.y);
    }) ?? [] : [];

  return new BarcodeResult(barcodeType(value.scanType), value.originalValue, points, bounds);
}

const SCAN_INTERVAL_MS: number = 200;

function scanProfile(profiles: camera.Profile[]): camera.Profile | undefined {
  const nv21 = profiles.filter((profile: camera.Profile): boolean => {
    return profile.format === camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP &&
      profile.size.width % 2 === 0 && profile.size.height % 2 === 0;
  });
  const readable = nv21.filter((profile: camera.Profile): boolean => {
    return Math.min(profile.size.width, profile.size.height) >= 480;
  });
  return (readable.length > 0 ? readable : nv21).sort((left: camera.Profile, right: camera.Profile): number => {
    return left.size.width * left.size.height - right.size.width * right.size.height;
  })[0];
}

function packNv21(component: image.Component, width: number, height: number): ArrayBuffer {
  const stride = component.rowStride;
  const rows = height * 3 / 2;
  const bytes = component.byteBuffer;
  if (width <= 0 || height <= 0 || width % 2 !== 0 || height % 2 !== 0 ||
    stride < width || bytes.byteLength < (rows - 1) * stride + width) {
    throw new Error('Invalid NV21 barcode frame stride.');
  }
  if (stride === width) return bytes.slice(0, width * rows);

  const packed = new Uint8Array(width * rows);

  for (let row = 0; row < rows; row += 1) {
    packed.set(new Uint8Array(bytes, row * stride, width), row * width);
  }

  return packed.buffer;
}

export class CameraBarcodeAnalyzer {
  private readonly receiver: image.ImageReceiver;
  private readonly output: camera.PreviewOutput;
  private readonly canScan: () => boolean;
  private readonly getBarcodeTypes: () => string[] | undefined;
  private readonly onBarcodeScanned: (result: BarcodeResult) => void;
  private reading?: Promise<void>;
  private decoding: boolean = false;
  private released: boolean = false;
  private warned: boolean = false;
  private nextScan: number = 0;

  private readonly onImageArrival = (error: BusinessError): void => {
    if (error || this.released || this.reading !== undefined) return;

    this.reading = this.readFrame().catch((failure: Object): void => this.warn(failure)).finally((): void => {
      this.reading = undefined;
    });
  };

  private constructor(
    receiver: image.ImageReceiver,
    output: camera.PreviewOutput,
    canScan: () => boolean,
    getBarcodeTypes: () => string[] | undefined,
    onBarcodeScanned: (result: BarcodeResult) => void,
  ) {
    this.receiver = receiver;
    this.output = output;
    this.canScan = canScan;
    this.getBarcodeTypes = getBarcodeTypes;
    this.onBarcodeScanned = onBarcodeScanned;
  }

  static async attach(
    manager: camera.CameraManager,
    session: camera.Session,
    profiles: camera.Profile[],
    canScan: () => boolean,
    getBarcodeTypes: () => string[] | undefined,
    onBarcodeScanned: (result: BarcodeResult) => void,
  ): Promise<CameraBarcodeAnalyzer | undefined> {
    const profile = scanProfile(profiles);
    if (profile === undefined || !canIUse(SCAN_CAPABILITY)) return undefined;

    let receiver: image.ImageReceiver | undefined;
    let output: camera.PreviewOutput | undefined;
    let analyzer: CameraBarcodeAnalyzer | undefined;
    let attached = false;
    try {
      // CameraKit determines the format. ImageReceiver exposes the whole NV21 buffer as ComponentType.JPEG.
      receiver = image.createImageReceiver(profile.size, image.ImageFormat.JPEG, 3);
      output = manager.createPreviewOutput(profile, await receiver.getReceivingSurfaceId());
      if (!session.canAddOutput(output)) return undefined;

      analyzer = new CameraBarcodeAnalyzer(receiver, output, canScan, getBarcodeTypes, onBarcodeScanned);
      receiver.on('imageArrival', analyzer.onImageArrival);
      session.addOutput(output);
      attached = true;
      return analyzer;
    } catch (error) {
      console.warn(`Expo Camera could not add a barcode analysis output: ${String(error)}`);
      return undefined;
    } finally {
      if (!attached) {
        if (analyzer !== undefined) {
          await analyzer.release();
        } else {
          await releaseBarcodeStream(output, receiver);
        }
      }
    }
  }

  private async readFrame(): Promise<void> {
    const frame = await this.receiver.readLatestImage();
    let scan: detectBarcode.ByteImage | undefined;
    let types: scanCore.ScanType[] = [];
    try {
      const now = Date.now();
      if (!this.released && this.canScan() && !this.decoding && now >= this.nextScan) {
        this.nextScan = now + SCAN_INTERVAL_MS;
        const requested = this.getBarcodeTypes();
        types = scanTypes(requested, requested === undefined || requested.length === 0);
        if (types.length > 0) {
          const size = frame.size;
          const component = await frame.getComponent(image.ComponentType.JPEG);
          scan = {
            byteBuffer: packNv21(component, size.width, size.height),
            width: size.width,
            height: size.height,
            format: detectBarcode.ImageFormat.NV21,
          };
        }
      }
    } finally {
      await frame.release();
    }
    if (scan !== undefined && !this.released && this.canScan()) {
      this.decoding = true;
      void this.decode(scan, types);
    }
  }

  private async decode(frame: detectBarcode.ByteImage, types: scanCore.ScanType[]): Promise<void> {
    try {
      const result = await detectBarcode.decodeImage(frame, { scanTypes: types });

      for (const value of result.scanResults) {
        if (this.released || !this.canScan()) return;
        const barcode = barcodeResult(value, false);
        const requested = this.getBarcodeTypes();
        if (barcode.type !== 'unknown' && (requested === undefined || requested.length === 0 || requested.includes(barcode.type))) {
          this.onBarcodeScanned(barcode);
        }
      }
    } catch (error) {
      this.warn(error as Object);
    } finally {
      this.decoding = false;
    }
  }

  async release(): Promise<void> {
    this.released = true;
    try {
      this.receiver.off('imageArrival', this.onImageArrival);
    } catch (_) {}
    await this.reading;
    await releaseBarcodeStream(this.output, this.receiver);
  }

  private warn(error: Object): void {
    if (this.released || this.warned) return;
    this.warned = true;
    console.warn(`Expo Camera could not scan the preview frame: ${String(error)}`);
  }
}

async function releaseBarcodeStream(output?: camera.PreviewOutput, receiver?: image.ImageReceiver): Promise<void> {
  try {
    await output?.release();
  } catch (_) {}
  try {
    await receiver?.release();
  } catch (_) {}
}
