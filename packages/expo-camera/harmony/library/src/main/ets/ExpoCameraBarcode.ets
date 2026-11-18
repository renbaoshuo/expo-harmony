/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { camera } from '@kit.CameraKit';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';

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

export interface BarcodePreviewGeometry {
  rotation: number;
  mirror: boolean;
  width: number;
  height: number;
  offsetX: number;
  offsetY: number;
}

interface BarcodeFormat {
  expoType: string;
  scanType: scanCore.ScanType;
}

const BARCODE_FORMATS: BarcodeFormat[] = [
  { expoType: 'aztec', scanType: scanCore.ScanType.AZTEC_CODE },
  { expoType: 'codabar', scanType: scanCore.ScanType.CODABAR_CODE },
  { expoType: 'code39', scanType: scanCore.ScanType.CODE39_CODE },
  { expoType: 'code93', scanType: scanCore.ScanType.CODE93_CODE },
  { expoType: 'code128', scanType: scanCore.ScanType.CODE128_CODE },
  { expoType: 'datamatrix', scanType: scanCore.ScanType.DATAMATRIX_CODE },
  { expoType: 'ean8', scanType: scanCore.ScanType.EAN8_CODE },
  { expoType: 'ean13', scanType: scanCore.ScanType.EAN13_CODE },
  { expoType: 'itf14', scanType: scanCore.ScanType.ITF14_CODE },
  { expoType: 'pdf417', scanType: scanCore.ScanType.PDF417_CODE },
  { expoType: 'qr', scanType: scanCore.ScanType.QR_CODE },
  { expoType: 'upc_a', scanType: scanCore.ScanType.UPC_A_CODE },
  { expoType: 'upc_e', scanType: scanCore.ScanType.UPC_E_CODE },
];

function barcodeType(type: scanCore.ScanType): string {
  return BARCODE_FORMATS.find((format: BarcodeFormat): boolean => format.scanType === type)?.expoType ?? 'unknown';
}

export function scanTypes(value?: string[], allWhenEmpty: boolean = true): scanCore.ScanType[] {
  if (value === undefined || value.length === 0) {
    return allWhenEmpty ? BARCODE_FORMATS.map((format: BarcodeFormat): scanCore.ScanType => format.scanType) : [];
  }

  return BARCODE_FORMATS
    .filter((format: BarcodeFormat): boolean => value.includes(format.expoType))
    .map((format: BarcodeFormat): scanCore.ScanType => format.scanType);
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

function projectPoint(x: number, y: number, geometry: BarcodePreviewGeometry): BarcodePoint {
  let u = x;
  let v = y;
  if (geometry.rotation === 90) {
    u = 1 - y;
    v = x;
  } else if (geometry.rotation === 180) {
    u = 1 - x;
    v = 1 - y;
  } else if (geometry.rotation === 270) {
    u = y;
    v = 1 - x;
  }
  if (geometry.mirror) u = 1 - u;

  return new BarcodePoint(geometry.offsetX + u * geometry.width, geometry.offsetY + v * geometry.height);
}

function previewBarcodeResult(
  value: scanBarcode.ScanResult,
  frame: detectBarcode.ByteImage,
  geometry?: BarcodePreviewGeometry,
): BarcodeResult {
  if (geometry === undefined) return barcodeResult(value, false);

  const points = value.cornerPoints?.map((point: scanBarcode.Point): BarcodePoint =>
    projectPoint(point.x / frame.width, point.y / frame.height, geometry),
  ) ?? [];
  const rect = value.scanCodeRect;
  const corners = rect === undefined ? points : [
    projectPoint(rect.left / frame.width, rect.top / frame.height, geometry),
    projectPoint(rect.right / frame.width, rect.bottom / frame.height, geometry),
  ];
  if (corners.length === 0) return barcodeResult(value, false);

  const xs = corners.map((point: BarcodePoint): number => point.x);
  const ys = corners.map((point: BarcodePoint): number => point.y);
  const left = Math.min(...xs);
  const top = Math.min(...ys);

  return new BarcodeResult(
    barcodeType(value.scanType),
    value.originalValue,
    points,
    new BarcodeBounds(new BarcodePoint(left, top), new BarcodeSize(Math.max(...xs) - left, Math.max(...ys) - top)),
  );
}

const SCAN_INTERVAL_MS: number = 200;

function scanProfile(profiles: camera.Profile[], preview: camera.Profile): camera.Profile | undefined {
  const nv21 = profiles.filter((profile: camera.Profile): boolean => {
    return profile.format === camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP &&
      profile.size.width % 2 === 0 && profile.size.height % 2 === 0;
  });
  const ratio = preview.size.width / preview.size.height;
  const matching = nv21.filter((profile: camera.Profile): boolean => {
    return Math.abs(profile.size.width / profile.size.height - ratio) < 0.03;
  });
  const candidates = matching.length > 0 ? matching : nv21;
  const readable = candidates.filter((profile: camera.Profile): boolean => {
    return Math.min(profile.size.width, profile.size.height) >= 480;
  });

  return (readable.length > 0 ? readable : candidates).sort((left: camera.Profile, right: camera.Profile): number => {
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
  private readonly getGeometry: (width: number, height: number) => BarcodePreviewGeometry | undefined;
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
    getGeometry: (width: number, height: number) => BarcodePreviewGeometry | undefined,
    onBarcodeScanned: (result: BarcodeResult) => void,
  ) {
    this.receiver = receiver;
    this.output = output;
    this.canScan = canScan;
    this.getBarcodeTypes = getBarcodeTypes;
    this.getGeometry = getGeometry;
    this.onBarcodeScanned = onBarcodeScanned;
  }

  static async attach(
    manager: camera.CameraManager,
    session: camera.Session,
    profiles: camera.Profile[],
    preview: camera.Profile,
    canScan: () => boolean,
    getBarcodeTypes: () => string[] | undefined,
    getGeometry: (width: number, height: number) => BarcodePreviewGeometry | undefined,
    onBarcodeScanned: (result: BarcodeResult) => void,
  ): Promise<CameraBarcodeAnalyzer | undefined> {
    const profile = scanProfile(profiles, preview);
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

      analyzer = new CameraBarcodeAnalyzer(receiver, output, canScan, getBarcodeTypes, getGeometry, onBarcodeScanned);
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
      const now = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);

      if (!this.released && this.canScan() && !this.decoding && now >= this.nextScan) {
        this.nextScan = now + SCAN_INTERVAL_MS;
        types = scanTypes(this.getBarcodeTypes());

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
    const geometry = this.getGeometry(frame.width, frame.height);

    try {
      const result = await detectBarcode.decodeImage(frame, { scanTypes: types, enableMultiMode: true });
      const current = geometry === this.getGeometry(frame.width, frame.height) ? geometry : undefined;

      for (const value of result.scanResults) {
        if (this.released || !this.canScan()) return;

        const barcode = previewBarcodeResult(value, frame, current);
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
