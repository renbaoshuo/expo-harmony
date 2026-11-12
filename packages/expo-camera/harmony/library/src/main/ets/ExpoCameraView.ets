/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  fileUriFromPath,
  filePathFromUri,
  ExpoPermissionStatus,
  ExpoView,
  ExpoViewContentContext,
  ExpoViewContext,
} from '@expo-harmony/expo-modules-core';
import { Permissions } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';
import { media } from '@kit.MediaKit';
import { sensor } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import deviceInfo from '@ohos.deviceInfo';
import display from '@ohos.display';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import { BarcodeResult, CameraBarcodeAnalyzer } from './ExpoCameraBarcode';
import { ExpoCameraError } from './ExpoCameraError';
import { ensureDirectory, packPicture, readBuffer, uniquePath, writeBuffer } from './ExpoCameraFiles';
import { decodeExifProperties, encodeExifMetadata, writableExifProperties, EXIF_KEYS } from './ExpoCameraExif';

interface CameraProps {
  facing?: string;
  flashMode?: string;
  selectedLens?: string;
  enableTorch?: boolean;
  pictureSize?: string;
  zoom?: number;
  mode?: string;
  barcodeScannerEnabled?: boolean;
  barcodeScannerSettings?: BarcodeScannerSettings;
  mute?: boolean;
  animateShutter?: boolean;
  videoQuality?: string;
  videoStabilizationMode?: string;
  autoFocus?: string;
  responsiveOrientationWhenOrientationLocked?: boolean;
  mirror?: boolean;
  active?: boolean;
  videoBitrate?: number;
  ratio?: string;
}

function cloneCameraProps(value: CameraProps): CameraProps {
  return {
    facing: value.facing,
    flashMode: value.flashMode,
    selectedLens: value.selectedLens,
    enableTorch: value.enableTorch,
    pictureSize: value.pictureSize,
    zoom: value.zoom,
    mode: value.mode,
    barcodeScannerEnabled: value.barcodeScannerEnabled,
    barcodeScannerSettings: value.barcodeScannerSettings,
    mute: value.mute,
    animateShutter: value.animateShutter,
    videoQuality: value.videoQuality,
    videoStabilizationMode: value.videoStabilizationMode,
    autoFocus: value.autoFocus,
    responsiveOrientationWhenOrientationLocked: value.responsiveOrientationWhenOrientationLocked,
    mirror: value.mirror,
    active: value.active,
    videoBitrate: value.videoBitrate,
    ratio: value.ratio,
  };
}

export interface PictureOptions {
  quality?: number;
  base64?: boolean;
  exif?: boolean;
  additionalExif?: Record<string, ESObject>;
  id?: number;
  fastMode?: boolean;
  mirror?: boolean;
  skipProcessing?: boolean;
  imageType?: string;
  pictureRef?: boolean;
  shutterSound?: boolean;
  maxDownsampling?: number;
}

export interface RecordingOptions {
  maxDuration?: number;
  maxFileSize?: number;
  mirror?: boolean;
  codec?: string;
}

export interface BarcodeScannerSettings {
  barcodeTypes?: string[];
}

class PictureResult {
  uri: string;
  width: number;
  height: number;
  format: string;
  base64?: string;
  exif?: ESObject;
  pictureRef?: boolean;

  constructor(uri: string, width: number, height: number, format: string) {
    this.uri = uri;
    this.width = width;
    this.height = height;
    this.format = format;
  }
}

class VideoResult {
  uri: string;

  constructor(uri: string) {
    this.uri = uri;
  }
}

interface PendingCapture {
  options: PictureOptions;
  softwareMirror: boolean;
  format: camera.CameraFormat;
  rawRotation?: camera.ImageRotation;
  resolve?: (value: ESObject) => void;
  reject?: (error: ExpoCameraError) => void;
  timer?: number;
  processing?: boolean;
}

interface ReadyWaiter {
  resolve: () => void;
  reject: (error: ExpoCameraError) => void;
  timer: number;
}

type ModernSession = camera.PhotoSession | camera.VideoSession;
type ControllableSession = ModernSession | camera.CaptureSession;

interface PhotoCapability {
  profiles: camera.CameraOutputCapability;
  useBasicSession: boolean;
}

interface RgbaPhotoData {
  jpeg?: ArrayBuffer;
  pixel?: image.PixelMap;
}

const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const CAPTURE_TIMEOUT_MS: number = 15_000;
const GRAVITY_THRESHOLD: number = 9.80665 * 0.75;
let photoProcessingQueue: Promise<void> = Promise.resolve();
let viewCleanup: Promise<void> = Promise.resolve();

function wait(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms);
  });
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function orientationCode(value?: string | null): number {
  if (value === undefined || value === null) return 1;

  const number = Number(value);
  if (Number.isInteger(number) && number >= 1 && number <= 8) return number;

  const name = value.toLowerCase().replace(/[^a-z]/g, '');
  if (name.includes('topright')) return 2;
  if (name.includes('bottomright')) return 3;
  if (name.includes('bottomleft')) return 4;
  if (name.includes('lefttop')) return 5;
  if (name.includes('righttop')) return 6;
  if (name.includes('rightbottom')) return 7;
  if (name.includes('leftbottom')) return 8;
  return 1;
}

async function transformPixelMap(pixel: image.PixelMap, orientation: number, mirror: boolean): Promise<void> {
  if (orientation === 2) {
    await pixel.flip(true, false);
  } else if (orientation === 3) {
    await pixel.rotate(180);
  } else if (orientation === 4) {
    await pixel.flip(false, true);
  } else if (orientation === 5) {
    await pixel.flip(true, false);
    await pixel.rotate(270);
  } else if (orientation === 6) {
    await pixel.rotate(90);
  } else if (orientation === 7) {
    await pixel.flip(true, false);
    await pixel.rotate(90);
  } else if (orientation === 8) {
    await pixel.rotate(270);
  }

  if (mirror) await pixel.flip(true, false);
}

function profileSize(profile: camera.Profile): string {
  return `${profile.size.width}x${profile.size.height}`;
}

function profilePixels(profile: camera.Profile): number {
  return profile.size.width * profile.size.height;
}

function aspectRatio(profile: camera.Profile): number {
  return profile.size.width / profile.size.height;
}

function targetRatio(value?: string): number | undefined {
  if (value === '4:3') return 4 / 3;
  if (value === '16:9') return 16 / 9;
  if (value === '1:1') return 1;
  return undefined;
}

function requestedPixels(size: string): number | undefined {
  const match = /^(\d+)x(\d+)$/.exec(size);
  if (match === null) return undefined;

  const width = Number(match[1]);
  const height = Number(match[2]);
  if (width <= 0 || height <= 0) return undefined;

  return width * height;
}

function supportedPhotoProfiles(capability: camera.CameraOutputCapability): camera.Profile[] {
  const jpeg = capability.photoProfiles.filter((profile: camera.Profile): boolean => {
    return profile.format === camera.CameraFormat.CAMERA_FORMAT_JPEG;
  });
  if (jpeg.length > 0 || deviceInfo.sdkApiVersion < 23) return jpeg;

  return capability.photoProfiles.filter((profile: camera.Profile): boolean => {
    return profile.format === camera.CameraFormat.CAMERA_FORMAT_RGBA_8888;
  });
}

async function readRgbaPhoto(photo: image.Image): Promise<RgbaPhotoData> {
  const size = photo.size;
  const data = photo.getBufferData();
  if (data === null) throw new ExpoCameraError('ERR_CAMERA_CAPTURE_PROCESSING', 'The RGBA photo buffer is unavailable.');

  const rowBytes = size.width * 4;
  const stride = data.rowStride[0];
  const pixelStride = data.pixelStride[0];
  if (!Number.isSafeInteger(size.width) || !Number.isSafeInteger(size.height) || size.width <= 0 || size.height <= 0 ||
    pixelStride !== 4 || !Number.isSafeInteger(stride) || stride < rowBytes) {
    throw new ExpoCameraError('ERR_CAMERA_CAPTURE_PROCESSING', 'The RGBA photo buffer has an invalid layout.');
  }

  if (data.byteBuffer.byteLength < (size.height - 1) * stride + rowBytes) {
    // A producer can deliver an encoded JPEG inside a surface configured for RGBA.
    const bytes = new Uint8Array(data.byteBuffer);
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
      return { jpeg: data.byteBuffer.slice(0) };
    }
    throw new ExpoCameraError('ERR_CAMERA_CAPTURE_PROCESSING', 'The RGBA photo buffer is incomplete.');
  }

  // The camera owns the original buffer until the Photo is released.
  const pixels = new Uint8Array(rowBytes * size.height);

  for (let row = 0; row < size.height; row += 1) {
    pixels.set(new Uint8Array(data.byteBuffer, row * stride, rowBytes), row * rowBytes);
  }

  const pixel = await image.createPixelMap(pixels.buffer, {
    size,
    srcPixelFormat: image.PixelMapFormat.RGBA_8888,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    alphaType: image.AlphaType.OPAQUE,
    editable: true,
  });
  return { pixel };
}

