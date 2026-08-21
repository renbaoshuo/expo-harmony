import type { RNComponentContext } from '@rnoh/react-native-openharmony';
import { ExpoViewContentContext } from '@expo-harmony/expo-modules-core';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';
import { media } from '@kit.MediaKit';
import { sensor } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import { ExpoCameraError } from './ExpoCameraError';
import { decodeExifProperties, encodeExifMetadata, EXIF_KEYS } from './ExpoCameraExif';

interface CameraProps {
  facing?: string;
  flashMode?: string;
  selectedLens?: string;
  enableTorch?: boolean;
  pictureSize?: string;
  zoom?: number;
  mode?: string;
  barcodeScannerEnabled?: boolean;
  barcodeScannerSettings?: ESObject;
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

interface PictureOptions {
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

interface RecordingOptions {
  maxDuration?: number;
  maxFileSize?: number;
  mirror?: boolean;
  codec?: string;
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
  resolve?: (value: ESObject) => void;
  reject?: (error: ExpoCameraError) => void;
  timer?: number;
}

interface ReadyWaiter {
  resolve: () => void;
  reject: (error: ExpoCameraError) => void;
  timer: number;
}

type ControllableSession = camera.PhotoSession | camera.VideoSession;

const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const CAPTURE_TIMEOUT_MS: number = 15_000;
const GRAVITY_THRESHOLD: number = 9.80665 * 0.75;
let fileSequence: number = 0;

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

function choosePreviewProfile(profiles: camera.Profile[], output: camera.Profile): camera.Profile {
  if (profiles.length === 0) {
    throw new ExpoCameraError('ERR_CAMERA_UNSUPPORTED', 'The selected camera exposes no preview profiles.');
  }

  const ratio = aspectRatio(output);
  const matches = profiles.filter((profile: camera.Profile): boolean => {
    return Math.abs(aspectRatio(profile) - ratio) < 0.03 && profile.size.width <= 1920 && profile.size.height <= 1920;
  });
  const pool = matches.length === 0 ? profiles : matches;

  return pool.slice().sort((left: camera.Profile, right: camera.Profile): number => {
    const leftGap = Math.abs(aspectRatio(left) - ratio);
    const rightGap = Math.abs(aspectRatio(right) - ratio);
    if (Math.abs(leftGap - rightGap) > 0.001) return leftGap - rightGap;
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

function uniquePath(dir: string, prefix: string, extension: string, tag: number): string {
  fileSequence = (fileSequence + 1) % 1_000_000;

  return `${dir}/${prefix}-${Date.now()}-${tag}-${fileSequence}.${extension}`;
}

async function decodePixelMap(source: image.ImageSource, maxDownsampling?: number): Promise<image.PixelMap> {
  const max = Math.max(1, Math.floor(maxDownsampling ?? 1));
  let sample = 1;

  while (sample <= max) {
    try {
      return await source.createPixelMap({ sampleSize: sample });
    } catch (_) {
      sample *= 2;
    }
  }

  throw new ExpoCameraError('ERR_CAMERA_CAPTURE_PROCESSING', 'The captured photo could not be decoded.');
}

export class ExpoCameraViewState {
  readonly controller: XComponentController = new XComponentController();
  readonly instanceId: number;
  readonly tag: number;
  private readonly componentContext: RNComponentContext;
  private readonly manager: camera.CameraManager;
  private contentContext?: ExpoViewContentContext;
  private props: CameraProps = {};
  private surfaceId?: string;
  private device?: camera.CameraDevice;
  private input?: camera.CameraInput;
  private previewOutput?: camera.PreviewOutput;
  private photoOutput?: camera.PhotoOutput;
  private videoOutput?: camera.VideoOutput;
  private session?: ControllableSession;
  private photoProfile?: camera.Profile;
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
  private readonly readyWaiters: ReadyWaiter[] = [];
  private reconfigurePending: boolean = false;
  private reconfiguring: boolean = false;
  private ready: boolean = false;
  private paused: boolean = false;
  private backgrounded: boolean = false;
  private orientationListening: boolean = false;
  private orientation?: string;
  private destroyed: boolean = false;
  private recording: boolean = false;
  private recordingStarting: boolean = false;
  private finishing: boolean = false;
  private barcodeWarningShown: boolean = false;
  private shutterWarningShown: boolean = false;
  private flash?: () => void;

  private readonly onPhoto = (error: BusinessError, photo: camera.Photo): void => {
    if (error !== undefined && error !== null) {
      console.error(`Expo Camera photo capture failed: ${String(error)}`);
      this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_FAILED', 'Photo capture failed.'));
      return;
    }

    void this.consumePhoto(photo);
  };

  private readonly onSessionError = (error: BusinessError): void => {
    if (this.destroyed || this.finishing) return;

    console.error(`Expo Camera session failed: ${String(error)}`);
    this.ready = false;
    this.rejectReadyWaiters(new ExpoCameraError('ERR_CAMERA_SESSION', 'The camera session failed.'));
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
      this.scheduleReconfigure();
    } else if (info.status === camera.CameraStatus.CAMERA_STATUS_APPEAR && !this.ready) {
      this.scheduleReconfigure();
    }
  };

  private readonly onGravity = (value: sensor.GravityResponse): void => {
    if (!this.orientationListening) return;

    let orientation: string | undefined;
    if (Math.abs(value.x) > Math.abs(value.y) && Math.abs(value.x) >= GRAVITY_THRESHOLD) {
      orientation = value.x > 0 ? 'landscapeRight' : 'landscapeLeft';
    } else if (Math.abs(value.y) >= GRAVITY_THRESHOLD) {
      orientation = value.y > 0 ? 'portraitUpsideDown' : 'portrait';
    }

    if (orientation === undefined || orientation === this.orientation) return;

    this.orientation = orientation;
    this.emit('onResponsiveOrientationChanged', { orientation });
  };

  constructor(context: RNComponentContext, tag: number) {
    this.componentContext = context;
    this.instanceId = context.rnInstance.getId();
    this.tag = tag;
    this.manager = camera.getCameraManager(context.uiAbilityContext);
    this.manager.on('cameraStatus', this.onCameraStatus);
  }

  setContentContext(context: ExpoViewContentContext): void {
    this.contentContext = context;
  }

  setFlash(handler?: () => void): void {
    this.flash = handler;
  }

  attachSurface(surfaceId: string): void {
    if (this.destroyed || surfaceId.length === 0) return;
    this.surfaceId = surfaceId;
    this.scheduleReconfigure();
  }

  detachSurface(): void {
    this.surfaceId = undefined;
    this.ready = false;
    this.setTorch(false);

    if (this.recording) {
      void this.finishRecording(true);
    } else {
      this.scheduleReconfigure();
    }
  }

  updateProps(value: Record<string, ESObject>): void {
    const prev = this.props;
    this.props = value as CameraProps;
    this.updateOrientationListener();

    if (this.props.barcodeScannerEnabled === true && !this.barcodeWarningShown) {
      console.warn('Live CameraView barcode scanning requires HarmonyOS API 26; the current API 24 target ignores barcodeScannerSettings.');
      this.barcodeWarningShown = true;
    } else if (this.props.barcodeScannerEnabled !== true) {
      this.barcodeWarningShown = false;
    }

    const reload =
      prev.facing !== this.props.facing ||
      prev.selectedLens !== this.props.selectedLens ||
      prev.pictureSize !== this.props.pictureSize ||
      prev.ratio !== this.props.ratio ||
      prev.mode !== this.props.mode ||
      prev.active !== this.props.active;

    if (reload) {
      if (this.recording) {
        void this.finishRecording(true);
      } else {
        this.scheduleReconfigure();
      }
      return;
    }

    this.applyControls();
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (this.destroyed) throw new ExpoCameraError('ERR_CAMERA_VIEW_DESTROYED', 'The camera view has been destroyed.');

    if (method === 'takePicture') return await this.takePicture((args[0] ?? {}) as PictureOptions);
    if (method === 'getAvailablePictureSizes') return this.getAvailablePictureSizes();
    if (method === 'getAvailableLenses') return this.getAvailableLenses();
    if (method === 'record') return await this.startRecording((args[0] ?? {}) as RecordingOptions);
    if (method === 'toggleRecording') return await this.toggleRecording();
    if (method === 'stopRecording') return await this.stopRecording();
    if (method === 'resumePreview') return await this.resumePreview();
    if (method === 'pausePreview') return await this.pausePreview();
    if (method === 'launchModernScanner') {
      throw new ExpoCameraError('ERR_CAMERA_SCANNER_UNAVAILABLE', 'The modern barcode scanner is not available on HarmonyOS.');
    }

    throw new ExpoCameraError('ERR_CAMERA_UNKNOWN_METHOD', `Unknown camera view method '${method}'.`);
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.ready = false;
    this.setTorch(false);
    this.stopOrientationListener();
    this.rejectReadyWaiters(new ExpoCameraError('ERR_CAMERA_VIEW_DESTROYED', 'The camera view has been destroyed.'));
    this.rejectCapture(new ExpoCameraError('ERR_CAMERA_VIEW_DESTROYED', 'The camera view was unmounted during capture.'));

    try {
      this.manager.off('cameraStatus', this.onCameraStatus);
    } catch (_) {}

    if (this.recording) {
      void this.finishRecording(true);
    } else {
      this.reconfigurePending = true;
      if (!this.reconfiguring) void this.runReconfigureLoop();
    }
  }

  onBackground(): void {
    if (this.destroyed || this.backgrounded) return;

    this.backgrounded = true;
    this.ready = false;
    this.setTorch(false);

    if (this.recording) {
      void this.finishRecording(true);
    } else {
      this.scheduleReconfigure();
    }
  }

  onForeground(): void {
    if (this.destroyed || !this.backgrounded) return;

    this.backgrounded = false;
    this.scheduleReconfigure();
  }

  private scheduleReconfigure(): void {
    if (this.destroyed) return;

    this.reconfigurePending = true;
    if (!this.reconfiguring && this.pendingCapture === undefined) void this.runReconfigureLoop();
  }

  private async runReconfigureLoop(): Promise<void> {
    this.reconfiguring = true;

    while (this.reconfigurePending && !this.recording && this.pendingCapture === undefined) {
      this.reconfigurePending = false;

      try {
        await this.releasePipeline();
        if (!this.destroyed && !this.backgrounded && this.surfaceId !== undefined && this.props.active !== false) {
          await this.initializePreview();
        }
      } catch (error) {
        console.error(`Expo Camera preview could not start: ${String(error)}`);

        this.ready = false;
        this.rejectReadyWaiters(new ExpoCameraError('ERR_CAMERA_NOT_READY', 'Camera preview could not start.'));
        this.emit('onMountError', { message: 'Camera preview could not start.' });
      }
    }

    this.reconfiguring = false;
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

    return cameras.find((device: camera.CameraDevice): boolean => device.cameraPosition === position) ?? cameras[0];
  }

  private async initializePreview(): Promise<void> {
    const surface = this.surfaceId;
    if (surface === undefined || this.destroyed || this.backgrounded || this.props.active === false) return;

    const device = this.selectedDevice();
    const videoMode = this.props.mode === 'video';
    const mode = videoMode ? camera.SceneMode.NORMAL_VIDEO : camera.SceneMode.NORMAL_PHOTO;
    const capability = this.manager.getSupportedOutputCapability(device, mode);
    let photo: camera.Profile | undefined;
    let output: camera.Profile;

    if (videoMode) {
      output = chooseVideoProfile(capability.videoProfiles, this.props.videoQuality);
    } else {
      const photos = capability.photoProfiles.filter((profile: camera.Profile): boolean => {
        return profile.format === camera.CameraFormat.CAMERA_FORMAT_JPEG;
      });
      photo = choosePhotoProfile(photos.length === 0 ? capability.photoProfiles : photos, this.props.pictureSize, this.props.ratio);
      output = photo;
    }

    const preview = choosePreviewProfile(capability.previewProfiles, output);

    const input = this.manager.createCameraInput(device);

    await input.open();

    const previewOut = this.manager.createPreviewOutput(preview, surface);
    const photoOut = photo === undefined ? undefined : this.manager.createPhotoOutput(photo);
    photoOut?.on('photoAvailable', this.onPhoto);
    const session: ControllableSession = videoMode
      ? this.manager.createSession<camera.VideoSession>(camera.SceneMode.NORMAL_VIDEO)
      : this.manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
    session.beginConfig();
    session.addInput(input);
    session.addOutput(previewOut);
    if (photoOut !== undefined) session.addOutput(photoOut);
    await session.commitConfig();
    session.on('error', this.onSessionError);

    this.device = device;
    this.input = input;
    this.previewOutput = previewOut;
    this.photoOutput = photoOut;
    this.photoProfile = photo;
    this.session = session;

    this.applyControls();
    await session.start();

    this.paused = false;
    this.ready = true;
    this.resolveReadyWaiters();
    this.emit('onAvailableLensesChanged', { lenses: this.getAvailableLenses() });
    this.emit('onCameraReady');
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
        session.setZoomRatio(Math.max(range[0], Math.min(max, zoom * max)));
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
    const enabled = this.props.responsiveOrientationWhenOrientationLocked === true;
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
  }

  private awaitReady(): Promise<void> {
    if (this.ready && !this.reconfiguring && !this.reconfigurePending) return Promise.resolve();
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
    if (this.props.mode === 'video') throw new ExpoCameraError('ERR_CAMERA_WRONG_MODE', 'Cannot take a picture while the camera is in video mode.');
    if (this.recording) throw new ExpoCameraError('ERR_CAMERA_CAPTURE_DURING_RECORDING', 'Cannot take a picture while recording.');
    if (this.paused) throw new ExpoCameraError('ERR_CAMERA_PREVIEW_PAUSED', 'Cannot take a picture while preview is paused.');
    if (this.pendingCapture !== undefined) throw new ExpoCameraError('ERR_CAMERA_CAPTURE_IN_PROGRESS', 'A photo capture is already in progress.');

    if (options.shutterSound === false && !this.shutterWarningShown) {
      console.warn('Disabling the system camera shutter sound is not supported by HarmonyOS CameraKit.');
      this.shutterWarningShown = true;
    }

    await this.awaitReady();

    const output = this.photoOutput;
    if (output === undefined) throw new ExpoCameraError('ERR_CAMERA_NOT_READY', 'Photo output is not ready.');

    if (this.props.flashMode === 'screen' && this.props.facing === 'front') {
      this.flash?.();
      await wait(120);
    } else if (this.props.animateShutter !== false) {
      this.flash?.();
    }

    const setting: camera.PhotoCaptureSetting = {
      quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
    };
    const mirror = this.props.facing === 'front' && (options.mirror === true || this.props.mirror === true);
    let softwareMirror = mirror;

    try {
      if (mirror && output.isMirrorSupported()) {
        setting.mirror = true;
        softwareMirror = false;
      }
    } catch (_) {}

    if (options.fastMode === true) {
      this.setPendingCapture({ options, softwareMirror });

      try {
        await output.capture(setting);
      } catch (error) {
        console.error(`Expo Camera photo capture failed: ${String(error)}`);

        this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_FAILED', 'Photo capture failed.'));

        throw new ExpoCameraError('ERR_CAMERA_CAPTURE_FAILED', 'Photo capture failed.');
      }

      return null;
    }

    return await new Promise<ESObject>((resolve: (value: ESObject) => void, reject: (error: ExpoCameraError) => void): void => {
      this.setPendingCapture({ options, softwareMirror, resolve, reject });

      output.capture(setting).catch((error: Object): void => {
        console.error(`Expo Camera photo capture failed: ${String(error)}`);
        this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_FAILED', 'Photo capture failed.'));
      });
    });
  }

  private setPendingCapture(pending: PendingCapture): void {
    pending.timer = setTimeout((): void => {
      if (this.pendingCapture !== pending) return;

      this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_TIMEOUT', 'The camera did not deliver a captured photo in time.'));
    }, CAPTURE_TIMEOUT_MS);

    this.pendingCapture = pending;
  }

  private async consumePhoto(photo: camera.Photo): Promise<void> {
    const pending = this.pendingCapture;
    if (pending === undefined) {
      await photo.release();
      return;
    }

    try {
      const jpeg = await photo.main.getComponent(image.ComponentType.JPEG);
      const result = await this.processPhoto(jpeg.byteBuffer, pending);

      if (this.pendingCapture !== pending) return;

      if (pending.options.fastMode === true) {
        this.emit('onPictureSaved', { id: pending.options.id ?? 0, data: result });
      } else {
        pending.resolve?.(result);
      }
    } catch (error) {
      console.error(`Expo Camera photo processing failed: ${String(error)}`);

      if (pending.options.fastMode === true) {
        console.error('Expo Camera could not deliver the fast-mode photo result.');
      } else {
        pending.reject?.(new ExpoCameraError('ERR_CAMERA_CAPTURE_PROCESSING', 'The captured photo could not be saved.'));
      }
    } finally {
      if (pending.timer !== undefined) clearTimeout(pending.timer);
      if (this.pendingCapture === pending) this.pendingCapture = undefined;

      try {
        await photo.release();
      } catch (_) {}

      if (this.reconfigurePending && !this.reconfiguring) void this.runReconfigureLoop();
    }
  }

  private async processPhoto(jpeg: ArrayBuffer, pending: PendingCapture): Promise<PictureResult> {
    const options = pending.options;
    const source = image.createImageSource(jpeg);
    let pixel: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;

    try {
      const info = await source.getImageInfo();
      let properties: Record<image.PropertyKey, string | null> | undefined;

      try {
        const keys = options.exif === true ? EXIF_KEYS : [image.PropertyKey.ORIENTATION];
        properties = await source.getImageProperties(keys);
      } catch (_) {}

      const orientation = orientationCode(properties?.[image.PropertyKey.ORIENTATION]);
      const skip = options.skipProcessing === true;
      const format = !skip && options.imageType === 'png' ? 'png' : 'jpg';
      let buffer = jpeg;
      let width = info.size.width;
      let height = info.size.height;

      if (!skip) {
        pixel = await decodePixelMap(source, options.maxDownsampling);
        await transformPixelMap(pixel, orientation, pending.softwareMirror);

        const transformed = await pixel.getImageInfo();
        width = transformed.size.width;
        height = transformed.size.height;

        packer = image.createImagePacker();
        buffer = await packer.packToData(pixel, {
          format: format === 'png' ? 'image/png' : 'image/jpeg',
          quality: Math.round(clamp(options.quality ?? 1, 0, 1) * 100),
          bufferSize: Math.max(25 * 1024 * 1024, jpeg.byteLength * 2),
          needsPackProperties: options.exif === true,
        });
      }

      const dir = `${this.componentContext.uiAbilityContext.cacheDir}/expo-camera`;
      await ensureDirectory(dir);
      const path = uniquePath(dir, 'photo', format, this.tag);

      await writeBuffer(path, buffer);

      if (!skip && options.exif === true && properties !== undefined) {
        const records = properties;
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
        } catch (_) {
        } finally {
          try {
            await output.release();
          } catch (_) {}
        }
      }

      const result = new PictureResult(`file://${path}`, width, height, format);
      if (options.base64 === true) {
        result.base64 = await new util.Base64Helper().encodeToString(new Uint8Array(buffer));
      }

      if (options.exif === true) {
        const exif = decodeExifProperties(properties ?? ({} as Record<image.PropertyKey, string | null>));
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

      return result;
    } finally {
      if (packer !== undefined) {
        try {
          await packer.release();
        } catch (_) {}
      }
      if (pixel !== undefined) {
        try {
          await pixel.release();
        } catch (_) {}
      }

      try {
        await source.release();
      } catch (_) {}
    }
  }

  private rejectCapture(error: ExpoCameraError): void {
    const pending = this.pendingCapture;
    this.pendingCapture = undefined;

    if (pending?.timer !== undefined) clearTimeout(pending.timer);

    pending?.reject?.(error);
    if (pending?.options.fastMode === true) console.error(`Expo Camera fast-mode capture failed: ${error.message}`);
    if (this.reconfigurePending && !this.reconfiguring) void this.runReconfigureLoop();
  }

  private getAvailablePictureSizes(): string[] {
    const device = this.device ?? this.selectedDevice();
    const capability = this.manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);

    return capability.photoProfiles
      .filter((profile: camera.Profile): boolean => profile.format === camera.CameraFormat.CAMERA_FORMAT_JPEG)
      .slice()
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
    try {
      if (this.props.mode !== 'video') throw new ExpoCameraError('ERR_CAMERA_WRONG_MODE', 'Cannot record while the camera is in picture mode.');
      if (this.surfaceId === undefined) throw new ExpoCameraError('ERR_CAMERA_NOT_READY', 'The camera preview surface is unavailable.');
      if (this.props.mute !== true) {
        const token = this.componentContext.uiAbilityContext.applicationInfo.accessTokenId;
        const granted =
          abilityAccessCtrl.createAtManager().checkAccessTokenSync(token, MICROPHONE_PERMISSION) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
        if (!granted) {
          throw new ExpoCameraError('ERR_CAMERA_MICROPHONE_PERMISSION', 'Microphone permission is required to record video with audio.');
        }
      }

      await this.awaitReady();

      const result: Promise<ESObject> = new Promise<ESObject>(
        (resolve: (value: ESObject) => void, reject: (error: ExpoCameraError) => void): void => {
          this.resolveRecording = resolve;
          this.rejectRecording = reject;
        },
      );

      this.recording = true;
      try {
        await this.releasePipeline();
        await this.initializeVideoRecording(options);
      } catch (error) {
        const detail = String(error).replace(/^(?:Error:\s*)+/, '');
        const reject = this.rejectRecording;

        this.resolveRecording = undefined;
        this.rejectRecording = undefined;
        this.recording = false;
        await this.releasePipeline();
        this.scheduleReconfigure();

        console.error(`Expo Camera recording could not start: ${detail}`);
        reject?.(new ExpoCameraError('ERR_CAMERA_RECORDING_START', 'Video recording could not start.'));
      }

      return await result;
    } finally {
      this.recordingStarting = false;
    }
  }

  private async initializeVideoRecording(options: RecordingOptions): Promise<void> {
    const surface = this.surfaceId;
    if (surface === undefined) throw new ExpoCameraError('ERR_CAMERA_NOT_READY', 'The camera preview surface is unavailable.');

    const device = this.selectedDevice();
    const capability = this.manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_VIDEO);

    const video = chooseVideoProfile(capability.videoProfiles, this.props.videoQuality);
    const preview = choosePreviewProfile(capability.previewProfiles, video);

    const dir = `${this.componentContext.uiAbilityContext.cacheDir}/expo-camera`;
    await ensureDirectory(dir);
    const path = uniquePath(dir, 'video', 'mp4', this.tag);
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);

    this.recordingFile = file;
    this.recordingPath = path;

    const recorder = await media.createAVRecorder();
    this.recorder = recorder;

    const encoders = await recorder.getAvailableEncoder();
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
    const inputSurface = await recorder.getInputSurface();
    const input = this.manager.createCameraInput(device);
    await input.open();

    const previewOut = this.manager.createPreviewOutput(preview, surface);
    const videoOut = this.manager.createVideoOutput(video, inputSurface);
    const session = this.manager.createSession<camera.VideoSession>(camera.SceneMode.NORMAL_VIDEO);
    session.beginConfig();
    session.addInput(input);
    session.addOutput(previewOut);
    session.addOutput(videoOut);
    await session.commitConfig();
    session.on('error', this.onSessionError);

    this.device = device;
    this.input = input;
    this.previewOutput = previewOut;
    this.videoOutput = videoOut;
    this.session = session;

    this.applyControls();
    this.applyVideoStabilization(session);

    const mirror = this.props.facing === 'front' && (options.mirror === true || this.props.mirror === true);
    try {
      if (videoOut.isMirrorSupported()) {
        videoOut.enableMirror(mirror);
      } else if (mirror) {
        console.warn('Mirror recording is not supported by the selected HarmonyOS camera.');
      }
    } catch (error) {
      console.warn(`Expo Camera could not configure mirror recording: ${String(error)}`);
    }
    try {
      await recorder.updateRotation(videoOut.getVideoRotation());
    } catch (error) {
      console.warn(`Expo Camera could not configure video rotation: ${String(error)}`);
    }

    recorder.on('stateChange', (state: media.AVRecorderState, _: media.StateChangeReason): void => {
      if (state === 'stopped' && this.recording && !this.finishing) void this.finishRecording(false);
    });
    recorder.on('error', (error: BusinessError): void => {
      if (this.recording && !this.finishing) {
        console.error(`Expo Camera video recorder failed: ${String(error)}`);
        void this.failRecording(new ExpoCameraError('ERR_CAMERA_RECORDING', 'Video recording failed.'));
      }
    });

    await session.start();
    await videoOut.start();
    await recorder.start();

    this.ready = true;
    this.paused = false;
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
            if (stat.size >= limit) void this.finishRecording(true);
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
    const recorder = this.recorder;
    if (!this.recording || recorder === undefined) return null;

    if (recorder.state === 'started') {
      await recorder.pause();
      this.pauseDurationTimer();
    } else if (recorder.state === 'paused') {
      await recorder.resume();
      this.resumeDurationTimer();
    }

    return null;
  }

  private async stopRecording(): Promise<ESObject> {
    if (this.recording) await this.finishRecording(true);
    return null;
  }

  private async finishRecording(stopRecorder: boolean): Promise<void> {
    if (!this.recording || this.finishing) return;

    this.finishing = true;
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

      await this.releasePipeline();
      this.recording = false;
      this.finishing = false;

      if (path === undefined) throw new ExpoCameraError('ERR_CAMERA_RECORDING_FILE', 'The video recorder did not create an output file.');

      const resolve = this.resolveRecording;
      this.resolveRecording = undefined;
      this.rejectRecording = undefined;
      resolve?.(new VideoResult(`file://${path}`));

      if (!this.destroyed) this.scheduleReconfigure();
    } catch (error) {
      console.error(`Expo Camera recording could not stop: ${String(error)}`);

      this.finishing = false;
      await this.failRecording(new ExpoCameraError('ERR_CAMERA_RECORDING_STOP', 'Video recording could not stop cleanly.'));
    }
  }

  private async failRecording(error: ExpoCameraError): Promise<void> {
    this.clearRecordingLimits();
    const reject = this.rejectRecording;

    this.resolveRecording = undefined;
    this.rejectRecording = undefined;
    this.recording = false;
    this.finishing = false;

    await this.releasePipeline();

    reject?.(error);
    if (!this.destroyed) this.scheduleReconfigure();
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
    if (this.recording) throw new ExpoCameraError('ERR_CAMERA_PREVIEW_DURING_RECORDING', 'Cannot pause preview while recording.');

    await this.awaitReady();

    if (!this.paused && this.session !== undefined) {
      await this.session.stop();
      this.paused = true;
    }

    return null;
  }