function choosePhotoProfile(profiles: camera.Profile[], size?: string, ratio?: string): camera.Profile {
  if (profiles.length === 0) {
    throw new ExpoCameraError('ERR_CAMERA_UNSUPPORTED', 'The selected camera exposes no photo profiles.');
  }

  if (size !== undefined) {
    const exact = profiles.find((profile: camera.Profile): boolean => profileSize(profile) === size);
    if (exact !== undefined) return exact;

    const pixels = requestedPixels(size);
    if (pixels !== undefined) {
      const lower = profiles
        .filter((profile: camera.Profile): boolean => profilePixels(profile) <= pixels)
        .sort((left: camera.Profile, right: camera.Profile): number => profilePixels(right) - profilePixels(left));
      if (lower.length > 0) return lower[0];

      return profiles.slice().sort((left: camera.Profile, right: camera.Profile): number => {
        return profilePixels(left) - profilePixels(right);
      })[0];
    }
  }

  const target = targetRatio(ratio);
  const matches =
    target === undefined ? profiles : profiles.filter((profile: camera.Profile): boolean => Math.abs(aspectRatio(profile) - target) < 0.03);
  const pool = matches.length === 0 ? profiles : matches;

  return pool.slice().sort((left: camera.Profile, right: camera.Profile): number => profilePixels(right) - profilePixels(left))[0];
}

function choosePreviewProfile(profiles: camera.Profile[], output?: camera.Profile, requestedRatio?: string): camera.Profile {
  if (profiles.length === 0) {
    throw new ExpoCameraError('ERR_CAMERA_UNSUPPORTED', 'The selected camera exposes no preview profiles.');
  }

  const ratio = output === undefined ? targetRatio(requestedRatio) : aspectRatio(output);
  const matches = profiles.filter((profile: camera.Profile): boolean => {
    return (ratio === undefined || Math.abs(aspectRatio(profile) - ratio) < 0.03) &&
      profile.size.width <= 1920 && profile.size.height <= 1920;
  });
  const pool = matches.length === 0 ? profiles : matches;

  return pool.slice().sort((left: camera.Profile, right: camera.Profile): number => {
    if (ratio !== undefined) {
      const gap = Math.abs(aspectRatio(left) - ratio) - Math.abs(aspectRatio(right) - ratio);
      if (Math.abs(gap) > 0.001) return gap;
    }
    return profilePixels(right) - profilePixels(left);
  })[0];
}

function videoTargetHeight(quality?: string): number {
  if (quality === '2160p') return 2160;
  if (quality === '720p') return 720;
  if (quality === '480p' || quality === '4:3') return 480;
  return 1080;
}

function chooseVideoProfile(profiles: camera.VideoProfile[], quality?: string): camera.VideoProfile {
  if (profiles.length === 0) {
    throw new ExpoCameraError('ERR_CAMERA_VIDEO_UNSUPPORTED', 'The selected camera exposes no video profiles.');
  }

  const ratio = quality === '4:3' ? 4 / 3 : undefined;
  const matches =
    ratio === undefined ? profiles : profiles.filter((profile: camera.VideoProfile): boolean => Math.abs(aspectRatio(profile) - ratio) < 0.03);
  const pool = matches.length === 0 ? profiles : matches;
  const height = videoTargetHeight(quality);

  const exact = pool.filter((profile: camera.VideoProfile): boolean => profile.size.height === height);
  if (exact.length > 0) {
    return exact.sort((left: camera.VideoProfile, right: camera.VideoProfile): number => profilePixels(right) - profilePixels(left))[0];
  }

  const higher = pool.filter((profile: camera.VideoProfile): boolean => profile.size.height > height);
  if (higher.length > 0) {
    return higher.sort((left: camera.VideoProfile, right: camera.VideoProfile): number => left.size.height - right.size.height)[0];
  }

  return pool.slice().sort((left: camera.VideoProfile, right: camera.VideoProfile): number => right.size.height - left.size.height)[0];
}

async function decodePixelMap(source: image.ImageSource, maxDownsampling?: number): Promise<image.PixelMap> {
  const info = await source.getImageInfo();
  const max = Math.min(maxDownsampling ?? 1, Math.max(info.size.width, info.size.height));
  let sample = 1;

  while (sample <= max) {
    try {
      // ImageSource.sampleSize only supports 1. desiredSize lets the system decoder downsample.
      return await source.createPixelMap({
        desiredSize: {
          width: Math.max(1, Math.floor(info.size.width / sample)),
          height: Math.max(1, Math.floor(info.size.height / sample)),
        },
      });
    } catch (_) {
      sample *= 2;
    }
  }

  throw new ExpoCameraError('ERR_CAMERA_CAPTURE_PROCESSING', 'The captured photo could not be decoded.');
}

type PictureRefFactory = (pixel: image.PixelMap, width: number, height: number) => ESObject;

export class ExpoCameraViewState extends ExpoView {
  readonly controller: XComponentController = new XComponentController();
  readonly tag: number;
  private readonly manager: camera.CameraManager;
  private props: CameraProps = {};
  private pendingProps: CameraProps = {};
  private propsCommitted: boolean = false;
  private readonly pictureRefFactory: PictureRefFactory;
  private surfaceId?: string;
  private device?: camera.CameraDevice;
  private input?: camera.CameraInput;
  private previewOutput?: camera.PreviewOutput;
  private displayChangeListener?: () => void;
  private barcodeAnalyzer?: CameraBarcodeAnalyzer;
  private photoOutput?: camera.PhotoOutput;
  private photoFormat?: camera.CameraFormat;
  private photoListener?: (error: BusinessError, photo: camera.Photo) => void;
  private videoOutput?: camera.VideoOutput;
  private session?: ControllableSession;
  private sessionErrorListener?: (error: BusinessError) => void;
  private recorder?: media.AVRecorder;
  private recordingFile?: fs.File;
  private recordingPath?: string;
  private durationTimer?: number;
  private sizeTimer?: number;
  private durationLeft: number = 0;
  private durationStarted: number = 0;
  private resolveRecording?: (value: ESObject) => void;
  private rejectRecording?: (error: ExpoCameraError) => void;
  private pendingCapture?: PendingCapture;
  private captureStarting: boolean = false;
  private captureGeneration: number = 0;
  private readonly readyWaiters: ReadyWaiter[] = [];
  private reconfigurePending: boolean = false;
  private reconfiguring?: Promise<void>;
  private pipelineGeneration: number = 0;
  private ready: boolean = false;
  private paused: boolean = false;
  private previewTransition: Promise<void> = Promise.resolve();
  private backgrounded: boolean = false;
  private orientationListening: boolean = false;
  private orientation?: string;
  private deviceDegree?: number;
  private destroyed: boolean = false;
  private recording: boolean = false;
  private recordingStarting: boolean = false;
  private recordingStartCancelled: boolean = false;
  private recordingInitialization?: Promise<void>;
  private recordingFinish?: Promise<void>;
  private recordingTransition: Promise<void> = Promise.resolve();
  private finishing: boolean = false;
  private skipBarcodeAnalysis: boolean = false;
  private barcodeWarningShown: boolean = false;
  private shutterWarningShown: boolean = false;
  private flash?: () => void;

  private readonly onPhoto = (error: BusinessError, photo: camera.Photo): void => {
    const pending = this.pendingCapture;
    if (pending === undefined || pending.processing === true) {
      if (photo !== undefined && photo !== null) void photo.release().catch((): void => {});
      return;
    }
    if ((error !== undefined && error !== null) || photo === undefined || photo === null) {
      console.error(`Expo Camera photo capture failed: ${String(error)}`);
      this.reconfigurePending = true;
      this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_FAILED', 'Photo capture failed.'));
      if (photo !== undefined && photo !== null) void photo.release().catch((): void => {});
      return;
    }

    pending.processing = true;
    if (pending.timer !== undefined) {
      clearTimeout(pending.timer);
      pending.timer = undefined;
    }
    photoProcessingQueue = photoProcessingQueue.then(async (): Promise<void> => {
      await this.consumePhoto(photo, pending);
    }).catch((failure: Object): void => {
      console.error(`Expo Camera photo processing failed: ${String(failure)}`);
    });
  };