  private async resumePreview(): Promise<ESObject> {
    if (this.recording) return null;

    if (this.paused && this.session !== undefined) {
      await this.session.start();
      this.paused = false;
      this.ready = true;
    } else if (!this.ready) {
      this.scheduleReconfigure();
      await this.awaitReady();
    }

    return null;
  }

  private async releasePipeline(): Promise<void> {
    this.ready = false;
    this.paused = false;

    if (this.pendingCapture !== undefined) {
      this.rejectCapture(new ExpoCameraError('ERR_CAMERA_CAPTURE_INTERRUPTED', 'Photo capture was interrupted.'));
    }

    if (this.session !== undefined) {
      try {
        this.session.off('error', this.onSessionError);
      } catch (_) {}

      try {
        await this.session.stop();
      } catch (_) {}
    }

    if (this.photoOutput !== undefined) {
      try {
        this.photoOutput.off('photoAvailable', this.onPhoto);
      } catch (_) {}
    }

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
        this.recorder.off('error');
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
    this.videoOutput = undefined;
    this.session = undefined;
    this.photoProfile = undefined;
    this.recorder = undefined;
    this.recordingFile = undefined;
    if (!this.recording) this.recordingPath = undefined;
  }

  private emit(eventName: string, payload: ESObject = {}): void {
    this.contentContext?.emit(eventName, payload);
  }
}

export class ExpoCameraViewRegistry {
  private static readonly states: Map<string, ExpoCameraViewState> = new Map();

  private static key(id: number, tag: number): string {
    return `${id}:${tag}`;
  }

  static add(state: ExpoCameraViewState): void {
    ExpoCameraViewRegistry.states.set(ExpoCameraViewRegistry.key(state.instanceId, state.tag), state);
  }

  static require(id: number, tag: number): ExpoCameraViewState {
    const state = ExpoCameraViewRegistry.states.get(ExpoCameraViewRegistry.key(id, tag));
    if (state === undefined) throw new ExpoCameraError('ERR_CAMERA_VIEW_NOT_FOUND', `Camera view ${tag} is not mounted.`);
    return state;
  }

  static remove(id: number, tag: number): void {
    const key = ExpoCameraViewRegistry.key(id, tag);
    ExpoCameraViewRegistry.states.get(key)?.destroy();
    ExpoCameraViewRegistry.states.delete(key);
  }

  static destroyInstance(id: number): void {
    Array.from(ExpoCameraViewRegistry.states.entries()).forEach((item: [string, ExpoCameraViewState]): void => {
      if (item[1].instanceId !== id) return;

      item[1].destroy();
      ExpoCameraViewRegistry.states.delete(item[0]);
    });
  }

  static onBackground(id: number): void {
    ExpoCameraViewRegistry.states.forEach((state: ExpoCameraViewState): void => {
      if (state.instanceId === id) state.onBackground();
    });
  }

  static onForeground(id: number): void {
    ExpoCameraViewRegistry.states.forEach((state: ExpoCameraViewState): void => {
      if (state.instanceId === id) state.onForeground();
    });
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
    this.state.setContentContext(this.contentContext);
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