  private readonly onSessionError = (error: BusinessError): void => {
    if (!this.canStartPreview() || this.reconfigurePending || this.finishing) return;

    console.error(`Expo Camera session failed: ${String(error)}`);
    this.ready = false;
    if (this.barcodeAnalyzer !== undefined) {
      this.skipBarcodeAnalysis = true;
      this.warnBarcodeUnavailable();
      this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'The camera session failed during capture.'));
      this.scheduleReconfigure();
      return;
    }

    this.rejectReadyWaiters(new ExpoCameraError('ERR_CAMERA_SESSION', 'The camera session failed.'));
    this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'The camera session failed during capture.'));
    this.emit('onMountError', { message: 'The camera session failed.' });

    if (this.recording) {
      void this.failRecording(new ExpoCameraError('ERR_CAMERA_RECORDING', 'The camera session failed while recording.'));
    } else {
      this.scheduleReconfigure();
    }
  };

  private readonly onCameraStatus = (error: BusinessError, info: camera.CameraStatusInfo): void => {
    if (this.destroyed || (error !== undefined && error !== null)) return;
    if (info.status !== camera.CameraStatus.CAMERA_STATUS_APPEAR && info.status !== camera.CameraStatus.CAMERA_STATUS_DISAPPEAR) return;

    this.emit('onAvailableLensesChanged', { lenses: this.getAvailableLenses() });

    if (info.status === camera.CameraStatus.CAMERA_STATUS_DISAPPEAR && info.camera.cameraId === this.device?.cameraId) {
      this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'The selected camera became unavailable.'));
      this.scheduleReconfigure();
    } else if (info.status === camera.CameraStatus.CAMERA_STATUS_APPEAR && !this.ready) {
      this.scheduleReconfigure();
    }
  };

  private readonly onGravity = (value: sensor.GravityResponse): void => {
    if (!this.orientationListening) return;

    let orientation: string | undefined;
    if (Math.abs(value.x) > Math.abs(value.y) && Math.abs(value.x) >= GRAVITY_THRESHOLD) {
      this.deviceDegree = value.x > 0 ? 90 : 270;
      orientation = value.x > 0 ? 'landscapeLeft' : 'landscapeRight';
    } else if (Math.abs(value.y) >= GRAVITY_THRESHOLD) {
      this.deviceDegree = value.y > 0 ? 0 : 180;
      orientation = value.y > 0 ? 'portrait' : 'portraitUpsideDown';
    }

    if (orientation === undefined || orientation === this.orientation) return;

    this.orientation = orientation;
    this.emit('onResponsiveOrientationChanged', { orientation });
  };

  constructor(context: ExpoViewContext, pictureRefFactory: PictureRefFactory) {
    super(context);
    this.tag = context.tag;
    this.pictureRefFactory = pictureRefFactory;
    this.manager = camera.getCameraManager(context.rnComponentContext.uiAbilityContext);
    this.manager.on('cameraStatus', this.onCameraStatus);
  }

  setFlash(handler?: () => void): void {
    this.flash = handler;
  }

  attachSurface(surfaceId: string): void {
    if (this.destroyed || surfaceId.length === 0 || surfaceId === this.surfaceId) return;
    this.surfaceId = surfaceId;
    this.scheduleReconfigure();
  }

  detachSurface(): void {
    this.cancelRecordingStart();
    this.surfaceId = undefined;
    this.ready = false;
    this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'The camera preview surface was destroyed.'));

    if (this.recording) {
      void this.finishRecording(true);
    } else {
      this.scheduleReconfigure();
    }
  }

  setFacing(value: string): void {
    if (value !== 'front' && value !== 'back') {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', `Unsupported camera facing '${value}'.`);
    }
    this.pendingProps.facing = value;
  }
  setFlashMode(value: string): void {
    if (value !== 'off' && value !== 'on' && value !== 'auto' && value !== 'screen') {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', `Unsupported camera flash mode '${value}'.`);
    }
    this.pendingProps.flashMode = value;
  }
  setSelectedLens(value: string | null): void {
    this.pendingProps.selectedLens = value ?? undefined;
  }
  setEnableTorch(value: boolean): void {
    this.pendingProps.enableTorch = value;
  }
  setPictureSize(value: string | null): void {
    this.pendingProps.pictureSize = value ?? undefined;
  }
  setZoom(value: number): void {
    if (!Number.isFinite(value) || value < 0 || value > 1) {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', 'Camera zoom must be between 0 and 1.');
    }
    this.pendingProps.zoom = value;
  }
  setMode(value: string): void {
    if (value !== 'picture' && value !== 'video') {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', `Unsupported camera mode '${value}'.`);
    }
    this.pendingProps.mode = value;
  }
  setBarcodeScannerEnabled(value: boolean): void {
    this.pendingProps.barcodeScannerEnabled = value;
  }
  setBarcodeScannerSettings(value: BarcodeScannerSettings | null): void {
    this.pendingProps.barcodeScannerSettings = value ?? undefined;
  }
  setMute(value: boolean): void {
    this.pendingProps.mute = value;
  }
  setAnimateShutter(value: boolean): void {
    this.pendingProps.animateShutter = value;
  }
  setVideoQuality(value: string): void {
    if (!['2160p', '1080p', '720p', '480p', '4:3'].includes(value)) {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', `Unsupported video quality '${value}'.`);
    }
    this.pendingProps.videoQuality = value;
  }
  setVideoStabilizationMode(value: string | null): void {
    this.pendingProps.videoStabilizationMode = value ?? undefined;
  }
  setAutoFocus(value: string): void {
    if (value !== 'on' && value !== 'off') {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', `Unsupported autofocus mode '${value}'.`);
    }
    this.pendingProps.autoFocus = value;
  }
  setResponsiveOrientation(value: boolean): void {
    this.pendingProps.responsiveOrientationWhenOrientationLocked = value;
  }
  setMirror(value: boolean): void {
    this.pendingProps.mirror = value;
  }
  setActive(value: boolean): void {
    this.pendingProps.active = value;
  }
  setVideoBitrate(value: number | null): void {
    if (value !== null && (!Number.isFinite(value) || value <= 0)) {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', 'Video bitrate must be a positive finite number.');
    }
    this.pendingProps.videoBitrate = value ?? undefined;
  }
  setRatio(value: string | null): void {
    this.pendingProps.ratio = value ?? undefined;
  }

  commitProps(): void {
    const prev = this.props;
    this.props = cloneCameraProps(this.pendingProps);
    this.pendingProps = cloneCameraProps(this.props);
    const firstCommit = !this.propsCommitted;
    this.propsCommitted = true;
    this.updateOrientationListener();

    const barcodeChanged = prev.barcodeScannerEnabled !== this.props.barcodeScannerEnabled;
    const reload =
      firstCommit ||
      prev.facing !== this.props.facing ||
      prev.selectedLens !== this.props.selectedLens ||
      prev.pictureSize !== this.props.pictureSize ||
      prev.ratio !== this.props.ratio ||
      prev.mode !== this.props.mode ||
      prev.videoQuality !== this.props.videoQuality ||
      prev.active !== this.props.active;

    if (reload || barcodeChanged) {
      this.skipBarcodeAnalysis = false;
      this.barcodeWarningShown = false;
    }
    if (reload) {
      this.cancelRecordingStart();
      if (this.props.active === false) {
        this.ready = false;
        this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'The camera was deactivated during capture.'));
      }
      if (this.recording) {
        void this.finishRecording(true);
      } else {
        this.scheduleReconfigure();
      }
      return;
    }
    if (barcodeChanged && !this.recording) {
      this.scheduleReconfigure();
      return;
    }

    if (this.ready) this.applyControls();
  }

  async takePictureAsync(options: PictureOptions): Promise<ESObject> {
    return await this.takePicture(options);
  }

  async getAvailablePictureSizesAsync(): Promise<string[]> {
    this.assertMounted();
    return this.getAvailablePictureSizes();
  }

  async getAvailableLensesAsync(): Promise<string[]> {
    this.assertMounted();
    return this.getAvailableLenses();
  }

  async recordAsync(options: RecordingOptions): Promise<ESObject> {
    return await this.startRecording(options);
  }

  async toggleRecordingAsync(): Promise<ESObject> {
    return await this.toggleRecording();
  }
  async stopRecordingAsync(): Promise<ESObject> {
    return await this.stopRecording();
  }
  async resumePreviewAsync(): Promise<ESObject> {
    return await this.resumePreview();
  }
  async pausePreviewAsync(): Promise<ESObject> {
    return await this.pausePreview();
  }

  async launchModernScannerAsync(): Promise<ESObject> {
    this.assertMounted();
    throw new ExpoCameraError('ERR_CAMERA_SCANNER_UNAVAILABLE', 'The modern barcode scanner is not available on HarmonyOS.');
  }

  destroy(): void {
    if (this.destroyed) return;

    this.cancelRecordingStart();
    this.destroyed = true;
    this.ready = false;
    this.stopOrientationListener();
    this.rejectReadyWaiters(new ExpoCameraError('ERR_CAMERA_VIEW_DESTROYED', 'The camera view has been destroyed.'));
    this.rejectCapture(new ExpoCameraError('ERR_CAMERA_VIEW_DESTROYED', 'The camera view was unmounted during capture.'));

    try {
      this.manager.off('cameraStatus', this.onCameraStatus);
    } catch (_) {}

    this.reconfigurePending = true;
    const cleanup = this.recording ? this.finishRecording(true) : this.reconfigure();
    // A replacement view can mount before the old camera input has closed.
    viewCleanup = Promise.all([viewCleanup, cleanup]).then((): void => {}).catch((error: Object): void => {
      console.error(`Expo Camera view cleanup failed: ${String(error)}`);
    });
  }

  onBackground(): void {
    if (this.destroyed || this.backgrounded) return;

    this.cancelRecordingStart();
    this.backgrounded = true;
    this.updateOrientationListener();
    this.ready = false;
    this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'The app moved to the background during capture.'));

    if (this.recording) {
      void this.finishRecording(true);
    } else {
      this.scheduleReconfigure();
    }
  }

  onForeground(): void {
    if (this.destroyed || !this.backgrounded) return;

    this.backgrounded = false;
    this.updateOrientationListener();
    this.scheduleReconfigure();
  }

  private assertMounted(): void {
    if (this.destroyed) {
      throw new ExpoCameraError('ERR_CAMERA_VIEW_DESTROYED', 'The camera view has been destroyed.');
    }
  }

  private scheduleReconfigure(): void {
    if (this.destroyed) return;

    this.reconfigurePending = true;
    if (this.pendingCapture === undefined) void this.reconfigure();
  }

  private reconfigure(): Promise<void> {
    if (this.reconfiguring === undefined) {
      this.reconfiguring = this.runReconfigureLoop().finally((): void => {
        this.reconfiguring = undefined;
        if (this.reconfigurePending && !this.recording && this.pendingCapture === undefined) void this.reconfigure();
      });
    }
    return this.reconfiguring;
  }

  private canStartPreview(): boolean {
    return this.propsCommitted && !this.destroyed && !this.backgrounded && this.surfaceId !== undefined && this.props.active !== false;
  }

  private async runReconfigureLoop(): Promise<void> {
    while (this.reconfigurePending && !this.recording && this.pendingCapture === undefined) {
      this.reconfigurePending = false;

      try {
        await this.releasePipeline();
        if (!this.canStartPreview()) continue;
        await viewCleanup;
        if (this.reconfigurePending || !this.canStartPreview()) continue;

        await this.initializePreview();
      } catch (error) {
        if (this.reconfigurePending || !this.canStartPreview()) continue;
        console.error(`Expo Camera preview could not start: ${String(error)}`);

        this.ready = false;
        const message = `Camera preview could not start: ${String(error)}`;
        this.rejectReadyWaiters(new ExpoCameraError('ERR_CAMERA_NOT_READY', message));
        this.emit('onMountError', { message });
      }
    }
  }

  private selectedDevice(): camera.CameraDevice {
    const cameras = this.manager.getSupportedCameras();
    if (cameras.length === 0) throw new ExpoCameraError('ERR_CAMERA_UNAVAILABLE', 'No camera is available on this device.');

    const position = this.props.facing === 'front' ? camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK;
    const lens = this.props.selectedLens;
    if (lens !== undefined) {
      const selected = cameras.find((device: camera.CameraDevice): boolean => {
        return device.cameraId === lens && device.cameraPosition === position;
      });
      if (selected !== undefined) return selected;
    }

    const matching = cameras.find((device: camera.CameraDevice): boolean => device.cameraPosition === position);
    if (matching === undefined) {
      throw new ExpoCameraError('ERR_CAMERA_UNAVAILABLE', `No ${this.props.facing === 'front' ? 'front' : 'back'} camera is available.`);
    }
    return matching;
  }

  private getPhotoCapability(device: camera.CameraDevice): PhotoCapability {
    let scene: camera.CameraOutputCapability | undefined;
    try {
      scene = this.manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
    } catch (error) {
      console.warn(`Expo Camera could not query photo scene profiles: ${String(error)}`);
    }
    const scenePhoto = scene === undefined ? undefined : supportedPhotoProfiles(scene)[0];
    if (scene !== undefined && scene.previewProfiles.length > 0 && scenePhoto?.format === camera.CameraFormat.CAMERA_FORMAT_JPEG) {
      return { profiles: scene, useBasicSession: false };
    }

    // Prefer encoded JPEG, including when the complete pair is only available through the basic query.
    try {
      const basic = this.manager.getSupportedOutputCapability(device);
      const basicPhotos = supportedPhotoProfiles(basic);
      if (basic.previewProfiles.length > 0 &&
        (basicPhotos[0]?.format === camera.CameraFormat.CAMERA_FORMAT_JPEG || scene === undefined || scene.previewProfiles.length === 0 ||
          (scenePhoto === undefined && basicPhotos.length > 0))) {
        return { profiles: basic, useBasicSession: true };
      }
    } catch (error) {
      console.warn(`Expo Camera could not query basic photo profiles: ${String(error)}`);
    }
    if (scene === undefined) throw new ExpoCameraError('ERR_CAMERA_UNSUPPORTED', 'The selected camera exposes no usable photo scene.');
    return { profiles: scene, useBasicSession: false };
  }

  private async initializePreview(includePhoto: boolean = true): Promise<void> {
    const surface = this.surfaceId;
    if (surface === undefined || this.destroyed || this.backgrounded || this.props.active === false) return;

    const device = this.selectedDevice();
    const videoMode = this.props.mode === 'video';
    const photoCapability = videoMode ? undefined : this.getPhotoCapability(device);
    const capability = photoCapability?.profiles ?? this.manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_VIDEO);
    let photo: camera.Profile | undefined;
    let output: camera.Profile | undefined;

    if (videoMode) {
      output = chooseVideoProfile(capability.videoProfiles, this.props.videoQuality);
    } else if (includePhoto) {
      const photos = supportedPhotoProfiles(capability);
      if (photos.length > 0) {
        photo = choosePhotoProfile(photos, this.props.pictureSize, this.props.ratio);
        output = photo;
      }
    }

    const preview = choosePreviewProfile(capability.previewProfiles, output, this.props.ratio);

    const generation: number = this.pipelineGeneration;
    if (this.context.moduleContext.permissionStatus(CAMERA_PERMISSION) !== ExpoPermissionStatus.GRANTED) {
      throw new ExpoCameraError('ERR_CAMERA_PERMISSION', 'Camera permission is required to open the camera.');
    }

    const input = this.manager.createCameraInput(device);
    this.device = device;
    this.input = input;

    let addingPhoto = false;

    try {
      await input.open();
      this.assertPipelineGeneration(generation);

      const previewOut = this.manager.createPreviewOutput(preview, surface);
      this.previewOutput = previewOut;
      addingPhoto = photo !== undefined;
      const photoOut = photo === undefined ? undefined : this.manager.createPhotoOutput(photo);
      this.photoOutput = photoOut;
      this.photoFormat = photo?.format;
      if (photoOut !== undefined) {
        this.photoListener = (error: BusinessError, photo: camera.Photo): void => {
          if (generation !== this.pipelineGeneration) {
            if (photo !== undefined && photo !== null) void photo.release().catch((): void => {});
            return;
          }
          this.onPhoto(error, photo);
        };
        photoOut.on('photoAvailable', this.photoListener);
      }
      let modernSession: ModernSession | undefined;
      let session: ControllableSession;
      if (photoCapability?.useBasicSession === true) {
        session = this.manager.createCaptureSession();
      } else {
        modernSession = videoMode
          ? this.manager.createSession<camera.VideoSession>(camera.SceneMode.NORMAL_VIDEO)
          : this.manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
        session = modernSession;
      }
      this.session = session;
      session.beginConfig();
      session.addInput(input);
      session.addOutput(previewOut);
      if (photoOut !== undefined) {
        if (modernSession !== undefined && !modernSession.canAddOutput(photoOut)) {
          throw new ExpoCameraError('ERR_CAMERA_CAPTURE_UNSUPPORTED', 'The camera session cannot add its photo output.');
        }
        session.addOutput(photoOut);
      }
      if (modernSession !== undefined && this.props.barcodeScannerEnabled === true && !this.skipBarcodeAnalysis) {
        this.barcodeAnalyzer = await CameraBarcodeAnalyzer.attach(
          this.manager,
          modernSession,
          capability.previewProfiles,
          (): boolean => generation === this.pipelineGeneration && this.ready && !this.paused && !this.reconfigurePending &&
            this.props.barcodeScannerEnabled === true,
          (): string[] | undefined => this.props.barcodeScannerSettings?.barcodeTypes,
          (result: BarcodeResult): void => this.emit('onBarcodeScanned', result),
        );
        this.assertPipelineGeneration(generation);
        if (this.barcodeAnalyzer === undefined) this.warnBarcodeUnavailable();
      }
      await session.commitConfig();
      this.assertPipelineGeneration(generation);
      this.listenForSessionErrors(session, generation);

      this.applyControls();
      await session.start();
      this.assertPipelineGeneration(generation);
      this.observePreviewRotation(previewOut, generation);

      if (this.paused) await session.stop();
      this.assertPipelineGeneration(generation);
      this.ready = true;
      this.resolveReadyWaiters();
      this.emit('onAvailableLensesChanged', { lenses: this.getAvailableLenses() });
      this.emit('onCameraReady');
    } catch (error) {
      const retryWithoutPhoto = addingPhoto && this.barcodeAnalyzer === undefined;
      if (this.barcodeAnalyzer !== undefined && !this.reconfigurePending && this.canStartPreview()) {
        this.skipBarcodeAnalysis = true;
        this.reconfigurePending = true;
        this.warnBarcodeUnavailable();
      }
      await this.releasePipeline();
      if (retryWithoutPhoto && !this.reconfigurePending && this.canStartPreview()) {
        console.warn(`Expo Camera could not configure photo capture: ${String(error)}`);
        await this.initializePreview(false);
        return;
      }
      if (error instanceof ExpoCameraError) throw new ExpoCameraError(error.code, error.message, error.cause);
      throw new ExpoCameraError('ERR_CAMERA_INITIALIZATION', `The Harmony camera pipeline could not be initialized: ${String(error)}`);
    }
  }

  private warnBarcodeUnavailable(): void {
    if (this.barcodeWarningShown) return;
    this.barcodeWarningShown = true;
    console.warn('Expo Camera cannot add a live barcode analysis stream to the current camera session.');
  }

  private assertPipelineGeneration(generation: number): void {
    if (generation !== this.pipelineGeneration || this.reconfigurePending || !this.canStartPreview()) {
      throw new ExpoCameraError('ERR_CAMERA_INITIALIZATION_CANCELLED', 'Camera initialization was cancelled by a lifecycle or surface change.');
    }
  }

  private observePreviewRotation(output: camera.PreviewOutput, generation: number): void {
    let displayRotation: number | undefined;
    const update = (): void => {
      if (generation !== this.pipelineGeneration || this.reconfigurePending || !this.canStartPreview()) return;
      try {
        const degrees = display.getDefaultDisplaySync().rotation * 90;
        if (displayRotation === degrees) return;
        output.setPreviewRotation(output.getPreviewRotation(degrees));
        displayRotation = degrees;
      } catch (error) {
        console.warn(`Expo Camera could not configure preview rotation: ${String(error)}`);
      }
    };
    update();
    try {
      display.on('change', update);
      this.displayChangeListener = update;
    } catch (error) {
      console.warn(`Expo Camera could not observe display changes: ${String(error)}`);
    }
  }

  private listenForSessionErrors(session: ControllableSession, generation: number): void {
    this.sessionErrorListener = (error: BusinessError): void => {
      if (generation === this.pipelineGeneration) this.onSessionError(error);
    };
    session.on('error', this.sessionErrorListener);
  }

  private applyControls(): void {
    const session = this.session;
    if (session === undefined) return;

    try {
      const flashMode =
        this.props.flashMode === 'on' || (this.props.flashMode === 'screen' && this.props.facing !== 'front')
          ? camera.FlashMode.FLASH_MODE_OPEN
          : this.props.flashMode === 'auto'
            ? camera.FlashMode.FLASH_MODE_AUTO
            : camera.FlashMode.FLASH_MODE_CLOSE;
      if (session.hasFlash() && session.isFlashModeSupported(flashMode)) session.setFlashMode(flashMode);
    } catch (_) {}

    try {
      this.setTorch(this.props.enableTorch === true);
    } catch (_) {}

    try {
      const range = session.getZoomRatioRange();
      if (range.length >= 2) {
        const zoom = clamp(this.props.zoom ?? 0, 0, 1);
        const max = range[range.length - 1];
        session.setZoomRatio(clamp(Math.max(1, zoom * max), range[0], max));
      }
    } catch (_) {}

    try {
      const focus = this.props.autoFocus === 'on' ? camera.FocusMode.FOCUS_MODE_AUTO : camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO;
      if (session.isFocusModeSupported(focus)) session.setFocusMode(focus);
    } catch (_) {}
  }

  private setTorch(enabled: boolean): void {
    try {
      const mode = enabled ? camera.TorchMode.ON : camera.TorchMode.OFF;
      if (this.manager.isTorchModeSupported(mode)) this.manager.setTorchMode(mode);
    } catch (_) {}
  }

  private updateOrientationListener(): void {
    const enabled =
      this.props.responsiveOrientationWhenOrientationLocked === true && !this.destroyed && !this.backgrounded && this.props.active !== false;
    if (enabled === this.orientationListening) return;

    if (enabled) {
      try {
        sensor.on(sensor.SensorId.GRAVITY, this.onGravity, { interval: 200_000_000 });
        this.orientationListening = true;
      } catch (_) {}
    } else {
      this.stopOrientationListener();
    }
  }

  private stopOrientationListener(): void {
    if (!this.orientationListening) return;

    try {
      sensor.off(sensor.SensorId.GRAVITY, this.onGravity);
    } catch (_) {}

    this.orientationListening = false;
    this.orientation = undefined;
    this.deviceDegree = undefined;
  }

  private captureDeviceDegree(): number {
    if (this.props.responsiveOrientationWhenOrientationLocked === true && this.deviceDegree !== undefined) {
      return this.deviceDegree;
    }
    // Display.rotation uses quarter turns. CameraKit expects degrees on API 12–22.
    return display.getDefaultDisplaySync().rotation * 90;
  }

  private awaitReady(): Promise<void> {
    if (this.ready && !this.reconfigurePending) return this.previewTransition;
    if (this.destroyed) {
      return Promise.reject(new ExpoCameraError('ERR_CAMERA_VIEW_DESTROYED', 'The camera view has been destroyed.'));
    }

    return new Promise<void>((resolve: () => void, reject: (error: ExpoCameraError) => void): void => {
      const timer = setTimeout((): void => {
        const index = this.readyWaiters.findIndex((waiter: ReadyWaiter): boolean => waiter.timer === timer);
        if (index >= 0) this.readyWaiters.splice(index, 1);

        reject(new ExpoCameraError('ERR_CAMERA_NOT_READY', 'The camera preview did not become ready in time.'));
      }, 5000);

      this.readyWaiters.push({ resolve, reject, timer });
    });
  }

  private resolveReadyWaiters(): void {
    const waiters = this.readyWaiters.splice(0);
    waiters.forEach((waiter: ReadyWaiter): void => {
      clearTimeout(waiter.timer);
      waiter.resolve();
    });
  }

  private rejectReadyWaiters(error: ExpoCameraError): void {
    const waiters = this.readyWaiters.splice(0);
    waiters.forEach((waiter: ReadyWaiter): void => {
      clearTimeout(waiter.timer);
      waiter.reject(error);
    });
  }

  private async takePicture(options: PictureOptions): Promise<ESObject> {
    if (options.quality !== undefined && (!Number.isFinite(options.quality) || options.quality < 0 || options.quality > 1)) {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', 'Photo quality must be a number between 0 and 1.');
    }
    if (options.maxDownsampling !== undefined && (!Number.isSafeInteger(options.maxDownsampling) || options.maxDownsampling < 1)) {
      throw new ExpoCameraError('ERR_CAMERA_INVALID_OPTION', 'Maximum downsampling must be a positive integer.');
    }
    if (this.props.mode === 'video') throw new ExpoCameraError('ERR_CAMERA_WRONG_MODE', 'Cannot take a picture while the camera is in video mode.');
    if (this.recording) throw new ExpoCameraError('ERR_CAMERA_CAPTURE_DURING_RECORDING', 'Cannot take a picture while recording.');
    if (this.paused) throw new ExpoCameraError('ERR_CAMERA_PREVIEW_PAUSED', 'Cannot take a picture while preview is paused.');
    if (this.pendingCapture !== undefined || this.captureStarting) {
      throw new ExpoCameraError('ERR_CAMERA_CAPTURE_IN_PROGRESS', 'A photo capture is already in progress.');
    }

    this.captureStarting = true;
    const captureGeneration: number = this.captureGeneration + 1;
    this.captureGeneration = captureGeneration;

    if (options.shutterSound === false && !this.shutterWarningShown) {
      console.warn('Disabling the system camera shutter sound is not supported by HarmonyOS CameraKit.');
      this.shutterWarningShown = true;
    }

    try {
      await this.awaitReady();
      await this.previewTransition;
      if (captureGeneration !== this.captureGeneration) {
        throw new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'Photo capture was interrupted.');
      }
      if (this.paused) throw new ExpoCameraError('ERR_CAMERA_PREVIEW_PAUSED', 'Cannot take a picture while preview is paused.');
    } catch (error) {
      if (captureGeneration === this.captureGeneration) this.captureStarting = false;
      if (error instanceof ExpoCameraError) throw new ExpoCameraError(error.code, error.message, error.cause);
      throw new ExpoCameraError('ERR_CAMERA_NOT_READY', `The Harmony camera did not become ready for capture: ${String(error)}`);
    }

    const output = this.photoOutput;
    const format = this.photoFormat;
    if (output === undefined || format === undefined) {
      if (captureGeneration === this.captureGeneration) this.captureStarting = false;
      throw new ExpoCameraError('ERR_CAMERA_CAPTURE_UNSUPPORTED', 'The current camera session does not support photo capture.');
    }

    if (this.props.flashMode === 'screen' && this.props.facing === 'front') {
      this.flash?.();
      await wait(120);
    } else if (this.props.animateShutter !== false) {
      this.flash?.();
    }

    if (captureGeneration !== this.captureGeneration) {
      throw new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'Photo capture was interrupted.');
    }
    if (this.paused) {
      this.captureStarting = false;
      throw new ExpoCameraError('ERR_CAMERA_PREVIEW_PAUSED', 'Cannot take a picture while preview is paused.');
    }

    const setting: camera.PhotoCaptureSetting = {
      quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
    };
    let rawRotation: camera.ImageRotation | undefined;
    try {
      const rotation = output.getPhotoRotation(this.captureDeviceDegree());
      if (format === camera.CameraFormat.CAMERA_FORMAT_RGBA_8888) {
        rawRotation = rotation;
        setting.rotation = camera.ImageRotation.ROTATION_0;
      } else {
        setting.rotation = rotation;
      }
    } catch (error) {
      if (format !== camera.CameraFormat.CAMERA_FORMAT_RGBA_8888) {
        if (captureGeneration === this.captureGeneration) this.captureStarting = false;
        throw new ExpoCameraError('ERR_CAMERA_CAPTURE_ROTATION', `Could not determine photo rotation: ${String(error)}`);
      }
      console.warn(`Expo Camera could not determine RGBA photo rotation: ${String(error)}`);
    }
    const mirror = this.props.facing === 'front' && (options.mirror === true || this.props.mirror === true);
    let softwareMirror = mirror;

    try {
      if (mirror && output.isMirrorSupported()) {
        setting.mirror = true;
        softwareMirror = false;
      }
    } catch (_) {}

    if (options.fastMode === true) {
      const pending: PendingCapture = { options, softwareMirror, format, rawRotation };
      this.setPendingCapture(pending);

      try {
        await output.capture(setting);
      } catch (error) {
        console.error(`Expo Camera photo capture failed: ${String(error)}`);

        if (this.pendingCapture === pending) {
          this.reconfigurePending = true;
          this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_FAILED', 'Photo capture failed.'));
        }

        throw new ExpoCameraError('ERR_CAMERA_CAPTURE_FAILED', 'Photo capture failed.');
      }

      return null;
    }

    return await new Promise<ESObject>((resolve: (value: ESObject) => void, reject: (error: ExpoCameraError) => void): void => {
      const pending: PendingCapture = { options, softwareMirror, format, rawRotation, resolve, reject };
      this.setPendingCapture(pending);

      const onFailure = (error: Object): void => {
        console.error(`Expo Camera photo capture failed: ${String(error)}`);
        if (this.pendingCapture === pending) {
          this.reconfigurePending = true;
          this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_FAILED', 'Photo capture failed.'));
        }
      };
      try {
        output.capture(setting).catch(onFailure);
      } catch (error) {
        onFailure(error as Object);
      }
    });
  }

  private setPendingCapture(pending: PendingCapture): void {
    if (this.pendingCapture !== undefined) {
      this.captureStarting = false;
      throw new ExpoCameraError('ERR_CAMERA_CAPTURE_IN_PROGRESS', 'A photo capture is already in progress.');
    }
    pending.timer = setTimeout((): void => {
      if (this.pendingCapture !== pending) return;

      // A timed-out native capture can still deliver a photo. Retire its output before accepting another request.
      this.reconfigurePending = true;
      this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_TIMEOUT', 'The camera did not deliver a captured photo in time.'));
    }, CAPTURE_TIMEOUT_MS);

    this.pendingCapture = pending;
    this.captureStarting = false;
  }

  private async consumePhoto(photo: camera.Photo, pending: PendingCapture): Promise<void> {
    if (this.pendingCapture !== pending) {
      await photo.release().catch((): void => {});
      return;
    }

    let result: PictureResult | undefined;
    let pixel: image.PixelMap | undefined;
    let delivered = false;
    const returnsReference = pending.options.pictureRef === true && pending.options.fastMode !== true;
    try {
      result = await this.processPhoto(photo.main, pending);

      if (this.pendingCapture !== pending) return;

      if (pending.options.fastMode === true) {
        this.emit('onPictureSaved', { id: pending.options.id ?? 0, data: result });
      } else {
        let output: ESObject = result;
        if (returnsReference) {
          const source: image.ImageSource = image.createImageSource(filePathFromUri(result.uri));
          try {
            pixel = await source.createPixelMap();
          } finally {
            await source.release().catch((): void => {});
          }
          if (this.pendingCapture !== pending) return;
          output = this.pictureRefFactory(pixel, result.width, result.height);
          pixel = undefined;
        }
        pending.resolve?.(output);
      }
      delivered = true;
    } catch (error) {
      console.error(`Expo Camera photo processing failed: ${String(error)}`);

      if (pending.options.fastMode === true) {
        console.error('Expo Camera could not deliver the fast-mode photo result.');
      } else {
        pending.reject?.(new ExpoCameraError('ERR_CAMERA_CAPTURE_PROCESSING', 'The captured photo could not be saved.'));
      }
    } finally {
      if (pixel !== undefined) await pixel.release().catch((): void => {});
      // Only URI results transfer the cache file to the caller. PictureRef owns its PixelMap instead.
      if (result !== undefined && (!delivered || returnsReference)) {
        try {
          fs.unlinkSync(filePathFromUri(result.uri));
        } catch (_) {}
      }
      if (this.pendingCapture === pending) this.pendingCapture = undefined;

      try {
        await photo.release();
      } catch (_) {}

      if (this.reconfigurePending) void this.reconfigure();
    }
  }

  private async processPhoto(photo: image.Image, pending: PendingCapture): Promise<PictureResult> {
    const options = pending.options;
    let jpeg: ArrayBuffer | undefined;
    let source: image.ImageSource | undefined;
    let pixel: image.PixelMap | undefined;
    let path: string | undefined;
    let saved = false;

    try {
      const raw = pending.format === camera.CameraFormat.CAMERA_FORMAT_RGBA_8888;
      let properties = {} as Record<image.PropertyKey, string | null>;
      let info: image.ImageInfo;
      if (raw) {
        const capture = await readRgbaPhoto(photo);
        jpeg = capture.jpeg;
        pixel = capture.pixel;
      } else {
        jpeg = (await photo.getComponent(image.ComponentType.JPEG)).byteBuffer;
      }

      if (jpeg !== undefined) {
        source = image.createImageSource(jpeg);
        info = await source.getImageInfo();
        try {
          const keys = options.exif === true ? EXIF_KEYS : [image.PropertyKey.ORIENTATION];
          properties = await source.getImageProperties(keys);
        } catch (_) {}
      } else if (pixel !== undefined) {
        info = await pixel.getImageInfo();
      } else {
        throw new ExpoCameraError('ERR_CAMERA_CAPTURE_PROCESSING', 'The captured photo is empty.');
      }

      const orientation = orientationCode(properties[image.PropertyKey.ORIENTATION]);
      const skip = options.skipProcessing === true;
      const format = !skip && options.imageType === 'png' ? 'png' : 'jpg';
      let width = info.size.width;
      let height = info.size.height;

      const dir = `${this.context.moduleContext.cachePath}/expo-camera`;
      await ensureDirectory(dir);
      path = uniquePath(dir, 'photo', format, this.tag);

      if (skip && jpeg !== undefined) {
        await writeBuffer(path, jpeg);
      } else {
        if (pixel === undefined && source !== undefined) pixel = await decodePixelMap(source, options.maxDownsampling);
        if (pixel === undefined) throw new ExpoCameraError('ERR_CAMERA_CAPTURE_PROCESSING', 'The captured photo could not be decoded.');

        if (!skip) {
          if (raw && pending.rawRotation !== undefined && pending.rawRotation !== camera.ImageRotation.ROTATION_0) {
            await pixel.rotate(pending.rawRotation);
          }
          await transformPixelMap(pixel, orientation, pending.softwareMirror);
          const size = (await pixel.getImageInfo()).size;
          width = size.width;
          height = size.height;
        }

        await packPicture(path, pixel, {
          format: format === 'png' ? 'image/png' : 'image/jpeg',
          quality: skip ? 100 : Math.round(clamp(options.quality ?? 1, 0, 1) * 100),
          needsPackProperties: options.exif === true,
        });
      }

      if (!skip && options.exif === true) {
        const records = writableExifProperties(properties);
        records[image.PropertyKey.ORIENTATION] = '1';
        records[image.PropertyKey.IMAGE_WIDTH] = String(width);
        records[image.PropertyKey.IMAGE_LENGTH] = String(height);
        records[image.PropertyKey.PIXEL_X_DIMENSION] = String(width);
        records[image.PropertyKey.PIXEL_Y_DIMENSION] = String(height);

        const additional = options.additionalExif;
        if (additional !== undefined) {
          const encoded = encodeExifMetadata(additional);
          Object.keys(encoded).forEach((key: string): void => {
            records[key as image.PropertyKey] = encoded[key as image.PropertyKey];
          });
        }

        const output = image.createImageSource(path);
        try {
          await output.modifyImageProperties(records);
        } catch (error) {
          throw new ExpoCameraError('ERR_CAMERA_EXIF_WRITE', `The captured photo metadata could not be saved: ${String(error)}`);
        } finally {
          try {
            await output.release();
          } catch (_) {}
        }
      }

      const result = new PictureResult(fileUriFromPath(path), width, height, format);
      if (options.base64 === true) {
        const bytes: ArrayBuffer = skip && jpeg !== undefined ? jpeg : await readBuffer(path);
        result.base64 = await new util.Base64Helper().encodeToString(new Uint8Array(bytes));
      }

      if (options.exif === true) {
        const exif = decodeExifProperties(properties);
        if (!skip) {
          exif[image.PropertyKey.ORIENTATION] = 1;
          exif[image.PropertyKey.IMAGE_WIDTH] = width;
          exif[image.PropertyKey.IMAGE_LENGTH] = height;
          exif[image.PropertyKey.PIXEL_X_DIMENSION] = width;
          exif[image.PropertyKey.PIXEL_Y_DIMENSION] = height;
        }

        const additional = options.additionalExif;
        if (additional !== undefined) {
          Object.keys(additional).forEach((key: string): void => {
            exif[key] = additional[key];
          });
        }

        result.exif = exif;
      }

      if (options.pictureRef === true) result.pictureRef = true;

      saved = true;
      return result;
    } finally {
      if (!saved && path !== undefined) {
        try {
          fs.unlinkSync(path);
        } catch (_) {}
      }
      if (pixel !== undefined) {
        try {
          await pixel.release();
        } catch (_) {}
      }

      try {
        await source?.release();
      } catch (_) {}
    }
  }

  private rejectCapture(error: ExpoCameraError): void {
    this.captureGeneration += 1;
    const pending = this.pendingCapture;
    this.pendingCapture = undefined;
    this.captureStarting = false;

    if (pending?.timer !== undefined) clearTimeout(pending.timer);

    pending?.reject?.(error);
    if (pending?.options.fastMode === true) console.error(`Expo Camera fast-mode capture failed: ${error.message}`);
    if (this.reconfigurePending) void this.reconfigure();
  }

  private getAvailablePictureSizes(): string[] {
    if (this.ready && this.props.mode !== 'video' && this.photoOutput === undefined) return [];

    const device = this.device ?? this.selectedDevice();

    return supportedPhotoProfiles(this.getPhotoCapability(device).profiles)
      .sort((left: camera.Profile, right: camera.Profile): number => profilePixels(right) - profilePixels(left))
      .map((profile: camera.Profile): string => profileSize(profile));
  }

  private getAvailableLenses(): string[] {
    const facing = this.props.facing === 'front' ? camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK;

    return this.manager
      .getSupportedCameras()
      .filter((device: camera.CameraDevice): boolean => device.cameraPosition === facing)
      .map((device: camera.CameraDevice): string => device.cameraId);
  }

  private async startRecording(options: RecordingOptions): Promise<ESObject> {
    if (this.recording || this.recordingStarting) {
      throw new ExpoCameraError('ERR_CAMERA_RECORDING_IN_PROGRESS', 'A video recording is already in progress.');
    }

    this.recordingStarting = true;
    this.recordingStartCancelled = false;
    try {
      if (this.paused) {
        throw new ExpoCameraError('ERR_CAMERA_PREVIEW_PAUSED', 'Cannot record while preview is paused.');
      }
      if (this.props.mode !== 'video') throw new ExpoCameraError('ERR_CAMERA_WRONG_MODE', 'Cannot record while the camera is in picture mode.');
      if (this.surfaceId === undefined) throw new ExpoCameraError('ERR_CAMERA_NOT_READY', 'The camera preview surface is unavailable.');

      if (this.props.mute !== true) {
        const granted = this.context.moduleContext.permissionStatus(MICROPHONE_PERMISSION) === ExpoPermissionStatus.GRANTED;
        if (!granted) {
          throw new ExpoCameraError('ERR_CAMERA_MICROPHONE_PERMISSION', 'Microphone permission is required to record video with audio.');
        }
      }

      await this.awaitReady();
      await this.previewTransition;
      this.assertRecordingStart(this.pipelineGeneration);
      if (this.paused) throw new ExpoCameraError('ERR_CAMERA_PREVIEW_PAUSED', 'Cannot record while preview is paused.');

      const result: Promise<ESObject> = new Promise<ESObject>(
        (resolve: (value: ESObject) => void, reject: (error: ExpoCameraError) => void): void => {
          this.resolveRecording = resolve;
          this.rejectRecording = reject;
        },
      );

      this.recording = true;
      this.recordingInitialization = this.prepareVideoRecording(options);
      void this.recordingInitialization.catch((): Promise<void> => this.finishRecording(true));

      return await result;
    } finally {
      this.recordingStarting = false;
    }
  }

  private cancelRecordingStart(): void {
    if (this.recordingStarting) this.recordingStartCancelled = true;
  }

  private assertRecordingStart(generation: number): void {
    if (this.recordingStartCancelled) {
      throw new ExpoCameraError('ERR_CAMERA_RECORDING_CANCELLED', 'Video recording was cancelled before it started.');
    }
    this.assertPipelineGeneration(generation);
  }

  private async prepareVideoRecording(options: RecordingOptions): Promise<void> {
    const cleanup = viewCleanup;
    await this.releasePipeline();
    await cleanup;
    await this.initializeVideoRecording(options);
  }

  private async initializeVideoRecording(options: RecordingOptions): Promise<void> {
    const generation = this.pipelineGeneration;
    this.assertRecordingStart(generation);
    const surface = this.surfaceId;
    if (surface === undefined) throw new ExpoCameraError('ERR_CAMERA_NOT_READY', 'The camera preview surface is unavailable.');

    const device = this.selectedDevice();
    const capability = this.manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_VIDEO);

    const video = chooseVideoProfile(capability.videoProfiles, this.props.videoQuality);
    const preview = choosePreviewProfile(capability.previewProfiles, video);

    const dir = `${this.context.moduleContext.cachePath}/expo-camera`;
    await ensureDirectory(dir);
    this.assertRecordingStart(generation);
    const path = uniquePath(dir, 'video', 'mp4', this.tag);
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);

    this.recordingFile = file;
    this.recordingPath = path;

    const recorder = await media.createAVRecorder();
    this.recorder = recorder;
    this.assertRecordingStart(generation);

    const encoders = await recorder.getAvailableEncoder();
    this.assertRecordingStart(generation);
    const supportsAvc = encoders.some(
      (encoder: media.EncoderInfo): boolean => encoder.type === 'video' && encoder.mimeType === media.CodecMimeType.VIDEO_AVC,
    );
    const supportsHevc = encoders.some(
      (encoder: media.EncoderInfo): boolean => encoder.type === 'video' && encoder.mimeType === media.CodecMimeType.VIDEO_HEVC,
    );
    let codec = media.CodecMimeType.VIDEO_AVC;

    if (options.codec === 'hvc1') {
      if (!supportsHevc) throw new ExpoCameraError('ERR_CAMERA_CODEC_UNSUPPORTED', "The requested video codec 'hvc1' is not supported.");
      codec = media.CodecMimeType.VIDEO_HEVC;
    } else if (options.codec === 'avc1') {
      if (!supportsAvc) throw new ExpoCameraError('ERR_CAMERA_CODEC_UNSUPPORTED', "The requested video codec 'avc1' is not supported.");
    } else if (options.codec !== undefined) {
      throw new ExpoCameraError('ERR_CAMERA_CODEC_UNSUPPORTED', `The requested video codec '${options.codec}' is not supported.`);
    } else if (!supportsAvc && supportsHevc) {
      codec = media.CodecMimeType.VIDEO_HEVC;
    } else if (!supportsAvc) {
      throw new ExpoCameraError('ERR_CAMERA_CODEC_UNSUPPORTED', 'The device exposes no supported video encoder.');
    }

    const profile: media.AVRecorderProfile = {
      fileFormat: media.ContainerFormatType.CFT_MPEG_4,
      videoBitrate: this.props.videoBitrate ?? 8_000_000,
      videoCodec: codec,
      videoFrameWidth: video.size.width,
      videoFrameHeight: video.size.height,
      videoFrameRate: clamp(video.frameRateRange.max, 1, 60),
    };
    const config: media.AVRecorderConfig = {
      videoSourceType: media.VideoSourceType.VIDEO_SOURCE_TYPE_SURFACE_YUV,
      profile,
      url: `fd://${file.fd}`,
    };
    if (this.props.mute !== true) {
      config.audioSourceType = media.AudioSourceType.AUDIO_SOURCE_TYPE_CAMCORDER;
      profile.audioBitrate = 128_000;
      profile.audioChannels = 2;
      profile.audioCodec = media.CodecMimeType.AUDIO_AAC;
      profile.audioSampleRate = 48_000;
    }

    await recorder.prepare(config);
    this.assertRecordingStart(generation);
    const inputSurface = await recorder.getInputSurface();
    this.assertRecordingStart(generation);
    if (this.context.moduleContext.permissionStatus(CAMERA_PERMISSION) !== ExpoPermissionStatus.GRANTED) {
      throw new ExpoCameraError('ERR_CAMERA_PERMISSION', 'Camera permission is required to open the camera.');
    }

    const input = this.manager.createCameraInput(device);
    this.device = device;
    this.input = input;
    await input.open();
    this.assertRecordingStart(generation);

    const previewOut = this.manager.createPreviewOutput(preview, surface);
    this.previewOutput = previewOut;
    const videoOut = this.manager.createVideoOutput(video, inputSurface);
    this.videoOutput = videoOut;
    const session = this.manager.createSession<camera.VideoSession>(camera.SceneMode.NORMAL_VIDEO);
    this.session = session;
    session.beginConfig();
    session.addInput(input);
    session.addOutput(previewOut);
    session.addOutput(videoOut);
    await session.commitConfig();
    this.assertRecordingStart(generation);
    this.listenForSessionErrors(session, generation);

    this.applyControls();
    this.applyVideoStabilization(session);

    const mirror = this.props.facing === 'front' && (options.mirror === true || this.props.mirror === true);

    try {
      if (deviceInfo.sdkApiVersion >= 15 && videoOut.isMirrorSupported()) {
        videoOut.enableMirror(mirror);
      } else if (mirror) {
        console.warn('Mirror recording is not supported by the selected HarmonyOS camera.');
      }
    } catch (error) {
      console.warn(`Expo Camera could not configure mirror recording: ${String(error)}`);
    }
    try {
      await recorder.updateRotation(videoOut.getVideoRotation(this.captureDeviceDegree()));
    } catch (error) {
      console.warn(`Expo Camera could not configure video rotation: ${String(error)}`);
    }
    this.assertRecordingStart(generation);

    recorder.on('stateChange', (state: media.AVRecorderState, _: media.StateChangeReason): void => {
      if (this.recorder === recorder && state === 'stopped' && this.recording && !this.finishing) void this.finishRecording(false);
    });
    recorder.on('error', (error: BusinessError): void => {
      if (this.recorder === recorder && this.recording && !this.finishing) {
        console.error(`Expo Camera video recorder failed: ${String(error)}`);
        void this.failRecording(new ExpoCameraError('ERR_CAMERA_RECORDING', 'Video recording failed.'));
      }
    });

    await session.start();
    this.assertRecordingStart(generation);
    this.observePreviewRotation(previewOut, generation);
    await videoOut.start();
    this.assertRecordingStart(generation);
    await recorder.start();
    this.assertRecordingStart(generation);

    this.ready = true;
    this.resolveReadyWaiters();

    if (options.maxDuration !== undefined && Number.isFinite(options.maxDuration) && options.maxDuration > 0) {
      this.durationLeft = Math.max(1, Math.floor(options.maxDuration * 1000));
      this.resumeDurationTimer();
    }
    if (options.maxFileSize !== undefined && Number.isFinite(options.maxFileSize) && options.maxFileSize > 0) {
      const limit = Math.floor(options.maxFileSize);
      let statWarningShown = false;
      this.sizeTimer = setInterval((): void => {
        void fs
          .stat(path)
          .then((stat: fs.Stat): void => {
            if (this.recorder === recorder && stat.size >= limit) void this.finishRecording(true);
          })
          .catch((error: Object): void => {
            if (!statWarningShown) {
              console.warn(`Expo Camera could not inspect the recording file yet: ${String(error)}`);
              statWarningShown = true;
            }
          });
      }, 250);
    }
  }

  private applyVideoStabilization(session: camera.VideoSession): void {
    const requested = this.props.videoStabilizationMode;
    const mode =
      requested === 'off'
        ? camera.VideoStabilizationMode.OFF
        : requested === 'standard'
          ? camera.VideoStabilizationMode.LOW
          : requested === 'cinematic'
            ? camera.VideoStabilizationMode.HIGH
            : camera.VideoStabilizationMode.AUTO;

    try {
      if (session.isVideoStabilizationModeSupported(mode)) {
        session.setVideoStabilizationMode(mode);
      } else if (mode !== camera.VideoStabilizationMode.OFF && session.isVideoStabilizationModeSupported(camera.VideoStabilizationMode.LOW)) {
        session.setVideoStabilizationMode(camera.VideoStabilizationMode.LOW);
      }
    } catch (_) {}
  }

  private async toggleRecording(): Promise<ESObject> {
    const transition = this.recordingTransition.then(async (): Promise<void> => {
      const recorder = this.recorder;
      if (!this.ready || !this.recording || this.finishing || recorder === undefined) return;

      if (recorder.state === 'started') {
        await recorder.pause();
        this.pauseDurationTimer();
      } else if (recorder.state === 'paused') {
        await recorder.resume();
        this.resumeDurationTimer();
      }
    });
    this.recordingTransition = transition.catch((): void => {});
    await transition;

    return null;
  }

  private async stopRecording(): Promise<ESObject> {
    this.cancelRecordingStart();
    if (this.recording) await this.finishRecording(true);
    return null;
  }

  private finishRecording(stopRecorder: boolean, error?: ExpoCameraError): Promise<void> {
    if (this.recordingFinish !== undefined) return this.recordingFinish;
    if (!this.recording) return Promise.resolve();

    this.finishing = true;
    this.cancelRecordingStart();
    this.recordingFinish = this.completeRecording(stopRecorder, error);
    return this.recordingFinish;
  }

  private async completeRecording(stopRecorder: boolean, error?: ExpoCameraError): Promise<void> {
    let failure = error;
    // Initialization owns the resources until its current native operation settles.
    // Keep recording true through cleanup so preview reconfiguration cannot overlap it.
    try {
      await this.recordingInitialization;
    } catch (initializationError) {
      if (failure === undefined) {
        if (
          initializationError instanceof ExpoCameraError &&
          (initializationError.code === 'ERR_CAMERA_RECORDING_CANCELLED' || initializationError.code === 'ERR_CAMERA_INITIALIZATION_CANCELLED')
        ) {
          failure = new ExpoCameraError('ERR_CAMERA_RECORDING_CANCELLED', 'Video recording was cancelled before it started.');
        } else if (initializationError instanceof ExpoCameraError) {
          failure = new ExpoCameraError(initializationError.code, initializationError.message, initializationError.cause);
        } else {
          console.error(`Expo Camera recording could not start: ${String(initializationError)}`);
          failure = new ExpoCameraError('ERR_CAMERA_RECORDING_START', 'Video recording could not start.');
        }
      }
    }

    await this.recordingTransition;
    this.clearRecordingLimits();
    const path = this.recordingPath;

    try {
      if (stopRecorder && this.recorder !== undefined && (this.recorder.state === 'started' || this.recorder.state === 'paused')) {
        await this.recorder.stop();
      }

      if (this.videoOutput !== undefined) {
        try {
          await this.videoOutput.stop();
        } catch (_) {}
      }
    } catch (error) {
      console.error(`Expo Camera recording could not stop: ${String(error)}`);
      failure = failure ?? new ExpoCameraError('ERR_CAMERA_RECORDING_STOP', 'Video recording could not stop cleanly.');
    }

    await this.releasePipeline();
    const resolve = this.resolveRecording;
    const reject = this.rejectRecording;
    this.resolveRecording = undefined;
    this.rejectRecording = undefined;
    this.recordingPath = undefined;
    this.recordingInitialization = undefined;
    this.recording = false;
    this.finishing = false;
    this.recordingFinish = undefined;

    if (failure !== undefined) {
      if (path !== undefined) {
        try {
          fs.unlinkSync(path);
        } catch (_) {}
      }
      reject?.(failure);
    } else if (path === undefined) {
      reject?.(new ExpoCameraError('ERR_CAMERA_RECORDING_FILE', 'The video recorder did not create an output file.'));
    } else {
      resolve?.(new VideoResult(fileUriFromPath(path)));
    }
    if (!this.destroyed) this.scheduleReconfigure();
  }

  private failRecording(error: ExpoCameraError): Promise<void> {
    return this.finishRecording(true, error);
  }

  private resumeDurationTimer(): void {
    if (this.durationLeft <= 0 || this.durationTimer !== undefined) return;

    this.durationStarted = Date.now();
    this.durationTimer = setTimeout((): void => {
      this.durationTimer = undefined;
      this.durationLeft = 0;
      void this.finishRecording(true);
    }, this.durationLeft);
  }

  private pauseDurationTimer(): void {
    if (this.durationTimer === undefined) return;

    clearTimeout(this.durationTimer);
    this.durationTimer = undefined;
    this.durationLeft = Math.max(0, this.durationLeft - (Date.now() - this.durationStarted));
  }

  private clearRecordingLimits(): void {
    if (this.durationTimer !== undefined) clearTimeout(this.durationTimer);
    if (this.sizeTimer !== undefined) clearInterval(this.sizeTimer);

    this.durationTimer = undefined;
    this.sizeTimer = undefined;
    this.durationLeft = 0;
    this.durationStarted = 0;
  }

  private async pausePreview(): Promise<ESObject> {
    return await this.changePreviewPaused(true);
  }

  private async resumePreview(): Promise<ESObject> {
    return await this.changePreviewPaused(false);
  }

  private async changePreviewPaused(paused: boolean): Promise<ESObject> {
    if (this.recording) {
      if (paused) throw new ExpoCameraError('ERR_CAMERA_PREVIEW_DURING_RECORDING', 'Cannot pause preview while recording.');
      return null;
    }

    if (!paused && !this.ready && this.reconfiguring === undefined && this.canStartPreview()) this.scheduleReconfigure();
    await this.awaitReady();

    const transition = this.previewTransition.then(async (): Promise<void> => {
      if (this.paused === paused) return;
      const session = this.session;
      if (!this.ready || this.reconfigurePending || this.recording || session === undefined) {
        throw new ExpoCameraError('ERR_CAMERA_NOT_READY', 'The camera preview is unavailable.');
      }

      if (paused) {
        this.paused = true;
        try {
          await session.stop();
        } catch (error) {
          this.paused = false;
          throw new ExpoCameraError('ERR_CAMERA_SESSION', `The camera preview could not pause: ${String(error)}`);
        }
      } else {
        await session.start();
        this.paused = false;
      }
    });
    this.previewTransition = transition.catch((): void => {});
    await transition;
    return null;
  }

  private async releasePipeline(): Promise<void> {
    this.pipelineGeneration += 1;
    this.captureGeneration += 1;
    this.captureStarting = false;
    this.ready = false;
    if (this.displayChangeListener !== undefined) {
      try {
        display.off('change', this.displayChangeListener);
      } catch (_) {}
      this.displayChangeListener = undefined;
    }
    await this.previewTransition;

    if (this.pendingCapture !== undefined) {
      this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'Photo capture was interrupted.'));
    }

    if (this.session !== undefined) {
      this.setTorch(false);
      try {
        if (this.sessionErrorListener !== undefined) this.session.off('error', this.sessionErrorListener);
      } catch (_) {}

      try {
        await this.session.stop();
      } catch (_) {}
    }

    if (this.photoOutput !== undefined) {
      try {
        if (this.photoListener !== undefined) this.photoOutput.off('photoAvailable', this.photoListener);
      } catch (_) {}
    }

    await this.barcodeAnalyzer?.release();
    this.barcodeAnalyzer = undefined;
    if (this.previewOutput !== undefined) {
      try {
        await this.previewOutput.release();
      } catch (_) {}
    }
    if (this.photoOutput !== undefined) {
      try {
        await this.photoOutput.release();
      } catch (_) {}
    }
    if (this.videoOutput !== undefined) {
      try {
        await this.videoOutput.release();
      } catch (_) {}
    }

    if (this.input !== undefined) {
      try {
        await this.input.close();
      } catch (_) {}
    }
    if (this.session !== undefined) {
      try {
        await this.session.release();
      } catch (_) {}
    }

    if (this.recorder !== undefined) {
      try {
        this.recorder.off('stateChange');
      } catch (_) {}
      try {
        this.recorder.off('error');
      } catch (_) {}
      try {
        await this.recorder.release();
      } catch (_) {}
    }
    if (this.recordingFile !== undefined) {
      try {
        await fs.close(this.recordingFile.fd);
      } catch (_) {}
    }

    this.device = undefined;
    this.input = undefined;
    this.previewOutput = undefined;
    this.photoOutput = undefined;
    this.photoFormat = undefined;
    this.photoListener = undefined;
    this.videoOutput = undefined;
    this.session = undefined;
    this.sessionErrorListener = undefined;
    this.recorder = undefined;
    this.recordingFile = undefined;
    if (!this.recording) this.recordingPath = undefined;
  }

  private emit(eventName: string, payload: ESObject = {}): void {
    this.sendEvent(eventName, payload);
  }
}
@Builder
export function buildExpoCameraView(context: ExpoViewContentContext) {
  ExpoCameraSurface({
    contentContext: context,
    state: context.nativeView as ExpoCameraViewState,
  });
}

@Component
struct ExpoCameraSurface {
  @Require public contentContext!: ExpoViewContentContext;
  @Require public state!: ExpoCameraViewState;
  @State private flashVisible: boolean = false;
  private flashTimer?: number;

  aboutToAppear(): void {
    this.state.setFlash((): void => {
      this.flashVisible = true;
      if (this.flashTimer !== undefined) clearTimeout(this.flashTimer);
      this.flashTimer = setTimeout((): void => {
        this.flashVisible = false;
        this.flashTimer = undefined;
      }, 140);
    });
  }

  aboutToDisappear(): void {
    this.state.setFlash(undefined);
    if (this.flashTimer !== undefined) clearTimeout(this.flashTimer);
    this.flashTimer = undefined;
  }

  build(): void {
    Stack() {
      XComponent({ type: XComponentType.SURFACE, controller: this.state.controller })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .onLoad((): void => {
          this.state.attachSurface(this.state.controller.getXComponentSurfaceId());
        })
        .onDestroy((): void => {
          this.state.detachSurface();
        })

      if (this.flashVisible) {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.White)
          .hitTestBehavior(HitTestMode.None);
      }
    }
    .width('100%')
    .height('100%');
  }
}
