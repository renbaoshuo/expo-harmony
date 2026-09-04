import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoValueType,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { abilityAccessCtrl, Permissions, wantAgent, WantAgent } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { audio } from '@kit.AudioKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { notificationManager } from '@kit.NotificationKit';
import deviceInfo from '@ohos.deviceInfo';
import fs from '@ohos.file.fs';
import {
  effectivePlaying,
  isDataAudioUri,
  isPackagedAudioUri,
  isRemoteAudioUri,
  isSupportedRecordingExtension,
  nextPlaylistIndex,
  packagedAudioResourceName,
  previousPlaylistIndex,
  seekTargetMilliseconds,
} from './ExpoAudioSemantics';

const MODULE_NAME: string = 'ExpoAudio';
const PLAYER_CLASS_NAME: string = 'AudioPlayer';
const RECORDER_CLASS_NAME: string = 'AudioRecorder';
const PLAYLIST_CLASS_NAME: string = 'AudioPlaylist';
const PLAYBACK_STATUS_EVENT: string = 'playbackStatusUpdate';
const RECORDING_STATUS_EVENT: string = 'recordingStatusUpdate';
const PLAYLIST_STATUS_EVENT: string = 'playlistStatusUpdate';
const TRACK_CHANGED_EVENT: string = 'trackChanged';
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const BACKGROUND_PLAYBACK_MODE: string = 'audioPlayback';
const BACKGROUND_RECORDING_MODE: string = 'audioRecording';
const MIN_UPDATE_INTERVAL_MS: number = 16;
const MIN_PLAYBACK_RATE: number = 0.1;
const MAX_PLAYBACK_RATE: number = 2.0;
const MAX_TIMER_DELAY_MS: number = 2_147_483_647;
const SEEK_STEP_MS: number = 10_000;
const METERING_INTERVAL_MS: number = 100;
const SILENCE_LEVEL_DB: number = -160;
const PCM_16_BIT_MAX_AMPLITUDE: number = 32_767;
const INPUT_SELECTION_API: number = 21;
const AUDIO_SESSION_TAG: string = 'ExpoAudio';
const DATA_URI_PREFIX: string = 'data:';
const DATA_URI_BASE64_MARKER: string = ';base64';
const FILE_URI_PREFIX: string = 'file://';
const DUCKING_VOLUME: number = 0.5;
const SOURCE_INITIALIZATION_TIMEOUT_MS: number = 15_000;
const FILE_CLOSE_ATTEMPTS: number = 3;
const MAX_DATA_URI_PAYLOAD_BYTES: number = 32 * 1024 * 1024;
let sequence: number = 0;

type PlaylistLoopMode = 'none' | 'single' | 'all';
type InterruptionMode = 'mixWithOthers' | 'doNotMix' | 'duckOthers';

interface AudioSource {
  uri?: string;
  headers?: Record<string, string>;
  name?: string;
}

interface AudioModeInput {
  shouldPlayInBackground?: boolean;
  shouldRouteThroughEarpiece?: boolean;
  interruptionMode?: string;
  allowsBackgroundRecording?: boolean;
}

interface RecordingOptionsInput {
  extension?: string;
  sampleRate?: number;
  numberOfChannels?: number;
  bitRate?: number;
  isMeteringEnabled?: boolean;
  mimeType?: string;
  bitsPerSecond?: number;
}

interface RecordingStartOptions {
  atTime?: number;
  forDuration?: number;
}

interface AudioMetadataInput {
  title?: string;
  artist?: string;
  albumTitle?: string;
  artworkUrl?: string;
}

class SourceFile {
  readonly path: string;
  readonly file: fs.File;
  readonly offset: number;
  readonly length: number;
  readonly temporary: boolean;
  private closed: boolean = false;

  constructor(path: string, file: fs.File, offset: number, length: number, temporary: boolean) {
    this.path = path;
    this.file = file;
    this.offset = offset;
    this.length = length;
    this.temporary = temporary;
  }

  close(): boolean {
    if (this.closed) return true;

    for (let attempt = 0; attempt < FILE_CLOSE_ATTEMPTS; attempt += 1) {
      try {
        fs.closeSync(this.file.fd);
        this.closed = true;

        if (this.temporary) deleteFile(this.path);

        return true;
      } catch (_) {}
    }

    return false;
  }
}

class PreparedPlayer {
  readonly player: media.AVPlayer;
  readonly file?: SourceFile;

  constructor(player: media.AVPlayer, file?: SourceFile) {
    this.player = player;
    this.file = file;
  }
}

class PreloadEntry {
  readonly source: AudioSource;
  readonly preferredBufferDuration: number;
  readonly prepared: Promise<PreparedPlayer>;

  constructor(source: AudioSource, preferredBufferDuration: number, prepared: Promise<PreparedPlayer>) {
    this.source = source;
    this.preferredBufferDuration = preferredBufferDuration;
    this.prepared = prepared;
  }
}

interface LockScreenOptionsInput {
  showSeekForward?: boolean;
  showSeekBackward?: boolean;
}

class ExpoAudioError extends ExpoModuleError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoAudioError';
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

class AudioSourceInfoRecord {
  uri?: string;
  name?: string;

  constructor(source: AudioSource) {
    this.uri = source.uri;
    this.name = source.name;
  }
}

class AudioStatusRecord {
  id: string;
  currentTime: number;
  playbackState: string;
  timeControlStatus: string;
  reasonForWaitingToPlay: string | null;
  mute: boolean;
  duration: number;
  playing: boolean;
  loop: boolean;
  didJustFinish: boolean;
  isBuffering: boolean;
  isLoaded: boolean;
  playbackRate: number;
  shouldCorrectPitch: boolean;

  constructor(controller: PlaybackController, didJustFinish: boolean) {
    this.id = controller.id;
    this.currentTime = controller.currentTimeSeconds;
    this.playbackState = controller.playbackState;
    this.timeControlStatus = controller.playing ? 'playing' : 'paused';
    this.reasonForWaitingToPlay = null;
    this.mute = controller.muted;
    this.duration = controller.durationSeconds;
    this.playing = controller.playing;
    this.loop = controller.looping;
    this.didJustFinish = didJustFinish;
    this.isBuffering = controller.buffering;
    this.isLoaded = controller.loaded;
    this.playbackRate = controller.playbackRate;
    this.shouldCorrectPitch = controller.correctsPitch;
  }
}

class PlaylistStatusRecord {
  id: string;
  currentIndex: number;
  trackCount: number;
  currentTime: number;
  duration: number;
  playing: boolean;
  isBuffering: boolean;
  isLoaded: boolean;
  playbackRate: number;
  muted: boolean;
  volume: number;
  loop: PlaylistLoopMode;
  didJustFinish: boolean;

  constructor(controller: PlaylistController, didJustFinish: boolean) {
    this.id = controller.id;
    this.currentIndex = controller.currentIndex;
    this.trackCount = controller.trackCount;
    this.currentTime = controller.currentTimeSeconds;
    this.duration = controller.durationSeconds;
    this.playing = controller.playing;
    this.isBuffering = controller.buffering;
    this.isLoaded = controller.loaded;
    this.playbackRate = controller.playbackRate;
    this.muted = controller.muted;
    this.volume = controller.volume;
    this.loop = controller.loopMode;
    this.didJustFinish = didJustFinish;
  }
}

class RecorderStateRecord {
  canRecord: boolean;
  isRecording: boolean;
  durationMillis: number;
  mediaServicesDidReset: boolean = false;
  metering?: number;
  url: string | null;

  constructor(controller: AudioRecorderController) {
    this.canRecord = controller.prepared;
    this.isRecording = controller.recording;
    this.durationMillis = controller.durationMillis;
    this.url = controller.uri;
    if (controller.recording && controller.metering !== undefined) this.metering = controller.metering;
  }
}

class RecordingStatusRecord {
  id: string;
  isFinished: boolean;
  hasError: boolean;
  error: string | null;
  url: string | null;

  constructor(id: string, error: string | null, url: string | null, isFinished: boolean = true) {
    this.id = id;
    this.isFinished = isFinished;
    this.hasError = error !== null;
    this.error = error;
    this.url = url;
  }
}

class RecordingInputRecord {
  name: string;
  type: string;
  uid: string;

  constructor(device: audio.AudioDeviceDescriptor) {
    this.name = device.name.length > 0 ? device.name : audioDeviceTypeName(device.deviceType);
    this.type = audioDeviceTypeName(device.deviceType);
    this.uid = String(device.id);
  }
}

class TrackChangedRecord {
  previousIndex: number;
  currentIndex: number;

  constructor(previousIndex: number, currentIndex: number) {
    this.previousIndex = previousIndex;
    this.currentIndex = currentIndex;
  }
}

abstract class OperationQueue {
  private tail: Promise<void> = Promise.resolve();

  async waitForIdle(): Promise<void> {
    await this.tail.catch((): void => {});
  }

  protected enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.tail.catch((): void => {}).then(operation);
    this.tail = next.catch((): void => {});

    return next;
  }

  protected schedule(label: string, operation: () => Promise<void>): void {
    this.enqueue(operation).catch((error: Object): void => this.onScheduledError(label, error));
  }

  protected abstract onScheduledError(label: string, error: Object): void;
}

interface AudioObjectEventSink {
  emit(eventName: string, payload: ESObject): void;
}

interface PlaybackDelegate {
  readonly context: ExpoModuleContext;
  readonly cacheDir: string;
  takePreloaded(source: AudioSource): Promise<PreparedPlayer | undefined>;
  beforePlay(): Promise<boolean>;
  playbackUsage(): audio.StreamUsage;
  playbackStateChanged(controller: PlaybackController): void;
  lockScreenStateChanged(controller: AudioPlayerController): void;
  setLockScreenPlayer(controller: AudioPlayerController, active: boolean, metadata?: AudioMetadataInput, options?: LockScreenOptionsInput): void;
}

function finiteNumber(value: ESObject, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function bounded(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

function positiveDelayMilliseconds(seconds: number): number {
  if (!Number.isFinite(seconds) || seconds <= 0) return 0;
  return Math.min(MAX_TIMER_DELAY_MS, Math.round(seconds * 1000));
}

function cleanError(cause: Object): string {
  try {
    if (cause !== null && typeof cause === 'object') {
      const error = cause as BusinessError;
      if (typeof error.message === 'string' && error.message.length > 0) return error.message;
    }

    return String(cause).replace(/^(?:Error:\s*)+/, '');
  } catch (_) {
    return 'The HarmonyOS media operation failed.';
  }
}

function readSource(value: ESObject): AudioSource | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return { uri: value };
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'An audio source must be null, a URI string, or an object.');
  }

  const input = value as Record<string, ESObject>;
  const source: AudioSource = {};

  if (typeof input.uri === 'string') source.uri = input.uri;
  if (typeof input.name === 'string') source.name = input.name;
  if (input.headers !== null && typeof input.headers === 'object' && !Array.isArray(input.headers)) {
    const headers: Record<string, string> = {};
    const values = input.headers as Record<string, ESObject>;

    Object.keys(values).forEach((name: string): void => {
      if (typeof values[name] === 'string') headers[name] = values[name] as string;
    });

    if (Object.keys(headers).length > 0) source.headers = headers;
  }

  return source;
}

function readSources(value: ESObject): AudioSource[] {
  if (!Array.isArray(value)) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'An audio playlist requires an array of sources.');
  }

  const sources: AudioSource[] = [];
  (value as ESObject[]).forEach((entry: ESObject): void => {
    const source = readSource(entry);
    if (source !== null && source.uri !== undefined && source.uri.length > 0) sources.push(source);
  });

  return sources;
}

function sourceKey(source: AudioSource | null): string | null {
  const uri = source?.uri;
  return uri !== undefined && uri.length > 0 ? uri : null;
}

function hasHeaders(source: AudioSource): boolean {
  return source.headers !== undefined && Object.keys(source.headers).length > 0;
}

function uptimeMilliseconds(): number {
  return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
}

function dataUriExtension(metadata: string): string {
  const mime = metadata.slice(DATA_URI_PREFIX.length).split(';')[0].toLowerCase();

  if (mime === 'audio/mpeg') return '.mp3';
  if (mime === 'audio/mp4' || mime === 'audio/x-m4a') return '.m4a';
  if (mime === 'audio/aac') return '.aac';
  if (mime === 'audio/ogg') return '.ogg';
  if (mime === 'audio/wav' || mime === 'audio/x-wav') return '.wav';
  if (mime === 'audio/flac') return '.flac';

  return '.audio';
}

function deleteFile(path?: string): void {
  if (path === undefined) return;

  try {
    fs.unlinkSync(path);
  } catch (_) {}
}

function closeSourceFile(file?: SourceFile): void {
  if (file === undefined || file.close()) return;

  console.error(`Expo Audio could not close the local source '${file.path}'.`);
}

function localFilePath(uri: string): string | undefined {
  if (uri.startsWith('/')) return uri;
  if (!uri.toLowerCase().startsWith(FILE_URI_PREFIX)) return undefined;

  const match = /^file:\/\/([^/?#]*)(\/[^?#]*)?(\?[^#]*)?(#.*)?$/i.exec(uri);
  if (match === null || match[2] === undefined || match[2].length === 0) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'The local audio URI must contain a path.');
  }
  if (match[3] !== undefined || match[4] !== undefined) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'The local audio URI must not contain a query or fragment.');
  }

  const authority = match[1];
  let path: string;
  try {
    path = decodeURIComponent(match[2]);
  } catch (_) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'The local audio URI contains invalid URL escaping.');
  }

  if (path.includes('\0')) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'The local audio URI contains a NUL character.');
  }

  if (authority.length === 0 || authority.toLowerCase() === 'localhost') return path;

  let decodedAuthority: string;
  try {
    decodedAuthority = decodeURIComponent(authority);
  } catch (_) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'The local audio URI authority contains invalid URL escaping.');
  }

  if (decodedAuthority.includes('\0')) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'The local audio URI authority contains a NUL character.');
  }

  return `${FILE_URI_PREFIX}${authority}${match[2]}`;
}

function openSourceFile(path: string, temporary: boolean): SourceFile {
  let file: fs.File | undefined;

  try {
    file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(file.fd);

    if (!stat.isFile() || !Number.isSafeInteger(stat.size) || stat.size <= 0) {
      throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'The local audio source is empty or is not a regular file.');
    }

    return new SourceFile(path, file, 0, stat.size, temporary);
  } catch (error) {
    if (file !== undefined) {
      try {
        fs.closeSync(file.fd);
      } catch (_) {}
    }

    if (temporary) deleteFile(path);

    throw new ExpoAudioError('ERR_AUDIO_PLAYER_LOAD', `The local audio source '${path}' is not readable: ${cleanError(error as Object)}`);
  }
}

function openPackagedSource(context: ExpoModuleContext, uri: string): SourceFile {
  let name: string;
  try {
    name = packagedAudioResourceName(uri);
  } catch (error) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', cleanError(error as Object));
  }

  const resources = context.uiAbilityContext.resourceManager;
  let opened = false;
  let duplicate: fs.File | undefined;

  try {
    const descriptor = resources.getRawFdSync(name);
    opened = true;

    if (
      !Number.isSafeInteger(descriptor.fd) ||
      descriptor.fd < 0 ||
      !Number.isSafeInteger(descriptor.offset) ||
      descriptor.offset < 0 ||
      !Number.isSafeInteger(descriptor.length) ||
      descriptor.length <= 0
    ) {
      throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', `The packaged audio '${name}' has an invalid file descriptor.`);
    }

    duplicate = fs.dup(descriptor.fd);

    return new SourceFile(uri, duplicate, descriptor.offset, descriptor.length, false);
  } catch (error) {
    if (duplicate !== undefined) {
      try {
        fs.closeSync(duplicate.fd);
      } catch (_) {}
    }

    throw new ExpoAudioError('ERR_AUDIO_PLAYER_LOAD', `The packaged audio '${name}' could not be opened: ${cleanError(error as Object)}`);
  } finally {
    if (opened) {
      let closed = false;

      for (let attempt = 0; attempt < FILE_CLOSE_ATTEMPTS && !closed; attempt += 1) {
        try {
          resources.closeRawFdSync(name);
          closed = true;
        } catch (_) {}
      }

      if (!closed) console.error(`Expo Audio could not close the packaged source '${name}'.`);
    }
  }
}

function writeDataUri(uri: string, cacheDir: string): string {
  const separator = uri.indexOf(',');

  if (separator <= DATA_URI_PREFIX.length) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_DATA_URI', 'The audio data URI is malformed.');
  }

  const metadata = uri.slice(0, separator);
  if (!metadata.toLowerCase().includes(DATA_URI_BASE64_MARKER)) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_DATA_URI', 'HarmonyOS audio data URIs must use base64 encoding.');
  }

  const payload = uri.slice(separator + 1);
  if (payload.length === 0) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_DATA_URI', 'The audio data URI has an empty payload.');
  }
  if (payload.length > Math.ceil((MAX_DATA_URI_PAYLOAD_BYTES * 4) / 3) + 4) {
    throw new ExpoAudioError('ERR_AUDIO_DATA_URI_TOO_LARGE', `HarmonyOS audio data URIs are limited to ${MAX_DATA_URI_PAYLOAD_BYTES} decoded bytes.`);
  }

  let bytes: Uint8Array;
  try {
    bytes = new util.Base64Helper().decodeSync(payload);
  } catch (error) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_DATA_URI', `The audio data URI is not valid base64: ${cleanError(error as Object)}`);
  }

  const folder = `${cacheDir}/expo-audio/sources`;
  if (!fs.accessSync(folder)) fs.mkdirSync(folder, true);

  sequence += 1;
  const path = `${folder}/source-${Date.now()}-${sequence}${dataUriExtension(metadata)}`;
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);

  try {
    fs.writeSync(file.fd, bytes.buffer);
  } catch (error) {
    try {
      fs.closeSync(file.fd);
    } catch (_) {}

    deleteFile(path);

    throw new ExpoAudioError('ERR_AUDIO_DATA_URI_WRITE', `The audio data URI could not be cached: ${cleanError(error as Object)}`);
  }

  let closed: boolean = false;
  for (let attempt: number = 0; attempt < FILE_CLOSE_ATTEMPTS && !closed; attempt += 1) {
    try {
      fs.closeSync(file.fd);
      closed = true;
    } catch (_) {}
  }
  if (!closed) {
    deleteFile(path);
    throw new ExpoAudioError('ERR_AUDIO_DATA_URI_CLOSE', 'The cached audio data URI file could not be closed safely.');
  }

  return path;
}

async function assignSource(
  player: media.AVPlayer,
  source: AudioSource,
  cacheDir: string,
  context: ExpoModuleContext,
): Promise<SourceFile | undefined> {
  const uri = source.uri;
  if (uri === undefined || uri.length === 0) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'The audio source does not contain a URI.');
  }

  if (isDataAudioUri(uri)) {
    const path = writeDataUri(uri, cacheDir);
    const file = openSourceFile(path, true);

    try {
      player.fdSrc = {
        fd: file.file.fd,
        offset: file.offset,
        length: file.length,
      };
    } catch (error) {
      closeSourceFile(file);

      throw new ExpoAudioError('ERR_AUDIO_PLAYER_LOAD', cleanError(error as Object));
    }

    return file;
  }

  if (isPackagedAudioUri(uri)) {
    const file = openPackagedSource(context, uri);

    try {
      player.fdSrc = {
        fd: file.file.fd,
        offset: file.offset,
        length: file.length,
      };
    } catch (error) {
      closeSourceFile(file);

      throw new ExpoAudioError('ERR_AUDIO_PLAYER_LOAD', cleanError(error as Object));
    }

    return file;
  }

  const path = localFilePath(uri);
  if (path !== undefined) {
    const file = openSourceFile(path, false);

    try {
      player.fdSrc = {
        fd: file.file.fd,
        offset: file.offset,
        length: file.length,
      };
    } catch (error) {
      closeSourceFile(file);

      throw new ExpoAudioError('ERR_AUDIO_PLAYER_LOAD', cleanError(error as Object));
    }

    return file;
  }

  if (isRemoteAudioUri(uri) && hasHeaders(source)) {
    await player.setMediaSource(media.createMediaSourceWithUrl(uri, source.headers));
  } else {
    player.url = uri;
  }

  return undefined;
}

async function waitForSourceInitialization(player: media.AVPlayer): Promise<void> {
  const initialState = player.state;
  if (initialState === 'initialized') return;
  if (initialState === 'error' || initialState === 'released') {
    throw new ExpoAudioError(
      'ERR_AUDIO_PLAYER_INITIALIZE',
      `HarmonyOS AVPlayer entered the ${initialState} state while initializing the audio source.`,
    );
  }

  let resolveReady: () => void = (): void => {};
  let failure: ExpoAudioError | undefined;
  let settled = false;
  const ready = new Promise<void>((resolve: () => void): void => {
    resolveReady = resolve;
  });
  const finish = (error?: ExpoAudioError): void => {
    if (settled) return;

    settled = true;
    failure = error;
    resolveReady();
  };
  const onState = (state: media.AVPlayerState, _: media.StateChangeReason): void => {
    if (state === 'initialized') finish();
    else if (state === 'error' || state === 'released') {
      finish(new ExpoAudioError('ERR_AUDIO_PLAYER_INITIALIZE', `HarmonyOS AVPlayer entered the ${state} state while initializing the audio source.`));
    }
  };
  const onError = (error: BusinessError): void => {
    finish(new ExpoAudioError('ERR_AUDIO_PLAYER_INITIALIZE', cleanError(error)));
  };

  let stateListening = false;
  let errorListening = false;
  let timer = -1;

  try {
    player.on('stateChange', onState);
    stateListening = true;
    player.on('error', onError);
    errorListening = true;
    timer = setTimeout((): void => {
      finish(
        new ExpoAudioError(
          'ERR_AUDIO_PLAYER_INITIALIZE_TIMEOUT',
          `HarmonyOS AVPlayer did not initialize the audio source within ${SOURCE_INITIALIZATION_TIMEOUT_MS} ms.`,
        ),
      );
    }, SOURCE_INITIALIZATION_TIMEOUT_MS);

    const state = player.state as media.AVPlayerState;
    if (state === 'initialized') finish();
    else if (state === 'error' || state === 'released') {
      finish(new ExpoAudioError('ERR_AUDIO_PLAYER_INITIALIZE', `HarmonyOS AVPlayer entered the ${state} state while initializing the audio source.`));
    }

    await ready;

    if (failure !== undefined) {
      throw new ExpoAudioError(failure.code, failure.message);
    }
  } finally {
    if (timer >= 0) clearTimeout(timer);

    if (stateListening) {
      try {
        player.off('stateChange', onState);
      } catch (_) {}
    }
    if (errorListening) {
      try {
        player.off('error', onError);
      } catch (_) {}
    }
  }
}

function publicPlaybackState(state: media.AVPlayerState, buffering: boolean): string {
  if (buffering) return 'buffering';
  if (state === 'prepared' || state === 'playing' || state === 'paused') return 'ready';
  if (state === 'completed') return 'ended';
  if (state === 'idle' || state === 'initialized' || state === 'stopped' || state === 'released') return 'idle';

  return 'unknown';
}

function audioDeviceTypeName(type: audio.DeviceType): string {
  if (type === audio.DeviceType.EARPIECE) return 'Built-in Earpiece';
  if (type === audio.DeviceType.SPEAKER) return 'Built-in Speaker';
  if (type === audio.DeviceType.WIRED_HEADSET) return 'Wired Headset';
  if (type === audio.DeviceType.WIRED_HEADPHONES) return 'Wired Headphones';
  if (type === audio.DeviceType.BLUETOOTH_SCO) return 'Bluetooth';
  if (type === audio.DeviceType.MIC) return 'Built-in Microphone';
  return `Audio Device ${type}`;
}

function normalizeLoopMode(value: ESObject): PlaylistLoopMode {
  if (value === 'single' || value === 'all') return value;
  return 'none';
}

function normalizeInterruptionMode(value: ESObject): InterruptionMode {
  if (value === 'mixWithOthers' || value === 'doNotMix' || value === 'duckOthers') return value;
  throw new ExpoAudioError('ERR_AUDIO_INVALID_INTERRUPTION_MODE', `Unsupported audio interruption mode '${String(value)}'.`);
}

function nearestLegacySpeed(rate: number): media.PlaybackSpeed {
  const choices: number[] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
  const values: media.PlaybackSpeed[] = [
    media.PlaybackSpeed.SPEED_FORWARD_0_50_X,
    media.PlaybackSpeed.SPEED_FORWARD_0_75_X,
    media.PlaybackSpeed.SPEED_FORWARD_1_00_X,
    media.PlaybackSpeed.SPEED_FORWARD_1_25_X,
    media.PlaybackSpeed.SPEED_FORWARD_1_50_X,
    media.PlaybackSpeed.SPEED_FORWARD_1_75_X,
    media.PlaybackSpeed.SPEED_FORWARD_2_00_X,
  ];

  let best = 0;
  let gap = Math.abs(rate - choices[0]);

  for (let index = 1; index < choices.length; index += 1) {
    const next = Math.abs(rate - choices[index]);
    if (next < gap) {
      gap = next;
      best = index;
    }
  }

  return values[best];
}

function legacySpeedValue(speed: media.PlaybackSpeed): number {
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_0_50_X) return 0.5;
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_0_75_X) return 0.75;
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_1_25_X) return 1.25;
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_1_50_X) return 1.5;
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_1_75_X) return 1.75;
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_2_00_X) return 2;
  return 1;
}

abstract class PlaybackController extends OperationQueue {
  readonly objectId: number;
  readonly id: string;
  readonly keepsAudioSessionActive: boolean;
  protected readonly dispatcher: AudioObjectEventSink;
  protected readonly delegate: PlaybackDelegate;
  protected player?: media.AVPlayer;
  protected sourceFile?: SourceFile;
  protected source: AudioSource | null;
  protected destroyed: boolean = false;
  protected updateTimer: number = -1;
  protected observedEvents: Set<string> = new Set();
  protected intendedPlaying: boolean = false;
  protected didJustFinish: boolean = false;
  protected currentTimeMs: number = 0;
  protected durationMs: number = 0;
  protected state: media.AVPlayerState = 'idle';
  protected volumeValue: number = 1;
  protected mutedValue: boolean = false;
  protected loopValue: boolean = false;
  protected rateValue: number = 1;
  protected correctPitchValue: boolean = true;
  protected bufferingValue: boolean = false;
  protected loadedValue: boolean = false;
  protected playingValue: boolean = false;
  protected duckedValue: boolean = false;
  private backgroundSuspended: boolean = false;
  private interruptionSuspended: boolean = false;
  private readonly updateIntervalMs: number;
  private readonly preferredBufferDuration: number;

  constructor(
    objectId: number,
    source: AudioSource | null,
    updateInterval: number,
    keepsAudioSessionActive: boolean,
    preferredBufferDuration: number,
    dispatcher: AudioObjectEventSink,
    delegate: PlaybackDelegate,
  ) {
    super();

    this.objectId = objectId;
    this.id = `expo-audio-${objectId}`;
    this.source = source;
    this.updateIntervalMs = Math.max(MIN_UPDATE_INTERVAL_MS, finiteNumber(updateInterval, 500));
    this.keepsAudioSessionActive = keepsAudioSessionActive;
    this.preferredBufferDuration = Math.max(0, finiteNumber(preferredBufferDuration, 0));
    this.dispatcher = dispatcher;
    this.delegate = delegate;

    this.schedule('initialize', async (): Promise<void> => this.replacePlayer(source, false));
  }

  get playing(): boolean {
    return effectivePlaying(this.playingValue, this.bufferingValue, this.intendedPlaying);
  }
  get muted(): boolean {
    return this.mutedValue;
  }
  get looping(): boolean {
    return this.loopValue;
  }
  get loaded(): boolean {
    return this.loadedValue;
  }
  get buffering(): boolean {
    return this.bufferingValue;
  }
  get currentTimeSeconds(): number {
    this.refreshPosition();
    return this.currentTimeMs / 1000;
  }
  get durationSeconds(): number {
    return this.durationMs / 1000;
  }
  get playbackRate(): number {
    return this.rateValue;
  }
  get correctsPitch(): boolean {
    return this.correctPitchValue;
  }
  get wantsToPlay(): boolean {
    return this.intendedPlaying;
  }
  get volume(): number {
    return this.volumeValue;
  }
  get playbackState(): string {
    return publicPlaybackState(this.state, this.bufferingValue);
  }
  get released(): boolean {
    return this.destroyed;
  }
  get sourceUri(): string | undefined {
    return this.source?.uri;
  }

  setObserving(eventName: string, observing: boolean): void {
    if (observing) this.observedEvents.add(eventName);
    else this.observedEvents.delete(eventName);
    this.updateStatusTimer();
    if (observing && eventName === this.statusEventName()) this.emitStatus();
  }

  get currentStatus(): ESObject {
    this.refreshPosition();
    return this.statusPayload(false);
  }

  setMuted(value: boolean): void {
    this.mutedValue = value;
    this.schedule('set muted', async (): Promise<void> => this.applyVolume());
    this.emitStatus();
  }

  setLooping(value: boolean): void {
    this.loopValue = value;
    this.schedule('set loop', async (): Promise<void> => {
      if (this.player !== undefined && this.isPreparedState(this.player.state)) this.player.loop = this.loopValue;
    });
    this.emitStatus();
  }

  setVolume(value: number): void {
    this.volumeValue = bounded(value, 0, 1);
    this.schedule('set volume', async (): Promise<void> => this.applyVolume());
    this.emitStatus();
  }

  setShouldCorrectPitch(value: boolean): void {
    if (!value) {
      throw new ExpoAudioError(
        'ERR_AUDIO_PITCH_CORRECTION_UNSUPPORTED',
        'HarmonyOS AVPlayer does not expose a control for disabling pitch correction.',
      );
    }

    this.correctPitchValue = true;
    this.emitStatus();
  }

  replace(source: AudioSource | null): void {
    this.schedule('replace source', async (): Promise<void> => this.replacePlayer(source, this.intendedPlaying));
  }

  refreshAudioRendererUsage(): void {
    this.schedule('replace source', async (): Promise<void> => this.replacePlayer(this.source, this.intendedPlaying));
  }

  async seekTo(seconds: number): Promise<void> {
    await this.enqueue(async (): Promise<void> => this.seek(seconds));
  }

  setAudioSamplingEnabled(enabled: boolean): void {
    if (enabled) {
      throw new ExpoAudioError('ERR_AUDIO_SAMPLING_UNSUPPORTED', 'HarmonyOS AVPlayer does not expose decoded PCM frames for audio sampling.');
    }
  }

  play(): void {
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    const wasPlaying = this.playing;
    this.intendedPlaying = true;

    if (wasPlaying !== this.playing) this.delegate.playbackStateChanged(this);
    this.emitStatus();

    this.schedule('play', async (): Promise<void> => {
      if (!(await this.delegate.beforePlay())) {
        this.intendedPlaying = false;
        return;
      }

      const player = this.requirePreparedPlayer('play');
      if (player.state === 'completed') player.seek(0, media.SeekMode.SEEK_CLOSEST);

      await player.play();
    });
  }

  pause(): void {
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.pauseForSuspension();
  }

  suspendForBackground(): void {
    if (this.destroyed || this.backgroundSuspended) return;
    if (!this.playingValue && !this.intendedPlaying && !this.interruptionSuspended) return;
    this.backgroundSuspended = true;
    this.pauseForSuspension();
  }

  resumeFromBackground(): void {
    if (!this.backgroundSuspended) return;
    this.backgroundSuspended = false;
    if (!this.interruptionSuspended) this.play();
  }

  suspendForInterruption(): void {
    if (this.destroyed || this.interruptionSuspended) return;
    if (!this.playingValue && !this.intendedPlaying && !this.backgroundSuspended) return;
    this.interruptionSuspended = true;
    this.pauseForSuspension();
  }

  resumeFromInterruption(): void {
    if (!this.interruptionSuspended) return;
    this.interruptionSuspended = false;
    if (!this.backgroundSuspended) this.play();
  }

  cancelSuspensions(): void {
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
  }

  setDucked(ducked: boolean): void {
    if (this.duckedValue === ducked) return;

    this.duckedValue = ducked;
    this.schedule(ducked ? 'duck volume' : 'restore volume', async (): Promise<void> => this.applyVolume());
  }

  private pauseForSuspension(): void {
    const wasPlaying = this.playing;
    this.intendedPlaying = false;

    if (wasPlaying !== this.playing) this.delegate.playbackStateChanged(this);
    this.emitStatus();

    this.schedule('pause', async (): Promise<void> => {
      const player = this.player;
      if (player !== undefined && player.state === 'playing') await player.pause();
    });
  }

  setPlaybackRate(rate: number): void {
    const requested: number = bounded(rate, MIN_PLAYBACK_RATE, MAX_PLAYBACK_RATE);
    if (!deviceInfo.apiAvailable(20)) {
      const effective: number = legacySpeedValue(nearestLegacySpeed(requested));
      if (Math.abs(effective - requested) > 0.000001) {
        throw new ExpoAudioError('ERR_AUDIO_PLAYBACK_RATE_UNSUPPORTED', `HarmonyOS below API 20 cannot represent playback rate ${requested}.`);
      }
    }
    this.rateValue = requested;
    this.schedule('set playback rate', async (): Promise<void> => this.applyPlaybackRate());
    this.emitStatus();
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.cancelSuspensions();
    this.observedEvents.clear();
    this.stopStatusTimer();

    this.schedule('release', async (): Promise<void> => {
      const player = this.player;
      const file = this.sourceFile;
      this.player = undefined;
      this.sourceFile = undefined;

      await this.releasePlayer(player, file);
    });
  }

  protected abstract className(): string;
  protected abstract statusEventName(): string;
  protected abstract statusPayload(didJustFinish: boolean): ESObject;

  protected async onCompleted(): Promise<void> {}

  protected shouldContinueAfterCompletion(): boolean {
    return false;
  }

  protected emitStatus(): void {
    const finished = this.didJustFinish;
    this.didJustFinish = false;

    if (this.destroyed || !this.observedEvents.has(this.statusEventName())) return;

    this.refreshPosition();

    this.dispatcher.emit(this.statusEventName(), this.statusPayload(finished));
  }

  protected async replacePlayer(source: AudioSource | null, resume: boolean): Promise<void> {
    if (this.destroyed) return;

    const previous = this.player;
    const previousFile = this.sourceFile;
    const wasPlaying = this.playing;

    this.player = undefined;
    this.sourceFile = undefined;
    this.source = source;
    this.state = 'idle';
    this.loadedValue = false;
    this.bufferingValue = source !== null;
    this.playingValue = false;
    this.currentTimeMs = 0;
    this.durationMs = 0;
    this.didJustFinish = false;

    if (wasPlaying !== this.playing) this.delegate.playbackStateChanged(this);
    this.emitStatus();

    if (previous !== undefined && previous.state === 'playing') {
      try {
        await previous.pause();
      } catch (_) {}
    }

    await this.releasePlayer(previous, previousFile);

    let next: media.AVPlayer | undefined;
    let nextFile: SourceFile | undefined;
    try {
      if (source === null || source.uri === undefined || source.uri.length === 0) {
        next = await media.createAVPlayer();
      } else {
        const prepared = await this.delegate.takePreloaded(source);

        if (prepared !== undefined) {
          next = prepared.player;
          nextFile = prepared.file;
        } else {
          next = await media.createAVPlayer();
          nextFile = await assignSource(next, source, this.delegate.cacheDir, this.delegate.context);
          await waitForSourceInitialization(next);

          if (this.preferredBufferDuration > 0) {
            await next.setPlaybackStrategy({ preferredBufferDuration: this.preferredBufferDuration });
          }

          next.audioRendererInfo = {
            usage: this.delegate.playbackUsage(),
            rendererFlags: 0,
          };
          await next.prepare();
        }
      }

      if (this.destroyed) {
        await this.releasePlayer(next, nextFile);
        return;
      }

      this.player = next;
      this.sourceFile = nextFile;
      this.attachPlayerCallbacks(next);
      this.state = next.state;
      this.loadedValue = this.isPreparedState(next.state);
      this.bufferingValue = false;
      this.durationMs = this.safeDuration(next);

      if (source !== null) {
        next.loop = this.loopValue;
        await this.applyVolume();
        await this.applyPlaybackRate();
      }

      this.emitStatus();
    } catch (error) {
      if (this.player === next) this.player = undefined;
      if (this.sourceFile === nextFile) this.sourceFile = undefined;

      await this.releasePlayer(next, nextFile);

      this.state = 'error';
      this.loadedValue = false;
      this.bufferingValue = false;
      this.playingValue = false;
      this.currentTimeMs = 0;
      this.durationMs = 0;

      throw new ExpoAudioError('ERR_AUDIO_PLAYER_LOAD', cleanError(error as Object));
    }

    if (resume && this.intendedPlaying) this.play();
  }

  protected async seek(seconds: number): Promise<void> {
    const player = this.requirePreparedPlayer('seek');
    const length = this.safeDuration(player);
    const target = seekTargetMilliseconds(seconds, length);

    player.seek(target, media.SeekMode.SEEK_CLOSEST);
    this.currentTimeMs = target;

    this.emitStatus();
  }

  protected onScheduledError(label: string, error: Object): void {
    if (this.destroyed && label !== 'release') return;

    console.error(`Expo Audio ${label} failed for ${this.id}: ${cleanError(error)}`);

    if (
      label !== 'initialize' &&
      label !== 'replace source' &&
      label !== 'change playlist track' &&
      label !== 'remove current track' &&
      label !== 'advance after completion' &&
      label !== 'player state' &&
      label !== 'player callback'
    ) {
      this.emitStatus();
      return;
    }

    const wasPlaying = this.playing;
    const player = this.player;
    const file = this.sourceFile;

    this.player = undefined;
    this.sourceFile = undefined;
    this.state = 'error';
    this.bufferingValue = false;
    this.playingValue = false;
    this.intendedPlaying = false;
    this.loadedValue = false;
    this.currentTimeMs = 0;
    this.durationMs = 0;

    this.emitStatus();
    if (wasPlaying !== this.playing) this.delegate.playbackStateChanged(this);

    this.enqueue(async (): Promise<void> => this.releasePlayer(player, file)).catch((): void => {});
  }

  private attachPlayerCallbacks(target: media.AVPlayer): void {
    if (!deviceInfo.apiAvailable(20)) {
      target.on('audioInterrupt', (event: audio.InterruptEvent): void => {
        if (this.destroyed || this.player !== target) return;
        if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
          this.suspendForInterruption();
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
          this.resumeFromInterruption();
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
          this.setDucked(true);
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
          this.setDucked(false);
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
          this.pause();
        }
      });
    }
    target.on('stateChange', (state: media.AVPlayerState, _: media.StateChangeReason): void => {
      if (this.destroyed || this.player !== target) return;
      if (state === 'error' || state === 'released') {
        this.onScheduledError('player state', new ExpoAudioError('ERR_AUDIO_PLAYER_STATE', `HarmonyOS AVPlayer entered the ${state} state.`));
        return;
      }

      const wasPlaying = this.playing;

      this.state = state;
      this.playingValue = state === 'playing';
      this.loadedValue = this.isPreparedState(state);

      if (state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed') {
        this.bufferingValue = false;
        this.durationMs = this.safeDuration(target);
        this.refreshPosition();
      }

      if (state === 'completed') {
        const continuing: boolean = this.shouldContinueAfterCompletion();
        this.didJustFinish = !continuing;
        this.intendedPlaying = continuing;
        this.schedule('advance after completion', async (): Promise<void> => this.onCompleted());
      }

      if (wasPlaying !== this.playing && !(state === 'completed' && this.intendedPlaying)) {
        this.delegate.playbackStateChanged(this);
      }

      this.updateStatusTimer();
      this.emitStatus();
    });
    target.on('timeUpdate', (time: number): void => {
      if (this.player !== target) return;
      this.currentTimeMs = Math.max(0, time);
    });
    target.on('durationUpdate', (duration: number): void => {
      if (this.player !== target) return;
      this.durationMs = Math.max(0, duration);
      this.emitStatus();
    });
    target.on('bufferingUpdate', (type: media.BufferingInfoType, _: number): void => {
      if (this.player !== target) return;

      const wasPlaying = this.playing;

      if (type === media.BufferingInfoType.BUFFERING_START) this.bufferingValue = true;
      if (type === media.BufferingInfoType.BUFFERING_END) this.bufferingValue = false;

      if (wasPlaying !== this.playing) this.delegate.playbackStateChanged(this);
      this.emitStatus();
    });
    target.on('seekDone', (time: number): void => {
      if (this.player !== target) return;
      this.currentTimeMs = Math.max(0, time);
      this.emitStatus();
    });
    target.on('audioOutputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo): void => {
      if (this.player !== target) return;
      if (info.changeReason !== audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) return;

      this.pause();
    });
    target.on('error', (error: BusinessError): void => {
      if (this.player !== target) return;
      this.onScheduledError('player callback', error);
    });
  }

  private refreshPosition(): void {
    const player = this.player;
    if (player === undefined || !this.isPreparedState(player.state)) return;

    try {
      this.currentTimeMs = Math.max(0, player.currentTime);
      this.durationMs = this.safeDuration(player);
    } catch (_) {}
  }

  private safeDuration(player: media.AVPlayer): number {
    try {
      const duration = player.duration;
      return Number.isFinite(duration) && duration > 0 ? duration : 0;
    } catch (_) {
      return 0;
    }
  }

  private async releasePlayer(player?: media.AVPlayer, file?: SourceFile): Promise<void> {
    if (player !== undefined && player.state !== 'released') {
      try {
        await player.release();
      } catch (_) {}
    }

    closeSourceFile(file);
  }

  private requirePreparedPlayer(operation: string): media.AVPlayer {
    if (this.destroyed) {
      throw new ExpoAudioError('ERR_AUDIO_PLAYER_RELEASED', `Cannot ${operation}; the audio object was released.`);
    }

    const player = this.player;
    if (player === undefined || !this.isPreparedState(player.state)) {
      throw new ExpoAudioError('ERR_AUDIO_NOT_LOADED', `Cannot ${operation}; no audio source is loaded.`);
    }

    return player;
  }

  private isPreparedState(state: media.AVPlayerState): boolean {
    return state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed';
  }

  private async applyVolume(): Promise<void> {
    const player = this.player;
    if (player === undefined || !this.isPreparedState(player.state)) return;

    const volume = this.duckedValue ? this.volumeValue * DUCKING_VOLUME : this.volumeValue;

    player.setVolume(this.mutedValue ? 0 : volume);
  }

  private async applyPlaybackRate(): Promise<void> {
    const player = this.player;
    if (player === undefined || !this.isPreparedState(player.state)) return;

    if (deviceInfo.apiAvailable(20)) {
      player.setPlaybackRate(this.rateValue);
    } else {
      const speed = nearestLegacySpeed(this.rateValue);
      player.setSpeed(speed);
    }
  }

  private updateStatusTimer(): void {
    const running = this.playing && this.observedEvents.has(this.statusEventName()) && !this.destroyed;

    if (!running) {
      this.stopStatusTimer();
      return;
    }
    if (this.updateTimer >= 0) return;

    this.updateTimer = setInterval((): void => this.emitStatus(), this.updateIntervalMs);
  }

  private stopStatusTimer(): void {
    if (this.updateTimer < 0) return;

    clearInterval(this.updateTimer);
    this.updateTimer = -1;
  }
}

class AudioPlayerController extends PlaybackController {
  private metadata?: AudioMetadataInput;
  private lockScreenOptions?: LockScreenOptionsInput;
  private activeForLockScreen: boolean = false;

  protected className(): string {
    return PLAYER_CLASS_NAME;
  }
  protected statusEventName(): string {
    return PLAYBACK_STATUS_EVENT;
  }
  protected statusPayload(didJustFinish: boolean): ESObject {
    return new AudioStatusRecord(this, didJustFinish);
  }

  setActiveForLockScreen(active: boolean, metadata?: AudioMetadataInput, options?: LockScreenOptionsInput): void {
    this.activeForLockScreen = active;
    this.metadata = metadata;
    this.lockScreenOptions = options;
    this.delegate.setLockScreenPlayer(this, active, metadata, options);
  }

  updateLockScreenMetadata(metadata?: AudioMetadataInput): void {
    this.metadata = metadata;

    if (this.activeForLockScreen) {
      this.delegate.setLockScreenPlayer(this, true, metadata, this.lockScreenOptions);
    }
  }

  clearLockScreenControls(): void {
    this.activeForLockScreen = false;
    this.delegate.setLockScreenPlayer(this, false);
  }

  protected emitStatus(): void {
    super.emitStatus();
    if (this.activeForLockScreen) this.delegate.lockScreenStateChanged(this);
  }

  destroy(): void {
    if (this.activeForLockScreen) this.delegate.setLockScreenPlayer(this, false);
    super.destroy();
  }
}

class PlaylistController extends PlaybackController {
  private tracks: AudioSource[];
  private indexValue: number = 0;
  private loopModeValue: PlaylistLoopMode;

  constructor(
    objectId: number,
    sources: AudioSource[],
    updateInterval: number,
    loopMode: PlaylistLoopMode,
    dispatcher: AudioObjectEventSink,
    delegate: PlaybackDelegate,
  ) {
    super(objectId, sources.length > 0 ? sources[0] : null, updateInterval, false, 0, dispatcher, delegate);

    this.tracks = sources;
    this.loopModeValue = loopMode;
    this.loopValue = loopMode === 'single';
  }

  get currentIndex(): number {
    return this.indexValue;
  }
  get trackCount(): number {
    return this.tracks.length;
  }
  get loopMode(): PlaylistLoopMode {
    return this.loopModeValue;
  }

  protected className(): string {
    return PLAYLIST_CLASS_NAME;
  }
  protected statusEventName(): string {
    return PLAYLIST_STATUS_EVENT;
  }
  protected statusPayload(didJustFinish: boolean): ESObject {
    return new PlaylistStatusRecord(this, didJustFinish);
  }

  get sources(): AudioSourceInfoRecord[] {
    return this.tracks.map((source: AudioSource): AudioSourceInfoRecord => new AudioSourceInfoRecord(source));
  }

  setLoopMode(value: string): void {
    this.loopModeValue = normalizeLoopMode(value);
    this.setLooping(this.loopModeValue === 'single');
  }

  next(): void {
    this.scheduleRelativeTrackChange(1);
  }

  previous(): void {
    this.scheduleRelativeTrackChange(-1);
  }

  skipTo(index: number): void {
    this.scheduleTrackChange(Math.trunc(index));
  }

  add(source: AudioSource | null): void {
    if (source === null || source.uri === undefined || source.uri.length === 0) return;

    this.tracks.push(source);
    if (this.tracks.length === 1) this.scheduleTrackChange(0, false);
    this.emitStatus();
  }

  insert(source: AudioSource | null, index: number): void {
    const position = Math.trunc(index);
    if (source === null || source.uri === undefined || source.uri.length === 0 || position < 0 || position > this.tracks.length) return;

    this.tracks.splice(position, 0, source);

    if (this.tracks.length === 1) this.scheduleTrackChange(0, false);
    else if (position <= this.indexValue) this.indexValue += 1;

    this.emitStatus();
  }

  remove(index: number): void {
    this.removeTrack(Math.trunc(index));
  }

  clear(): void {
    this.tracks = [];
    this.indexValue = 0;
    this.intendedPlaying = false;

    this.schedule('clear playlist', async (): Promise<void> => this.replacePlayer(null, false));
    this.emitStatus();
  }

  protected async onCompleted(): Promise<void> {
    if (this.tracks.length === 0) return;
    if (this.loopModeValue === 'single') {
      await this.replacePlayer(this.tracks[this.indexValue], true);
      return;
    }
    if (this.indexValue + 1 < this.tracks.length) {
      await this.changeTrack(this.indexValue + 1, true);
      return;
    }
    if (this.loopModeValue === 'all') {
      await this.changeTrack(0, true);
    }
  }

  protected shouldContinueAfterCompletion(): boolean {
    return this.tracks.length > 0 && (this.loopModeValue === 'single' || this.indexValue + 1 < this.tracks.length || this.loopModeValue === 'all');
  }

  private nextIndex(): number {
    return nextPlaylistIndex(this.indexValue, this.tracks.length, this.loopModeValue === 'all');
  }

  private previousIndex(): number {
    return previousPlaylistIndex(this.indexValue, this.tracks.length, this.loopModeValue === 'all');
  }

  private scheduleTrackChange(index: number, preservePlayback: boolean = true): void {
    this.schedule('change playlist track', async (): Promise<void> => {
      if (index < 0 || index >= this.tracks.length || (index === this.indexValue && this.loaded)) return;

      await this.changeTrack(index, preservePlayback && this.intendedPlaying);
    });
  }

  private scheduleRelativeTrackChange(offset: number): void {
    this.schedule('change playlist track', async (): Promise<void> => {
      const index = offset > 0 ? this.nextIndex() : this.previousIndex();
      if (index < 0 || index >= this.tracks.length || (index === this.indexValue && this.loaded)) return;

      await this.changeTrack(index, this.intendedPlaying);
    });
  }

  private async changeTrack(index: number, resume: boolean): Promise<void> {
    if (index < 0 || index >= this.tracks.length) return;

    const previous = this.indexValue;
    this.indexValue = index;

    await this.replacePlayer(this.tracks[index], resume);
    if (this.destroyed) return;

    if (previous !== index && this.observedEvents.has(TRACK_CHANGED_EVENT)) {
      this.dispatcher.emit(TRACK_CHANGED_EVENT, new TrackChangedRecord(previous, index));
    }

    this.emitStatus();
  }

  private removeTrack(index: number): void {
    if (index < 0 || index >= this.tracks.length) return;

    const current = index === this.indexValue;
    const resume = this.playing || this.intendedPlaying;

    this.tracks.splice(index, 1);

    if (this.tracks.length === 0) {
      this.indexValue = 0;
      this.schedule('empty playlist', async (): Promise<void> => this.replacePlayer(null, false));
    } else if (current) {
      this.indexValue = Math.min(index, this.tracks.length - 1);
      this.schedule('remove current track', async (): Promise<void> => this.replacePlayer(this.tracks[this.indexValue], resume));
    } else if (index < this.indexValue) {
      this.indexValue -= 1;
    }

    this.emitStatus();
  }
}

function readMetadata(value: ESObject): AudioMetadataInput | undefined {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return undefined;

  const input = value as Record<string, ESObject>;
  const metadata: AudioMetadataInput = {};

  if (typeof input.title === 'string') metadata.title = input.title;
  if (typeof input.artist === 'string') metadata.artist = input.artist;
  if (typeof input.albumTitle === 'string') metadata.albumTitle = input.albumTitle;
  if (typeof input.artworkUrl === 'string') metadata.artworkUrl = input.artworkUrl;

  return metadata;
}

function readLockScreenOptions(value: ESObject): LockScreenOptionsInput | undefined {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return undefined;

  const input = value as Record<string, ESObject>;

  return {
    showSeekForward: input.showSeekForward === true,
    showSeekBackward: input.showSeekBackward === true,
  };
}

function readRecordingOptions(value: ESObject, fallback?: RecordingOptionsInput): RecordingOptionsInput {
  const options: RecordingOptionsInput = {};

  if (fallback !== undefined) {
    options.extension = fallback.extension;
    options.sampleRate = fallback.sampleRate;
    options.numberOfChannels = fallback.numberOfChannels;
    options.bitRate = fallback.bitRate;
    options.isMeteringEnabled = fallback.isMeteringEnabled;
    options.mimeType = fallback.mimeType;
    options.bitsPerSecond = fallback.bitsPerSecond;
  }

  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return options;

  const input = value as Record<string, ESObject>;

  if (typeof input.extension === 'string') options.extension = input.extension;
  if (typeof input.sampleRate === 'number') options.sampleRate = input.sampleRate;
  if (typeof input.numberOfChannels === 'number') options.numberOfChannels = input.numberOfChannels;
  if (typeof input.bitRate === 'number') options.bitRate = input.bitRate;
  if (typeof input.isMeteringEnabled === 'boolean') options.isMeteringEnabled = input.isMeteringEnabled;
  if (typeof input.mimeType === 'string') options.mimeType = input.mimeType;
  if (typeof input.bitsPerSecond === 'number') options.bitsPerSecond = input.bitsPerSecond;

  return options;
}

function mergeRecordingOptions(fallback: RecordingOptionsInput, input: RecordingOptionsInput): RecordingOptionsInput {
  const options: RecordingOptionsInput = {};
  options.extension = input.extension ?? fallback.extension;
  options.sampleRate = input.sampleRate ?? fallback.sampleRate;
  options.numberOfChannels = input.numberOfChannels ?? fallback.numberOfChannels;
  options.bitRate = input.bitRate ?? fallback.bitRate;
  options.isMeteringEnabled = input.isMeteringEnabled ?? fallback.isMeteringEnabled;
  options.mimeType = input.mimeType ?? fallback.mimeType;
  options.bitsPerSecond = input.bitsPerSecond ?? fallback.bitsPerSecond;
  return options;
}

function readRecordingStartOptions(value: ESObject): RecordingStartOptions {
  const options: RecordingStartOptions = {};

  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return options;

  const input = value as Record<string, ESObject>;

  if (typeof input.atTime === 'number') options.atTime = input.atTime;
  if (typeof input.forDuration === 'number') options.forDuration = input.forDuration;

  return options;
}

class RecorderProfile {
  extension: string;
  profile: media.AVRecorderProfile;

  constructor(extension: string, profile: media.AVRecorderProfile) {
    this.extension = extension;
    this.profile = profile;
  }
}

function recordingProfile(options: RecordingOptionsInput): RecorderProfile {
  const requestedExtension = options.extension ?? (options.mimeType === 'audio/mpeg' ? '.mp3' : '.m4a');
  if (!isSupportedRecordingExtension(requestedExtension)) {
    throw new ExpoAudioError(
      'ERR_AUDIO_RECORDING_FORMAT_UNSUPPORTED',
      `HarmonyOS Expo Audio supports only M4A/AAC and MP3 recording, not '${requestedExtension}'.`,
    );
  }

  const extension = requestedExtension.trim().toLowerCase().replace(/^\./, '');
  const sampleRate = Math.trunc(bounded(finiteNumber(options.sampleRate, 44100), 8000, 96000));
  const channels = Math.trunc(bounded(finiteNumber(options.numberOfChannels, 2), 1, 2));
  const bitRate = Math.trunc(bounded(finiteNumber(options.bitRate ?? options.bitsPerSecond, 128000), 32000, 320000));

  if (extension === 'mp3') {
    return new RecorderProfile('.mp3', {
      audioBitrate: bitRate,
      audioChannels: channels,
      audioCodec: media.CodecMimeType.AUDIO_MP3,
      audioSampleRate: sampleRate,
      fileFormat: media.ContainerFormatType.CFT_MP3,
    });
  }

  // AAC in an M4A container is the broadly supported HarmonyOS recording path
  // and matches Expo's high-quality preset semantics.
  return new RecorderProfile('.m4a', {
    audioBitrate: bitRate,
    audioChannels: channels,
    audioCodec: media.CodecMimeType.AUDIO_AAC,
    audioSampleRate: sampleRate,
    fileFormat: media.ContainerFormatType.CFT_MPEG_4A,
  });
}

interface RecorderDelegate {
  readonly context: ExpoModuleContext;
  ensureRecordingPermission(): void;
  recordingStateChanged(): void;
}

class AudioRecorderController extends OperationQueue {
  readonly objectId: number;
  readonly id: string;
  private readonly dispatcher: AudioObjectEventSink;
  private readonly delegate: RecorderDelegate;
  private options: RecordingOptionsInput;
  private recorder?: media.AVRecorder;
  private outputFile?: fs.File;
  private outputPath: string | null = null;
  private preparedValue: boolean = false;
  private recordingValue: boolean = false;
  private pausedValue: boolean = false;
  private destroyed: boolean = false;
  private elapsedBeforeStartMs: number = 0;
  private startedAtMs: number = 0;
  private meteringValue?: number;
  private meteringTimer: number = -1;
  private delayedStartTimer: number = -1;
  private stopTimer: number = -1;
  private observed: boolean = false;
  private failed: boolean = false;
  private backgroundSuspended: boolean = false;
  private interruptionSuspended: boolean = false;
  private recordingRequested: boolean = false;
  private recordGeneration: number = 0;
  private delayedStartDeadlineMs: number = 0;
  // -1 means no automatic stop was requested; 0 means stop immediately.
  private pendingDurationMs: number = -1;

  constructor(objectId: number, options: RecordingOptionsInput, dispatcher: AudioObjectEventSink, delegate: RecorderDelegate) {
    super();

    this.objectId = objectId;
    this.id = `expo-audio-recorder-${objectId}`;
    this.options = options;
    this.dispatcher = dispatcher;
    this.delegate = delegate;
  }

  get prepared(): boolean {
    return this.preparedValue;
  }
  get recording(): boolean {
    return this.recordingValue;
  }
  get durationMillis(): number {
    if (!this.recordingValue) return this.elapsedBeforeStartMs;
    return this.elapsedBeforeStartMs + Math.max(0, uptimeMilliseconds() - this.startedAtMs);
  }
  get uri(): string | null {
    return this.outputPath === null ? null : `file://${this.outputPath}`;
  }
  get metering(): number | undefined {
    return this.meteringValue;
  }

  setObserving(eventName: string, observing: boolean): void {
    if (eventName !== RECORDING_STATUS_EVENT) return;
    this.observed = observing;
  }

  get currentStatus(): RecorderStateRecord {
    return new RecorderStateRecord(this);
  }

  async prepareToRecord(options?: RecordingOptionsInput): Promise<void> {
    const merged: RecordingOptionsInput = options === undefined ? this.options : mergeRecordingOptions(this.options, options);
    await this.enqueue(async (): Promise<void> => this.prepare(merged));
  }

  async stop(): Promise<void> {
    await this.enqueue(async (): Promise<void> => this.stopInternal(null));
  }

  startRecordingAtTime(seconds: number): void {
    this.record({ atTime: seconds });
  }

  recordForDuration(seconds: number): void {
    this.record({ forDuration: seconds });
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.observed = false;
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;

    this.clearTimers();
    this.schedule('release recorder', async (): Promise<void> => this.releaseRecorder());
  }

  protected onScheduledError(label: string, error: Object): void {
    if (this.destroyed && label !== 'release recorder') return;

    const message = cleanError(error);
    console.error(`Expo Audio ${label} failed for ${this.id}: ${message}`);

    if (this.failed) return;

    this.failed = true;
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;
    this.recordingValue = false;
    this.pausedValue = false;
    this.preparedValue = false;

    this.clearTimers();
    this.emitResult(message);
    this.delegate.recordingStateChanged();

    this.enqueue(async (): Promise<void> => this.releaseRecorder()).catch((): void => {});
  }

  private async prepare(options: RecordingOptionsInput): Promise<void> {
    if (this.destroyed) throw new ExpoAudioError('ERR_AUDIO_RECORDER_RELEASED', 'The audio recorder was released.');

    this.delegate.ensureRecordingPermission();

    if (this.preparedValue) {
      throw new ExpoAudioError('ERR_AUDIO_RECORDER_ALREADY_PREPARED', 'The audio recorder is already prepared.');
    }

    this.options = options;
    this.failed = false;
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;

    const profile = recordingProfile(options);
    const folder = `${this.delegate.context.uiAbilityContext.cacheDir}/expo-audio`;

    if (!fs.accessSync(folder)) fs.mkdirSync(folder, true);

    sequence += 1;
    const path = `${folder}/recording-${Date.now()}-${sequence}${profile.extension}`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);

    let recorder: media.AVRecorder | undefined;
    try {
      recorder = await media.createAVRecorder();

      recorder.on('stateChange', (state: media.AVRecorderState, _: media.StateChangeReason): void => {
        if (this.recorder !== recorder || this.destroyed) return;

        this.handleStateChange(state);
      });
      recorder.on('error', (error: BusinessError): void => {
        if (this.recorder === recorder) this.onScheduledError('recorder callback', error);
      });

      await recorder.prepare({
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: profile.profile,
        url: `fd://${file.fd}`,
      });

      if (deviceInfo.apiAvailable(20)) await recorder.setWillMuteWhenInterrupted(true);
    } catch (error) {
      if (recorder !== undefined) {
        try {
          await recorder.release();
        } catch (_) {}
      }

      try {
        fs.closeSync(file.fd);
      } catch (_) {}

      deleteFile(path);

      throw new ExpoAudioError('ERR_AUDIO_RECORDER_PREPARE', cleanError(error as Object));
    }

    if (recorder === undefined) {
      try {
        fs.closeSync(file.fd);
      } catch (_) {}

      deleteFile(path);

      throw new ExpoAudioError('ERR_AUDIO_RECORDER_PREPARE', 'HarmonyOS did not create an AVRecorder instance.');
    }

    this.recorder = recorder;
    this.outputFile = file;
    this.outputPath = path;
    this.preparedValue = true;
    this.recordingValue = false;
    this.pausedValue = false;
    this.elapsedBeforeStartMs = 0;
    this.meteringValue = options.isMeteringEnabled === true ? SILENCE_LEVEL_DB : undefined;
  }

  record(options: RecordingStartOptions): void {
    this.delegate.ensureRecordingPermission();

    if (!this.preparedValue || this.recorder === undefined) {
      throw new ExpoAudioError('ERR_AUDIO_RECORDER_NOT_PREPARED', 'Call prepareToRecordAsync() before starting an audio recording.');
    }

    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.recordingRequested = true;
    this.recordGeneration += 1;
    const generation = this.recordGeneration;

    this.clearStartAndStopTimers();

    if (options.atTime !== undefined && (!Number.isFinite(options.atTime) || options.atTime < 0)) {
      throw new ExpoAudioError('ERR_AUDIO_INVALID_RECORDING_TIME', 'Recording start time must be a finite non-negative number.');
    }
    if ((options.atTime ?? 0) > 0) {
      throw new ExpoAudioError(
        'ERR_AUDIO_RECORDING_AT_TIME_UNSUPPORTED',
        'HarmonyOS AVRecorder does not provide a device-clock scheduled recording start.',
      );
    }
    if (options.forDuration !== undefined && (!Number.isFinite(options.forDuration) || options.forDuration < 0)) {
      throw new ExpoAudioError('ERR_AUDIO_INVALID_RECORDING_DURATION', 'Recording duration must be a finite non-negative number.');
    }
    const delay: number = 0;
    this.pendingDurationMs = options.forDuration === undefined ? -1 : positiveDelayMilliseconds(options.forDuration);

    const begin = (): void => {
      this.delayedStartTimer = -1;
      this.delayedStartDeadlineMs = 0;

      if (generation !== this.recordGeneration || !this.recordingRequested || this.backgroundSuspended || this.interruptionSuspended) return;

      this.scheduleRecordingStart(generation);
    };

    if (delay > 0) {
      this.delayedStartDeadlineMs = uptimeMilliseconds() + delay;
      this.delayedStartTimer = setTimeout(begin, delay);
    } else {
      begin();
    }
  }

  private scheduleRecordingStart(generation: number): void {
    const duration = this.pendingDurationMs;

    this.schedule('start recorder', async (): Promise<void> => {
      if (generation !== this.recordGeneration || this.backgroundSuspended || this.interruptionSuspended || !this.recordingRequested) return;

      const recorder = this.requireRecorder('start');

      if (this.pausedValue) await recorder.resume();
      else await recorder.start();

      this.pendingDurationMs = -1;
      this.startedAtMs = uptimeMilliseconds();
      this.recordingValue = true;
      this.pausedValue = false;
      this.startProgressTimers();
      this.delegate.recordingStateChanged();

      if (duration >= 0) {
        this.stopTimer = setTimeout((): void => {
          this.stopTimer = -1;
          this.backgroundSuspended = false;
          this.interruptionSuspended = false;
          this.recordingRequested = false;
          this.recordGeneration += 1;

          this.enqueue(async (): Promise<void> => this.stopInternal(null)).catch((error: Object): void => {
            console.error(`Expo Audio timed stop recorder failed for ${this.id}: ${cleanError(error)}`);
          });
        }, duration);
      }
    });
  }

  pause(): void {
    this.delegate.ensureRecordingPermission();
    this.schedule('pause recorder', async (): Promise<void> => {
      this.backgroundSuspended = false;
      this.interruptionSuspended = false;
      this.recordingRequested = false;
      this.recordGeneration += 1;
      this.pendingDurationMs = -1;
      this.clearDelayedStartTimer();
      await this.pauseNativeRecorder();
    });
  }

  suspendForBackground(): void {
    if (this.destroyed || this.backgroundSuspended) return;
    if (!this.recordingRequested && !this.recordingValue) return;

    this.backgroundSuspended = true;

    this.pauseForSuspension();
  }

  resumeFromBackground(): void {
    if (!this.backgroundSuspended) return;

    this.backgroundSuspended = false;

    if (!this.recordingRequested || !this.preparedValue) return;
    if (this.delayedStartTimer >= 0 && this.delayedStartDeadlineMs > uptimeMilliseconds()) return;

    this.clearDelayedStartTimer();
    this.scheduleRecordingStart(this.recordGeneration);
  }

  cancelBackgroundSuspension(): void {
    if (!this.backgroundSuspended) return;

    this.backgroundSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;

    this.clearDelayedStartTimer();
  }

  suspendForInterruption(): void {
    if (this.destroyed || this.interruptionSuspended) return;
    if (!this.recordingRequested && !this.recordingValue) return;

    this.interruptionSuspended = true;

    this.pauseForSuspension();
  }

  resumeFromInterruption(): void {
    if (!this.interruptionSuspended) return;

    this.interruptionSuspended = false;

    if (!this.recordingRequested || !this.preparedValue || this.backgroundSuspended) return;
    if (this.delayedStartTimer >= 0 && this.delayedStartDeadlineMs > uptimeMilliseconds()) return;

    this.clearDelayedStartTimer();
    this.scheduleRecordingStart(this.recordGeneration);
  }

  cancelInterruptionSuspension(): void {
    if (!this.interruptionSuspended) return;

    this.interruptionSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;

    this.clearDelayedStartTimer();
  }

  private pauseForSuspension(): void {
    this.schedule('pause recorder', async (): Promise<void> => this.pauseNativeRecorder());
  }

  private async pauseNativeRecorder(): Promise<void> {
    if (!this.recordingValue) return;
    const recorder = this.requireRecorder('pause');
    await recorder.pause();
    this.elapsedBeforeStartMs = this.durationMillis;
    this.recordingValue = false;
    this.pausedValue = true;
    this.stopProgressTimers();
    this.delegate.recordingStateChanged();
  }

  private async stopInternal(error: string | null): Promise<void> {
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;

    this.clearTimers();

    const recorder = this.recorder;
    if (recorder === undefined) return;

    if (this.recordingValue) this.elapsedBeforeStartMs = this.durationMillis;

    let failure = error;
    try {
      if (recorder.state === 'started' || recorder.state === 'paused') await recorder.stop();
    } catch (cause) {
      failure = cleanError(cause as Object);
    }

    this.recordingValue = false;
    this.pausedValue = false;
    this.preparedValue = false;

    await this.releaseRecorder();

    this.emitResult(failure);
    this.delegate.recordingStateChanged();

    if (failure !== null) throw new ExpoAudioError('ERR_AUDIO_RECORDING_STOP', failure);
  }

  private async releaseRecorder(): Promise<void> {
    const recorder = this.recorder;
    this.recorder = undefined;

    if (recorder !== undefined && recorder.state !== 'released') {
      try {
        await recorder.release();
      } catch (_) {}
    }

    const file = this.outputFile;
    this.outputFile = undefined;

    if (file !== undefined) {
      try {
        fs.closeSync(file.fd);
      } catch (_) {}
    }

    this.preparedValue = false;
    this.recordingValue = false;
    this.pausedValue = false;
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;
    this.elapsedBeforeStartMs = 0;
    this.startedAtMs = 0;
    this.delegate.recordingStateChanged();
  }

  getAvailableInputs(): RecordingInputRecord[] {
    this.requireRecorder('list inputs');

    const manager = audio.getAudioManager().getRoutingManager();
    const devices = manager.getDevicesSync(audio.DeviceFlag.INPUT_DEVICES_FLAG);

    return devices.map((device: audio.AudioDeviceDescriptor): RecordingInputRecord => new RecordingInputRecord(device));
  }

  async getCurrentInput(): Promise<RecordingInputRecord> {
    const input = await this.requireRecorder('get current input').getCurrentAudioCapturerInfo();

    if (input.deviceDescriptors.length === 0) {
      throw new ExpoAudioError('ERR_AUDIO_INPUT_UNAVAILABLE', 'No recording input is currently selected.');
    }

    return new RecordingInputRecord(input.deviceDescriptors[0]);
  }

  setInput(uid: string): void {
    if (uid.length === 0) throw new ExpoAudioError('ERR_AUDIO_INVALID_INPUT', 'The recording input identifier is empty.');

    this.requireRecorder('select input');

    if (!deviceInfo.apiAvailable(21)) {
      throw new ExpoAudioError(
        'ERR_AUDIO_INPUT_SELECTION_UNAVAILABLE',
        `Selecting a recording input requires HarmonyOS API ${INPUT_SELECTION_API} or newer.`,
      );
    }

    const manager = audio.getAudioManager();
    const devices = manager.getRoutingManager().getDevicesSync(audio.DeviceFlag.INPUT_DEVICES_FLAG);
    const input = devices.find((device: audio.AudioDeviceDescriptor): boolean => String(device.id) === uid);

    if (input === undefined) {
      throw new ExpoAudioError('ERR_AUDIO_INPUT_NOT_FOUND', `Recording input '${uid}' is unavailable.`);
    }

    this.enqueue(async (): Promise<void> => {
      await manager.getSessionManager().selectMediaInputDevice(input);
    }).catch((error: Object): void => {
      const message = `Failed to select recording input '${uid}': ${cleanError(error)}`;

      console.error(`Expo Audio ${message}`);
      this.emitOperationError(message);
    });
  }

  private requireRecorder(operation: string): media.AVRecorder {
    if (this.destroyed) throw new ExpoAudioError('ERR_AUDIO_RECORDER_RELEASED', `Cannot ${operation}; the recorder was released.`);

    if (!this.preparedValue || this.recorder === undefined) {
      throw new ExpoAudioError('ERR_AUDIO_RECORDER_NOT_PREPARED', `Cannot ${operation}; the recorder is not prepared.`);
    }

    return this.recorder;
  }

  private handleStateChange(state: media.AVRecorderState): void {
    if (state === 'stopped' && this.preparedValue) {
      this.backgroundSuspended = false;
      this.interruptionSuspended = false;
      this.recordingRequested = false;
      this.recordGeneration += 1;
      this.pendingDurationMs = -1;

      this.enqueue(async (): Promise<void> => this.stopInternal(null)).catch((error: Object): void => {
        console.error(`Expo Audio finalize stopped recorder failed for ${this.id}: ${cleanError(error)}`);
      });
    }

    if (state === 'error') this.onScheduledError('recorder state', new Error('HarmonyOS AVRecorder entered the error state.'));
  }

  private startProgressTimers(): void {
    this.stopProgressTimers();

    if (this.options.isMeteringEnabled === true) {
      this.meteringTimer = setInterval((): void => this.updateMetering(), METERING_INTERVAL_MS);
    }
  }

  private updateMetering(): void {
    const recorder = this.recorder;
    if (recorder === undefined || !this.recordingValue) return;

    const generation = this.recordGeneration;

    recorder
      .getAudioCapturerMaxAmplitude()
      .then((amplitude: number): void => {
        if (this.recorder !== recorder || this.recordGeneration !== generation || !this.recordingValue) return;

        if (amplitude <= 0) this.meteringValue = SILENCE_LEVEL_DB;
        else {
          const ratio = Math.min(amplitude, PCM_16_BIT_MAX_AMPLITUDE) / PCM_16_BIT_MAX_AMPLITUDE;

          this.meteringValue = Math.max(SILENCE_LEVEL_DB, 20 * Math.log10(ratio));
        }
      })
      .catch((): void => {});
  }

  private emitResult(error: string | null): void {
    if (!this.observed || this.destroyed) return;

    this.dispatcher.emit(RECORDING_STATUS_EVENT, new RecordingStatusRecord(this.id, error, error === null ? this.uri : null));
  }

  private emitOperationError(error: string): void {
    if (!this.observed || this.destroyed) return;

    this.dispatcher.emit(RECORDING_STATUS_EVENT, new RecordingStatusRecord(this.id, error, null, false));
  }

  private clearStartAndStopTimers(): void {
    this.clearDelayedStartTimer();

    if (this.stopTimer >= 0) clearTimeout(this.stopTimer);
    this.stopTimer = -1;
  }

  private clearDelayedStartTimer(): void {
    if (this.delayedStartTimer >= 0) clearTimeout(this.delayedStartTimer);

    this.delayedStartTimer = -1;
    this.delayedStartDeadlineMs = 0;
  }

  private stopProgressTimers(): void {
    if (this.meteringTimer >= 0) clearInterval(this.meteringTimer);

    this.meteringTimer = -1;
  }

  private clearTimers(): void {
    this.clearStartAndStopTimers();
    this.stopProgressTimers();
  }
}

class ExpoAudioRuntime implements PlaybackDelegate, RecorderDelegate {
  readonly context: ExpoModuleContext;
  private readonly players: Map<number, AudioPlayerController> = new Map();
  private readonly recorders: Map<number, AudioRecorderController> = new Map();
  private readonly playlists: Map<number, PlaylistController> = new Map();
  private readonly preloaded: Map<string, PreloadEntry> = new Map();
  private readonly sessionManager: audio.AudioSessionManager;
  private active: boolean = true;
  private inBackground: boolean = false;
  private focusInterrupted: boolean = false;
  private mode: AudioModeInput = {};
  private interruptionMode: InterruptionMode = 'mixWithOthers';
  private audioSessionActivated: boolean = false;
  private audioSessionTransition?: Promise<void>;
  private deactivatingAudioSession: boolean = false;
  private lockScreenPlayer?: AudioPlayerController;
  private lockScreenOptions?: LockScreenOptionsInput;
  private lockScreenSession?: avSession.AVSession;
  private sessionController?: PlaybackController;
  private mediaSessionTail: Promise<void> = Promise.resolve();
  private lockScreenGeneration: number = 0;
  private backgroundModes: string[] = [];
  private backgroundTaskTail: Promise<void> = Promise.resolve();
  private lifecycleTail: Promise<void> = Promise.resolve();
  private nextObjectId: number = 1;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    this.context = context;
    this.sessionManager = audio.getAudioManager().getSessionManager();

    this.sessionManager.on('audioSessionDeactivated', (event: audio.AudioSessionDeactivatedEvent): void => {
      this.audioSessionActivated = false;

      if (!this.deactivatingAudioSession) {
        if (deviceInfo.apiAvailable(20) && this.focusInterrupted && event.reason === audio.AudioSessionDeactivatedReason.DEACTIVATED_LOWER_PRIORITY) {
          return;
        }

        this.focusInterrupted = false;
        this.pauseAllPlayback();
      }
    });

    if (deviceInfo.apiAvailable(20)) {
      this.sessionManager.on('audioSessionStateChanged', (event: audio.AudioSessionStateChangedEvent): void =>
        this.handleAudioSessionStateChanged(event),
      );
    }
  }

  get cacheDir(): string {
    return this.context.uiAbilityContext.cacheDir;
  }

  playbackUsage(): audio.StreamUsage {
    return this.mode.shouldRouteThroughEarpiece === true ? audio.StreamUsage.STREAM_USAGE_VOICE_MESSAGE : audio.StreamUsage.STREAM_USAGE_MUSIC;
  }

  async takePreloaded(source: AudioSource): Promise<PreparedPlayer | undefined> {
    const key = sourceKey(source);
    if (key === null) return undefined;

    const entry = this.preloaded.get(key);
    if (entry === undefined) return undefined;

    const prepared = this.createPreloadedPlayer(entry.source, entry.preferredBufferDuration);
    const replacement = new PreloadEntry(entry.source, entry.preferredBufferDuration, prepared);

    this.preloaded.set(key, replacement);
    prepared.catch((): void => {
      if (this.preloaded.get(key) === replacement) this.preloaded.delete(key);
    });

    return await entry.prepared;
  }

  async beforePlay(): Promise<boolean> {
    if (!this.active || this.destroyed) return false;
    if (this.audioSessionActivated) return true;

    while (this.audioSessionTransition !== undefined) {
      const pending = this.audioSessionTransition;

      try {
        await pending;
      } catch (_) {}

      if (!this.active || this.destroyed) return false;
      if (this.audioSessionActivated) return true;
    }

    const strategy: audio.AudioSessionStrategy = {
      concurrencyMode: this.concurrencyMode(),
    };
    const activation = this.sessionManager.activateAudioSession(strategy);

    this.audioSessionTransition = activation;

    try {
      await activation;
      this.audioSessionActivated = true;

      return this.active && !this.destroyed;
    } finally {
      if (this.audioSessionTransition === activation) this.audioSessionTransition = undefined;
    }
  }

  playbackStateChanged(controller: PlaybackController): void {
    if (this.sessionController === controller) this.updateMediaPlaybackState(controller);
    if (this.inBackground) this.scheduleBackgroundTaskSync();

    if (this.hasActivePlayback()) return;
    if (this.hasSessionRetainer()) return;

    this.deactivateAudioSession();
  }

  lockScreenStateChanged(controller: AudioPlayerController): void {
    if (this.lockScreenPlayer !== controller) return;
    this.updateMediaPlaybackState(controller);
  }

  recordingStateChanged(): void {
    if (this.inBackground) this.scheduleBackgroundTaskSync();
  }

  setLockScreenPlayer(controller: AudioPlayerController, active: boolean, metadata?: AudioMetadataInput, options?: LockScreenOptionsInput): void {
    if (!active) {
      if (this.lockScreenPlayer === controller) {
        this.lockScreenPlayer = undefined;
        this.lockScreenOptions = undefined;
        this.lockScreenGeneration += 1;

        if (this.inBackground) this.scheduleBackgroundTaskSync();
        else this.clearMediaSession();
      }

      return;
    }

    this.lockScreenPlayer = controller;
    this.lockScreenOptions = options;
    const generation = ++this.lockScreenGeneration;

    this.ensureMediaSession(controller, options)
      .then(async (session: avSession.AVSession): Promise<void> => {
        if (generation !== this.lockScreenGeneration || this.lockScreenPlayer !== controller) return;

        const details: avSession.AVMetadata = { assetId: controller.id };

        if (metadata?.title !== undefined) details.title = metadata.title;
        if (metadata?.artist !== undefined) details.artist = metadata.artist;
        if (metadata?.albumTitle !== undefined) details.album = metadata.albumTitle;
        if (metadata?.artworkUrl !== undefined) details.mediaImage = metadata.artworkUrl;
        if (controller.durationSeconds > 0) details.duration = Math.round(controller.durationSeconds * 1000);

        await session.setAVMetadata(details);
        await session.activate();

        this.updateMediaPlaybackState(controller);
      })
      .catch((error: Object): void => {
        console.error(`Expo Audio lock-screen setup failed: ${cleanError(error)}`);
      });
  }

  ensureRecordingPermission(): void {
    if (!this.getRecordingPermission().granted) {
      throw new ExpoAudioError('ERR_AUDIO_RECORDING_PERMISSION', 'Microphone permission has not been granted.');
    }
  }

  getPreloadedSources(): string[] {
    return Array.from(this.preloaded.keys());
  }

  async background(): Promise<void> {
    await this.queueLifecycle(async (): Promise<void> => this.onBackground());
  }

  async foreground(): Promise<void> {
    await this.queueLifecycle(async (): Promise<void> => this.onForeground());
  }

  async prepareForReload(): Promise<void> {
    await this.queueLifecycle(async (): Promise<void> => this.destroy());
  }

  async destroy(): Promise<void> {
    if (this.destroyed) return;

    this.destroyed = true;

    const players = Array.from(this.players.values());
    const recorders = Array.from(this.recorders.values());
    const playlists = Array.from(this.playlists.values());

    players.forEach((controller: AudioPlayerController): void => controller.destroy());
    recorders.forEach((controller: AudioRecorderController): void => controller.destroy());
    playlists.forEach((controller: PlaylistController): void => controller.destroy());
    this.players.clear();
    this.recorders.clear();
    this.playlists.clear();

    for (let index = 0; index < players.length; index += 1) await players[index].waitForIdle();
    for (let index = 0; index < recorders.length; index += 1) await recorders[index].waitForIdle();
    for (let index = 0; index < playlists.length; index += 1) await playlists[index].waitForIdle();

    await this.clearAllPreloaded();
    await this.stopBackgroundTask();
    this.lockScreenPlayer = undefined;
    this.clearMediaSession();
    await this.mediaSessionTail.catch((): void => {});
    await this.deactivateAudioSession();

    try {
      this.sessionManager.off('audioSessionDeactivated');
    } catch (_) {}

    if (deviceInfo.apiAvailable(20)) {
      try {
        this.sessionManager.off('audioSessionStateChanged');
      } catch (_) {}
    }
  }

  private async queueLifecycle(operation: () => Promise<void>): Promise<void> {
    const run = this.lifecycleTail.catch((): void => {}).then(operation);

    this.lifecycleTail = run.catch((): void => {});

    await run;
  }

  createPlayer(
    sink: AudioObjectEventSink,
    source: AudioSource | null,
    updateInterval: number,
    keepsAudioSessionActive: boolean,
    preferredBufferDuration: number,
  ): AudioPlayerController {
    if (this.destroyed) throw new ExpoAudioError('ERR_AUDIO_MODULE_DESTROYED', 'Expo Audio has already been destroyed.');
    const objectId: number = this.allocateObjectId();
    const controller = new AudioPlayerController(objectId, source, updateInterval, keepsAudioSessionActive, preferredBufferDuration, sink, this);
    this.players.set(objectId, controller);
    return controller;
  }

  createRecorder(sink: AudioObjectEventSink, options: RecordingOptionsInput): AudioRecorderController {
    if (this.destroyed) throw new ExpoAudioError('ERR_AUDIO_MODULE_DESTROYED', 'Expo Audio has already been destroyed.');
    const objectId: number = this.allocateObjectId();
    const controller = new AudioRecorderController(objectId, options, sink, this);
    this.recorders.set(objectId, controller);
    return controller;
  }

  createPlaylist(sink: AudioObjectEventSink, sources: AudioSource[], updateInterval: number, loopMode: PlaylistLoopMode): PlaylistController {
    if (this.destroyed) throw new ExpoAudioError('ERR_AUDIO_MODULE_DESTROYED', 'Expo Audio has already been destroyed.');
    const objectId: number = this.allocateObjectId();
    const controller = new PlaylistController(objectId, sources, updateInterval, loopMode, sink, this);
    this.playlists.set(objectId, controller);
    return controller;
  }

  releasePlayer(player: AudioPlayerController): void {
    if (this.players.get(player.objectId) !== player) return;
    if (this.lockScreenPlayer === player) this.lockScreenPlayer = undefined;
    if (this.sessionController === player) this.clearMediaSession();
    player.destroy();
    this.players.delete(player.objectId);
    this.reconcileReleasedPlaybackObject();
  }

  releaseRecorder(recorder: AudioRecorderController): void {
    if (this.recorders.get(recorder.objectId) !== recorder) return;
    recorder.destroy();
    this.recorders.delete(recorder.objectId);
  }

  releasePlaylist(playlist: PlaylistController): void {
    if (this.playlists.get(playlist.objectId) !== playlist) return;
    if (this.sessionController === playlist) this.clearMediaSession();
    playlist.destroy();
    this.playlists.delete(playlist.objectId);
    this.reconcileReleasedPlaybackObject();
  }

  private reconcileReleasedPlaybackObject(): void {
    if (this.inBackground) this.scheduleBackgroundTaskSync();
    if (!this.hasActivePlayback() && !this.hasSessionRetainer()) this.deactivateAudioSession();
  }

  private allocateObjectId(): number {
    const objectId: number = this.nextObjectId;
    this.nextObjectId += 1;
    return objectId;
  }

  async setAudioActive(active: boolean): Promise<void> {
    this.active = active;

    if (active) return;

    this.pauseAllPlayback();

    await this.deactivateAudioSession();
  }

  async setAudioMode(input: AudioModeInput): Promise<void> {
    const next: AudioModeInput = {
      shouldPlayInBackground: input.shouldPlayInBackground ?? this.mode.shouldPlayInBackground,
      shouldRouteThroughEarpiece: input.shouldRouteThroughEarpiece ?? this.mode.shouldRouteThroughEarpiece,
      allowsBackgroundRecording: input.allowsBackgroundRecording ?? this.mode.allowsBackgroundRecording,
      interruptionMode: input.interruptionMode ?? this.mode.interruptionMode,
    };
    const nextInterruptionMode: InterruptionMode = normalizeInterruptionMode(next.interruptionMode ?? 'mixWithOthers');
    const routeChanged: boolean = next.shouldRouteThroughEarpiece !== this.mode.shouldRouteThroughEarpiece;

    if (deviceInfo.apiAvailable(20)) {
      const earpiece = next.shouldRouteThroughEarpiece === true;

      this.sessionManager.setAudioSessionScene(
        earpiece ? audio.AudioSessionScene.AUDIO_SESSION_SCENE_VOICE_COMMUNICATION : audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA,
      );

      await this.sessionManager.setDefaultOutputDevice(earpiece ? audio.DeviceType.EARPIECE : audio.DeviceType.DEFAULT);
    } else if (next.shouldRouteThroughEarpiece === true) {
      throw new ExpoAudioError('ERR_AUDIO_EARPIECE_ROUTING_UNSUPPORTED', 'Routing playback through the earpiece requires HarmonyOS API 20 or newer.');
    }

    while (this.audioSessionTransition !== undefined) {
      const pending = this.audioSessionTransition;

      try {
        await pending;
      } catch (_) {}
    }

    const reactivate = this.audioSessionActivated && this.hasActivePlayback();

    if (this.audioSessionActivated) {
      await this.deactivateAudioSession();
    }

    this.mode = next;
    this.interruptionMode = nextInterruptionMode;

    if (routeChanged) {
      await this.clearAllPreloaded();
      this.players.forEach((player: AudioPlayerController): void => player.refreshAudioRendererUsage());
      this.playlists.forEach((playlist: PlaylistController): void => playlist.refreshAudioRendererUsage());
    }

    if (reactivate) await this.beforePlay();

    if (this.inBackground) await this.queueBackgroundTaskSync();
  }

  private concurrencyMode(): audio.AudioConcurrencyMode {
    if (this.interruptionMode === 'doNotMix') return audio.AudioConcurrencyMode.CONCURRENCY_PAUSE_OTHERS;
    if (this.interruptionMode === 'duckOthers') return audio.AudioConcurrencyMode.CONCURRENCY_DUCK_OTHERS;
    return audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS;
  }

  private hasActivePlayback(): boolean {
    return (
      Array.from(this.players.values()).some((player: AudioPlayerController): boolean => player.playing) ||
      Array.from(this.playlists.values()).some((playlist: PlaylistController): boolean => playlist.playing)
    );
  }

  private hasSessionRetainer(): boolean {
    return Array.from(this.players.values()).some((player: AudioPlayerController): boolean => player.keepsAudioSessionActive);
  }

  private pauseAllPlayback(): void {
    this.players.forEach((player: AudioPlayerController): void => player.pause());
    this.playlists.forEach((playlist: PlaylistController): void => playlist.pause());
  }

  private handleAudioSessionStateChanged(event: audio.AudioSessionStateChangedEvent): void {
    if (this.destroyed || this.deactivatingAudioSession) return;

    const hint = event.stateChangeHint;

    if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE) {
      this.focusInterrupted = true;

      this.players.forEach((player: AudioPlayerController): void => player.suspendForInterruption());
      this.playlists.forEach((playlist: PlaylistController): void => playlist.suspendForInterruption());
      this.recorders.forEach((recorder: AudioRecorderController): void => recorder.suspendForInterruption());

      return;
    }

    if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_DUCK) {
      this.focusInterrupted = true;

      this.players.forEach((player: AudioPlayerController): void => player.setDucked(true));
      this.playlists.forEach((playlist: PlaylistController): void => playlist.setDucked(true));

      return;
    }

    if (
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME ||
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_UNDUCK
    ) {
      this.focusInterrupted = false;

      this.players.forEach((player: AudioPlayerController): void => player.setDucked(false));
      this.playlists.forEach((playlist: PlaylistController): void => playlist.setDucked(false));

      if (this.active && (!this.inBackground || this.mode.shouldPlayInBackground === true)) {
        this.resumeInterruptedPlayback();
      }
      if (this.active && (!this.inBackground || this.mode.allowsBackgroundRecording === true)) {
        this.resumeInterruptedRecorders();
      }

      return;
    }

    if (
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP ||
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP
    ) {
      this.focusInterrupted = false;
      this.audioSessionActivated = false;

      this.players.forEach((player: AudioPlayerController): void => player.setDucked(false));
      this.playlists.forEach((playlist: PlaylistController): void => playlist.setDucked(false));
      this.recorders.forEach((recorder: AudioRecorderController): void => {
        recorder.suspendForInterruption();
        recorder.cancelInterruptionSuspension();
      });
      this.pauseAllPlayback();
    }
  }

  private resumeInterruptedPlayback(): void {
    this.players.forEach((player: AudioPlayerController): void => player.resumeFromInterruption());
    this.playlists.forEach((playlist: PlaylistController): void => playlist.resumeFromInterruption());
  }

  private resumeInterruptedRecorders(): void {
    this.recorders.forEach((recorder: AudioRecorderController): void => recorder.resumeFromInterruption());
  }

  private async deactivateAudioSession(): Promise<void> {
    while (this.audioSessionTransition !== undefined) {
      const pending = this.audioSessionTransition;

      try {
        await pending;
      } catch (_) {}
    }

    if (!this.audioSessionActivated) return;

    this.audioSessionActivated = false;

    const transition = this.performAudioSessionDeactivation();
    this.audioSessionTransition = transition;

    try {
      await transition;
    } catch (_) {
    } finally {
      if (this.audioSessionTransition === transition) this.audioSessionTransition = undefined;
    }
  }

  private async performAudioSessionDeactivation(): Promise<void> {
    this.deactivatingAudioSession = true;
    try {
      await this.sessionManager.deactivateAudioSession();
    } finally {
      this.deactivatingAudioSession = false;
    }
  }

  async preload(source: AudioSource | null, preferredBufferDuration: number): Promise<void> {
    const key = sourceKey(source);

    if (source === null || key === null) return;

    const entry = this.preloaded.get(key);

    if (entry !== undefined) {
      await entry.prepared;

      return;
    }

    const duration = Math.max(0, preferredBufferDuration);
    const load = this.createPreloadedPlayer(source, duration);
    const next = new PreloadEntry(source, duration, load);

    this.preloaded.set(key, next);

    try {
      await load;
    } catch (error) {
      if (this.preloaded.get(key) === next) this.preloaded.delete(key);

      throw new ExpoAudioError('ERR_AUDIO_PRELOAD', cleanError(error as Object));
    }
  }

  private async createPreloadedPlayer(source: AudioSource, preferredBufferDuration: number): Promise<PreparedPlayer> {
    const player = await media.createAVPlayer();
    let file: SourceFile | undefined;

    try {
      file = await assignSource(player, source, this.cacheDir, this.context);
      await waitForSourceInitialization(player);

      if (preferredBufferDuration > 0) {
        await player.setPlaybackStrategy({ preferredBufferDuration });
      }

      player.audioRendererInfo = {
        usage: this.playbackUsage(),
        rendererFlags: 0,
      };

      await player.prepare();

      return new PreparedPlayer(player, file);
    } catch (error) {
      try {
        await player.release();
      } catch (_) {}

      closeSourceFile(file);

      throw new ExpoAudioError('ERR_AUDIO_PRELOAD', cleanError(error as Object));
    }
  }

  async clearPreloaded(source: AudioSource | null): Promise<void> {
    const key = sourceKey(source);
    if (key === null) return;

    const entry = this.preloaded.get(key);
    if (entry === undefined) return;

    this.preloaded.delete(key);

    const prepared = await entry.prepared;

    try {
      if (prepared.player.state !== 'released') await prepared.player.release();
    } finally {
      closeSourceFile(prepared.file);
    }
  }

  async clearAllPreloaded(): Promise<void> {
    const entries = Array.from(this.preloaded.values());

    this.preloaded.clear();

    for (let index = 0; index < entries.length; index += 1) {
      try {
        const prepared = await entries[index].prepared;
        try {
          if (prepared.player.state !== 'released') await prepared.player.release();
        } finally {
          closeSourceFile(prepared.file);
        }
      } catch (_) {}
    }
  }

  getRecordingPermission(): PermissionRecord {
    const manager = abilityAccessCtrl.createAtManager();

    try {
      const status = manager.getSelfPermissionStatus(MICROPHONE_PERMISSION);

      if (status === abilityAccessCtrl.PermissionStatus.GRANTED) return new PermissionRecord('granted', true);
      if (status === abilityAccessCtrl.PermissionStatus.NOT_DETERMINED) return new PermissionRecord('undetermined', true);
      return new PermissionRecord('denied', false);
    } catch (_) {
      const token = this.context.uiAbilityContext.applicationInfo.accessTokenId;
      const granted = manager.checkAccessTokenSync(token, MICROPHONE_PERMISSION) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;

      return new PermissionRecord(granted ? 'granted' : 'denied', true);
    }
  }

  async requestRecordingPermission(): Promise<PermissionRecord> {
    try {
      await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context.uiAbilityContext, [MICROPHONE_PERMISSION]);

      return this.getRecordingPermission();
    } catch (_) {
      throw new ExpoAudioError('ERR_AUDIO_PERMISSION_REQUEST', 'The microphone permission request could not be completed.');
    }
  }

  async requestNotificationPermission(): Promise<PermissionRecord> {
    if (notificationManager.isNotificationEnabledSync()) return new PermissionRecord('granted', true);

    try {
      await notificationManager.requestEnableNotification(this.context.uiAbilityContext);
    } catch (error) {
      const cause = error as BusinessError;

      if (cause.code === 1600004) return new PermissionRecord('denied', false);

      throw new ExpoAudioError('ERR_AUDIO_NOTIFICATION_PERMISSION', cleanError(cause));
    }

    return notificationManager.isNotificationEnabledSync() ? new PermissionRecord('granted', true) : new PermissionRecord('denied', false);
  }

  private desiredBackgroundModes(): string[] {
    const modes: string[] = [];

    if (this.mode.shouldPlayInBackground === true && this.hasActivePlayback()) modes.push(BACKGROUND_PLAYBACK_MODE);
    if (
      this.mode.allowsBackgroundRecording === true &&
      Array.from(this.recorders.values()).some((recorder: AudioRecorderController): boolean => recorder.recording)
    ) {
      modes.push(BACKGROUND_RECORDING_MODE);
    }

    return modes;
  }

  private sameBackgroundModes(modes: string[]): boolean {
    return (
      modes.length === this.backgroundModes.length && modes.every((mode: string, index: number): boolean => mode === this.backgroundModes[index])
    );
  }

  private scheduleBackgroundTaskSync(): void {
    this.queueBackgroundTaskSync().catch((error: Object): void => {
      console.error(`Expo Audio background task update failed: ${cleanError(error)}`);
    });
  }

  private async queueBackgroundTaskSync(): Promise<void> {
    const run = this.backgroundTaskTail.catch((): void => {}).then(async (): Promise<void> => this.syncBackgroundTask());

    this.backgroundTaskTail = run.catch((): void => {});

    await run;
  }

  private async syncBackgroundTask(): Promise<void> {
    const modes = this.inBackground && !this.destroyed ? this.desiredBackgroundModes() : [];

    if (modes.includes(BACKGROUND_PLAYBACK_MODE)) await this.ensureBackgroundMediaSession();
    if (this.sameBackgroundModes(modes)) return;

    if (modes.length === 0) {
      await this.stopBackgroundTaskNow();

      return;
    }

    if (this.backgroundModes.length > 0) {
      await backgroundTaskManager.updateBackgroundRunning(this.context.uiAbilityContext, modes);
      this.backgroundModes = modes;

      if (!modes.includes(BACKGROUND_PLAYBACK_MODE) && this.lockScreenPlayer === undefined) this.clearMediaSession();

      return;
    }

    const ability = this.context.uiAbilityContext.abilityInfo;
    const agent: WantAgent = await wantAgent.getWantAgent({
      wants: [{ bundleName: ability.bundleName, abilityName: ability.name }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    });

    await backgroundTaskManager.startBackgroundRunning(this.context.uiAbilityContext, modes, agent);
    this.backgroundModes = modes;
  }

  private async stopBackgroundTask(): Promise<void> {
    await this.backgroundTaskTail.catch((): void => {});
    await this.stopBackgroundTaskNow();
  }

  private async stopBackgroundTaskNow(): Promise<void> {
    if (this.backgroundModes.length === 0) return;

    await backgroundTaskManager.stopBackgroundRunning(this.context.uiAbilityContext);
    this.backgroundModes = [];

    if (this.lockScreenPlayer === undefined) this.clearMediaSession();
  }

  private activePlaybackController(): PlaybackController | undefined {
    if (this.lockScreenPlayer !== undefined && this.lockScreenPlayer.playing) return this.lockScreenPlayer;

    const player = Array.from(this.players.values()).find((entry: AudioPlayerController): boolean => entry.playing);
    if (player !== undefined) return player;

    return Array.from(this.playlists.values()).find((entry: PlaylistController): boolean => entry.playing);
  }

  private async ensureBackgroundMediaSession(): Promise<void> {
    const controller = this.activePlaybackController();
    if (controller === undefined) {
      throw new ExpoAudioError('ERR_AUDIO_BACKGROUND_PLAYBACK', 'No active player is available for the background media session.');
    }

    const session = await this.ensureMediaSession(controller, controller === this.lockScreenPlayer ? this.lockScreenOptions : undefined);
    if (controller !== this.lockScreenPlayer) {
      const metadata: avSession.AVMetadata = { assetId: controller.id };

      if (controller.durationSeconds > 0) metadata.duration = Math.round(controller.durationSeconds * 1000);

      await session.setAVMetadata(metadata);
    }
    await session.activate();

    this.updateMediaPlaybackState(controller);
  }

  private async onBackground(): Promise<void> {
    if (this.destroyed) return;

    this.inBackground = true;

    if (this.mode.shouldPlayInBackground !== true) {
      this.players.forEach((player: AudioPlayerController): void => player.suspendForBackground());
      this.playlists.forEach((playlist: PlaylistController): void => playlist.suspendForBackground());
    }

    if (this.mode.allowsBackgroundRecording !== true) {
      this.recorders.forEach((recorder: AudioRecorderController): void => recorder.suspendForBackground());
    }

    await this.queueBackgroundTaskSync();
  }

  private async onForeground(): Promise<void> {
    if (this.destroyed) return;

    this.inBackground = false;

    await this.stopBackgroundTask();

    if (this.lockScreenPlayer === undefined) this.clearMediaSession();

    if (!this.active) {
      this.players.forEach((player: AudioPlayerController): void => player.cancelSuspensions());
      this.playlists.forEach((playlist: PlaylistController): void => playlist.cancelSuspensions());
      this.recorders.forEach((recorder: AudioRecorderController): void => recorder.cancelBackgroundSuspension());

      return;
    }

    this.players.forEach((player: AudioPlayerController): void => player.resumeFromBackground());
    this.playlists.forEach((playlist: PlaylistController): void => playlist.resumeFromBackground());
    this.recorders.forEach((recorder: AudioRecorderController): void => recorder.resumeFromBackground());

    if (!this.focusInterrupted) this.resumeInterruptedPlayback();
    if (!this.focusInterrupted) this.resumeInterruptedRecorders();
  }

  private async ensureMediaSession(controller: PlaybackController, options?: LockScreenOptionsInput): Promise<avSession.AVSession> {
    const operation: Promise<avSession.AVSession> = this.mediaSessionTail
      .catch((): void => {})
      .then(async (): Promise<avSession.AVSession> => this.ensureMediaSessionNow(controller, options));
    this.mediaSessionTail = operation.then(
      (): void => {},
      (): void => {},
    );
    return await operation;
  }

  private async ensureMediaSessionNow(controller: PlaybackController, options?: LockScreenOptionsInput): Promise<avSession.AVSession> {
    let session = this.lockScreenSession;

    if (session === undefined) {
      session = await avSession.createAVSession(this.context.uiAbilityContext, AUDIO_SESSION_TAG, 'audio');
      this.lockScreenSession = session;
    }

    this.sessionController = controller;

    try {
      session.off('play');
    } catch (_) {}
    try {
      session.off('pause');
    } catch (_) {}
    try {
      session.off('seek');
    } catch (_) {}
    try {
      session.off('fastForward');
    } catch (_) {}
    try {
      session.off('rewind');
    } catch (_) {}

    session.on('play', (): void => controller.play());
    session.on('pause', (): void => controller.pause());
    session.on('seek', (time: number): void => {
      controller.seekTo(time / 1000).catch((): void => {});
    });

    if (options?.showSeekForward === true) {
      session.on('fastForward', (time?: number): void => {
        const offset = time ?? SEEK_STEP_MS;

        controller.seekTo(controller.currentTimeSeconds + offset / 1000).catch((): void => {});
      });
    }

    if (options?.showSeekBackward === true) {
      session.on('rewind', (time?: number): void => {
        const offset = time ?? SEEK_STEP_MS;

        controller.seekTo(Math.max(0, controller.currentTimeSeconds - offset / 1000)).catch((): void => {});
      });
    }

    return session;
  }

  private updateMediaPlaybackState(controller: PlaybackController): void {
    const session = this.lockScreenSession;

    if (session === undefined) return;

    const state: avSession.AVPlaybackState = {
      state: controller.playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      speed: controller.playbackRate,
      position: {
        elapsedTime: Math.round(controller.currentTimeSeconds * 1000),
        updateTime: Date.now(),
      },
      duration: Math.round(controller.durationSeconds * 1000),
      muted: controller.muted,
      volume: controller.volume,
    };

    session.setAVPlaybackState(state).catch((error: Object): void => {
      console.error(`Expo Audio lock-screen state update failed: ${cleanError(error)}`);
    });
  }

  private clearMediaSession(): void {
    this.lockScreenGeneration += 1;
    this.sessionController = undefined;
    const cleanup: Promise<void> = this.mediaSessionTail
      .catch((): void => {})
      .then(async (): Promise<void> => {
        const session: avSession.AVSession | undefined = this.lockScreenSession;
        this.lockScreenSession = undefined;
        if (session === undefined) return;
        try {
          await session.deactivate();
        } catch (_) {}
        await session.destroy();
      });
    this.mediaSessionTail = cleanup.catch((error: Object): void => {
      console.error(`Expo Audio lock-screen teardown failed: ${cleanError(error)}`);
    });
  }
}

abstract class ExpoAudioSharedObject extends ExpoSharedObject implements AudioObjectEventSink {
  emit(eventName: string, payload: ESObject): void {
    this.sendEvent(eventName, payload);
  }
}

class ExpoAudioPlayer extends ExpoAudioSharedObject {
  readonly controller: AudioPlayerController;
  private readonly runtime: ExpoAudioRuntime;

  constructor(
    context: ExpoModuleContext,
    runtime: ExpoAudioRuntime,
    source: AudioSource | null,
    updateInterval: number,
    keepsAudioSessionActive: boolean,
    preferredBufferDuration: number,
  ) {
    super(context);
    this.runtime = runtime;
    this.controller = runtime.createPlayer(this, source, updateInterval, keepsAudioSessionActive, preferredBufferDuration);
  }

  override onStartListeningToEvent(eventName: string): void {
    this.controller.setObserving(eventName, true);
  }

  override onStopListeningToEvent(eventName: string): void {
    this.controller.setObserving(eventName, false);
  }

  override sharedObjectWillRelease(): void {
    this.runtime.releasePlayer(this.controller);
  }

  release(): void {
    this.runtime.releasePlayer(this.controller);
  }
}

class ExpoAudioRecorder extends ExpoAudioSharedObject {
  readonly controller: AudioRecorderController;
  private readonly runtime: ExpoAudioRuntime;

  constructor(context: ExpoModuleContext, runtime: ExpoAudioRuntime, options: RecordingOptionsInput) {
    super(context);
    this.runtime = runtime;
    this.controller = runtime.createRecorder(this, options);
  }

  override onStartListeningToEvent(eventName: string): void {
    this.controller.setObserving(eventName, true);
  }

  override onStopListeningToEvent(eventName: string): void {
    this.controller.setObserving(eventName, false);
  }

  override sharedObjectWillRelease(): void {
    this.runtime.releaseRecorder(this.controller);
  }
}

class ExpoAudioPlaylist extends ExpoAudioSharedObject {
  readonly controller: PlaylistController;
  private readonly runtime: ExpoAudioRuntime;

  constructor(context: ExpoModuleContext, runtime: ExpoAudioRuntime, sources: AudioSource[], updateInterval: number, loopMode: PlaylistLoopMode) {
    super(context);
    this.runtime = runtime;
    this.controller = runtime.createPlaylist(this, sources, updateInterval, loopMode);
  }

  override onStartListeningToEvent(eventName: string): void {
    this.controller.setObserving(eventName, true);
  }

  override onStopListeningToEvent(eventName: string): void {
    this.controller.setObserving(eventName, false);
  }

  override sharedObjectWillRelease(): void {
    this.runtime.releasePlaylist(this.controller);
  }

  release(): void {
    this.runtime.releasePlaylist(this.controller);
  }
}

function audioInputType<Value>(expectedType: string, decoder: (value: ESObject) => Value): ExpoValueType<Value> {
  return new ExpoValueType<Value>(
    expectedType,
    (value: ESObject, path: string): Value => {
      try {
        return decoder(value);
      } catch (error) {
        if (error instanceof ExpoModuleError) {
          throw new ExpoModuleError(error.code, `${path}: ${error.message}`, error, path);
        }
        throw new ExpoModuleError('ERR_INVALID_ARGUMENT_TYPE', `${path} expected ${expectedType}.`, error as Object, path);
      }
    },
    (value: Value): ESObject => value as ESObject,
  );
}

function readAudioMode(value: ESObject): AudioModeInput {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_MODE', 'The audio mode must be an object.');
  }
  const input = value as Record<string, ESObject>;
  const mode: AudioModeInput = {};
  if (typeof input.shouldPlayInBackground === 'boolean') mode.shouldPlayInBackground = input.shouldPlayInBackground;
  if (typeof input.shouldRouteThroughEarpiece === 'boolean') mode.shouldRouteThroughEarpiece = input.shouldRouteThroughEarpiece;
  if (typeof input.allowsBackgroundRecording === 'boolean') mode.allowsBackgroundRecording = input.allowsBackgroundRecording;
  if (typeof input.interruptionMode === 'string') mode.interruptionMode = input.interruptionMode;
  return mode;
}

const AUDIO_SOURCE_TYPE: ExpoValueType<AudioSource | null> = audioInputType<AudioSource | null>(
  'audio source',
  (value: ESObject): AudioSource | null => readSource(value),
);
const AUDIO_SOURCES_TYPE: ExpoValueType<AudioSource[]> = audioInputType<AudioSource[]>('array of audio sources', (value: ESObject): AudioSource[] =>
  readSources(value),
);
const AUDIO_MODE_TYPE: ExpoValueType<AudioModeInput> = audioInputType<AudioModeInput>(
  'audio mode',
  (value: ESObject): AudioModeInput => readAudioMode(value),
);
const RECORDING_OPTIONS_TYPE: ExpoValueType<RecordingOptionsInput> = audioInputType<RecordingOptionsInput>(
  'recording options',
  (value: ESObject): RecordingOptionsInput => readRecordingOptions(value),
);
const RECORDING_START_OPTIONS_TYPE: ExpoValueType<RecordingStartOptions> = audioInputType<RecordingStartOptions>(
  'recording start options',
  (value: ESObject): RecordingStartOptions => readRecordingStartOptions(value),
);
const AUDIO_METADATA_TYPE: ExpoValueType<AudioMetadataInput | undefined> = audioInputType<AudioMetadataInput | undefined>(
  'lock-screen metadata',
  (value: ESObject): AudioMetadataInput | undefined => readMetadata(value),
);
const LOCK_SCREEN_OPTIONS_TYPE: ExpoValueType<LockScreenOptionsInput | undefined> = audioInputType<LockScreenOptionsInput | undefined>(
  'lock-screen options',
  (value: ESObject): LockScreenOptionsInput | undefined => readLockScreenOptions(value),
);

export class ExpoAudioModule extends ExpoModule {
  private readonly runtime: ExpoAudioRuntime;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.runtime = new ExpoAudioRuntime(context);
  }

  override definition(): ExpoModuleDefinition {
    const playerClass = new ExpoSharedObjectClassDefinition<ExpoAudioPlayer>(PLAYER_CLASS_NAME)
      .construct(
        ExpoFunction.ownedTyped4(
          AUDIO_SOURCE_TYPE,
          ExpoValueTypes.number(),
          ExpoValueTypes.boolean(),
          ExpoValueTypes.number(),
          (
            context: ExpoModuleContext,
            source: AudioSource | null,
            updateInterval: number,
            keepsAudioSessionActive: boolean,
            preferredBufferDuration: number,
          ): ExpoAudioPlayer => new ExpoAudioPlayer(context, this.runtime, source, updateInterval, keepsAudioSessionActive, preferredBufferDuration),
        ),
      )
      .events([PLAYBACK_STATUS_EVENT, 'audioSampleUpdate'])
      .property('id', ExpoValueTypes.string(), (object: ExpoAudioPlayer): string => object.controller.id)
      .property('playing', ExpoValueTypes.boolean(), (object: ExpoAudioPlayer): boolean => object.controller.playing)
      .property(
        'muted',
        ExpoValueTypes.boolean(),
        (object: ExpoAudioPlayer): boolean => object.controller.muted,
        (object: ExpoAudioPlayer, value: boolean): void => object.controller.setMuted(value),
      )
      .property(
        'loop',
        ExpoValueTypes.boolean(),
        (object: ExpoAudioPlayer): boolean => object.controller.looping,
        (object: ExpoAudioPlayer, value: boolean): void => object.controller.setLooping(value),
      )
      .property('paused', ExpoValueTypes.boolean(), (object: ExpoAudioPlayer): boolean => !object.controller.playing)
      .property('isLoaded', ExpoValueTypes.boolean(), (object: ExpoAudioPlayer): boolean => object.controller.loaded)
      .property('isAudioSamplingSupported', ExpoValueTypes.boolean(), (_object: ExpoAudioPlayer): boolean => false)
      .property('isBuffering', ExpoValueTypes.boolean(), (object: ExpoAudioPlayer): boolean => object.controller.buffering)
      .property('currentTime', ExpoValueTypes.number(), (object: ExpoAudioPlayer): number => object.controller.currentTimeSeconds)
      .property('duration', ExpoValueTypes.number(), (object: ExpoAudioPlayer): number => object.controller.durationSeconds)
      .property(
        'volume',
        ExpoValueTypes.number(),
        (object: ExpoAudioPlayer): number => object.controller.volume,
        (object: ExpoAudioPlayer, value: number): void => object.controller.setVolume(value),
      )
      .property('playbackRate', ExpoValueTypes.number(), (object: ExpoAudioPlayer): number => object.controller.playbackRate)
      .property(
        'shouldCorrectPitch',
        ExpoValueTypes.boolean(),
        (object: ExpoAudioPlayer): boolean => object.controller.correctsPitch,
        (object: ExpoAudioPlayer, value: boolean): void => object.controller.setShouldCorrectPitch(value),
      )
      .property('currentStatus', (object: ExpoAudioPlayer): ESObject => object.controller.currentStatus)
      .syncFunction('play', (object: ExpoAudioPlayer): void => object.controller.play())
      .syncFunction('pause', (object: ExpoAudioPlayer): void => object.controller.pause())
      .syncFunction(
        'replace',
        ExpoFunction.ownedTyped1(AUDIO_SOURCE_TYPE, (object: ExpoAudioPlayer, source: AudioSource | null): void => object.controller.replace(source)),
      )
      .asyncFunction(
        'seekTo',
        ExpoFunction.ownedTyped3(
          ExpoValueTypes.number(),
          ExpoValueTypes.number().optional(),
          ExpoValueTypes.number().optional(),
          async (object: ExpoAudioPlayer, seconds: number, toleranceBefore?: number, toleranceAfter?: number): Promise<void> => {
            await object.controller.seekTo(seconds);
          },
        ),
      )
      .syncFunction(
        'setPlaybackRate',
        ExpoFunction.ownedTyped2(
          ExpoValueTypes.number(),
          ExpoValueTypes.string().optional(),
          (object: ExpoAudioPlayer, rate: number, pitchCorrectionQuality?: string): void => {
            object.controller.setPlaybackRate(rate);
          },
        ),
      )
      .syncFunction(
        'setAudioSamplingEnabled',
        ExpoFunction.ownedTyped1(ExpoValueTypes.boolean(), (object: ExpoAudioPlayer, enabled: boolean): void =>
          object.controller.setAudioSamplingEnabled(enabled),
        ),
      )
      .syncFunction(
        'setActiveForLockScreen',
        ExpoFunction.ownedTyped3(
          ExpoValueTypes.boolean(),
          AUDIO_METADATA_TYPE.optional(),
          LOCK_SCREEN_OPTIONS_TYPE.optional(),
          (object: ExpoAudioPlayer, active: boolean, metadata?: AudioMetadataInput, options?: LockScreenOptionsInput): void => {
            object.controller.setActiveForLockScreen(active, metadata, options);
          },
        ),
      )
      .syncFunction(
        'updateLockScreenMetadata',
        ExpoFunction.ownedTyped1(AUDIO_METADATA_TYPE, (object: ExpoAudioPlayer, metadata?: AudioMetadataInput): void => {
          object.controller.updateLockScreenMetadata(metadata);
        }),
      )
      .syncFunction('clearLockScreenControls', (object: ExpoAudioPlayer): void => {
        object.controller.clearLockScreenControls();
      })
      .syncFunction('remove', (object: ExpoAudioPlayer): void => object.release());

    const recorderClass = new ExpoSharedObjectClassDefinition<ExpoAudioRecorder>(RECORDER_CLASS_NAME)
      .construct(
        ExpoFunction.ownedTyped1(
          RECORDING_OPTIONS_TYPE,
          (context: ExpoModuleContext, options: RecordingOptionsInput): ExpoAudioRecorder => new ExpoAudioRecorder(context, this.runtime, options),
        ),
      )
      .events([RECORDING_STATUS_EVENT])
      .property('id', ExpoValueTypes.string(), (object: ExpoAudioRecorder): string => object.controller.id)
      .property('currentTime', ExpoValueTypes.number(), (object: ExpoAudioRecorder): number => object.controller.durationMillis / 1000)
      .property('isRecording', ExpoValueTypes.boolean(), (object: ExpoAudioRecorder): boolean => object.controller.recording)
      .property('uri', ExpoValueTypes.string().nullable(), (object: ExpoAudioRecorder): string | null => object.controller.uri)
      .syncFunction(
        'record',
        ExpoFunction.ownedTyped1(RECORDING_START_OPTIONS_TYPE.optional(), (object: ExpoAudioRecorder, options?: RecordingStartOptions): void => {
          object.controller.record(options ?? {});
        }),
      )
      .asyncFunction('stop', async (object: ExpoAudioRecorder): Promise<void> => {
        await object.controller.stop();
      })
      .syncFunction('pause', (object: ExpoAudioRecorder): void => {
        object.controller.pause();
      })
      .syncFunction('getAvailableInputs', (object: ExpoAudioRecorder): RecordingInputRecord[] => object.controller.getAvailableInputs())
      .asyncFunction('getCurrentInput', async (object: ExpoAudioRecorder): Promise<RecordingInputRecord> => await object.controller.getCurrentInput())
      .syncFunction(
        'setInput',
        ExpoFunction.ownedTyped1(ExpoValueTypes.string(), (object: ExpoAudioRecorder, uid: string): void => object.controller.setInput(uid)),
      )
      .syncFunction('getStatus', (object: ExpoAudioRecorder): RecorderStateRecord => object.controller.currentStatus)
      .syncFunction(
        'startRecordingAtTime',
        ExpoFunction.ownedTyped1(ExpoValueTypes.number(), (object: ExpoAudioRecorder, seconds: number): void =>
          object.controller.startRecordingAtTime(seconds),
        ),
      )
      .asyncFunction(
        'prepareToRecordAsync',
        ExpoFunction.ownedTyped1(
          RECORDING_OPTIONS_TYPE.optional(),
          async (object: ExpoAudioRecorder, options?: RecordingOptionsInput): Promise<void> => {
            await object.controller.prepareToRecord(options);
          },
        ),
      )
      .syncFunction(
        'recordForDuration',
        ExpoFunction.ownedTyped1(ExpoValueTypes.number(), (object: ExpoAudioRecorder, seconds: number): void =>
          object.controller.recordForDuration(seconds),
        ),
      );

    const playlistClass = new ExpoSharedObjectClassDefinition<ExpoAudioPlaylist>(PLAYLIST_CLASS_NAME)
      .construct(
        ExpoFunction.ownedTyped3(
          AUDIO_SOURCES_TYPE,
          ExpoValueTypes.number(),
          ExpoValueTypes.string(),
          (context: ExpoModuleContext, sources: AudioSource[], updateInterval: number, loopMode: string): ExpoAudioPlaylist =>
            new ExpoAudioPlaylist(context, this.runtime, sources, updateInterval, normalizeLoopMode(loopMode)),
        ),
      )
      .events([PLAYLIST_STATUS_EVENT, TRACK_CHANGED_EVENT])
      .property('id', ExpoValueTypes.string(), (object: ExpoAudioPlaylist): string => object.controller.id)
      .property('currentIndex', ExpoValueTypes.number(), (object: ExpoAudioPlaylist): number => object.controller.currentIndex)
      .property('trackCount', ExpoValueTypes.number(), (object: ExpoAudioPlaylist): number => object.controller.trackCount)
      .property('sources', (object: ExpoAudioPlaylist): AudioSourceInfoRecord[] => object.controller.sources)
      .property('playing', ExpoValueTypes.boolean(), (object: ExpoAudioPlaylist): boolean => object.controller.playing)
      .property(
        'muted',
        ExpoValueTypes.boolean(),
        (object: ExpoAudioPlaylist): boolean => object.controller.muted,
        (object: ExpoAudioPlaylist, value: boolean): void => object.controller.setMuted(value),
      )
      .property('isLoaded', ExpoValueTypes.boolean(), (object: ExpoAudioPlaylist): boolean => object.controller.loaded)
      .property('isBuffering', ExpoValueTypes.boolean(), (object: ExpoAudioPlaylist): boolean => object.controller.buffering)
      .property('currentTime', ExpoValueTypes.number(), (object: ExpoAudioPlaylist): number => object.controller.currentTimeSeconds)
      .property('duration', ExpoValueTypes.number(), (object: ExpoAudioPlaylist): number => object.controller.durationSeconds)
      .property(
        'volume',
        ExpoValueTypes.number(),
        (object: ExpoAudioPlaylist): number => object.controller.volume,
        (object: ExpoAudioPlaylist, value: number): void => object.controller.setVolume(value),
      )
      .property(
        'playbackRate',
        ExpoValueTypes.number(),
        (object: ExpoAudioPlaylist): number => object.controller.playbackRate,
        (object: ExpoAudioPlaylist, value: number): void => object.controller.setPlaybackRate(value),
      )
      .property(
        'loop',
        ExpoValueTypes.string(),
        (object: ExpoAudioPlaylist): string => object.controller.loopMode,
        (object: ExpoAudioPlaylist, value: string): void => object.controller.setLoopMode(value),
      )
      .property('currentStatus', (object: ExpoAudioPlaylist): ESObject => object.controller.currentStatus)
      .syncFunction('play', (object: ExpoAudioPlaylist): void => object.controller.play())
      .syncFunction('pause', (object: ExpoAudioPlaylist): void => object.controller.pause())
      .syncFunction('next', (object: ExpoAudioPlaylist): void => object.controller.next())
      .syncFunction('previous', (object: ExpoAudioPlaylist): void => object.controller.previous())
      .syncFunction(
        'skipTo',
        ExpoFunction.ownedTyped1(ExpoValueTypes.number(), (object: ExpoAudioPlaylist, index: number): void => object.controller.skipTo(index)),
      )
      .asyncFunction(
        'seekTo',
        ExpoFunction.ownedTyped1(ExpoValueTypes.number(), async (object: ExpoAudioPlaylist, seconds: number): Promise<void> => {
          await object.controller.seekTo(seconds);
        }),
      )
      .syncFunction(
        'add',
        ExpoFunction.ownedTyped1(AUDIO_SOURCE_TYPE, (object: ExpoAudioPlaylist, source: AudioSource | null): void => object.controller.add(source)),
      )
      .syncFunction(
        'insert',
        ExpoFunction.ownedTyped2(
          AUDIO_SOURCE_TYPE,
          ExpoValueTypes.number(),
          (object: ExpoAudioPlaylist, source: AudioSource | null, index: number): void => object.controller.insert(source, index),
        ),
      )
      .syncFunction(
        'remove',
        ExpoFunction.ownedTyped1(ExpoValueTypes.number(), (object: ExpoAudioPlaylist, index: number): void => object.controller.remove(index)),
      )
      .syncFunction('clear', (object: ExpoAudioPlaylist): void => object.controller.clear())
      .syncFunction('destroy', (object: ExpoAudioPlaylist): void => object.release());

    return new ExpoModuleDefinition()
      .name(MODULE_NAME)
      .sharedObjectClass(playerClass)
      .sharedObjectClass(recorderClass)
      .sharedObjectClass(playlistClass)
      .asyncFunction(
        'setIsAudioActiveAsync',
        ExpoFunction.typed1(ExpoValueTypes.boolean(), async (active: boolean): Promise<void> => await this.runtime.setAudioActive(active)),
      )
      .asyncFunction(
        'setAudioModeAsync',
        ExpoFunction.typed1(AUDIO_MODE_TYPE, async (mode: AudioModeInput): Promise<void> => await this.runtime.setAudioMode(mode)),
      )
      .asyncFunction('requestRecordingPermissionsAsync', async (): Promise<PermissionRecord> => await this.runtime.requestRecordingPermission())
      .asyncFunction('requestNotificationPermissionsAsync', async (): Promise<PermissionRecord> => await this.runtime.requestNotificationPermission())
      .asyncFunction('getRecordingPermissionsAsync', async (): Promise<PermissionRecord> => this.runtime.getRecordingPermission())
      .asyncFunction(
        'preload',
        ExpoFunction.typed2(
          AUDIO_SOURCE_TYPE,
          ExpoValueTypes.number(),
          async (source: AudioSource | null, preferredBufferDuration: number): Promise<void> =>
            await this.runtime.preload(source, preferredBufferDuration),
        ),
      )
      .asyncFunction(
        'clearPreloadedSource',
        ExpoFunction.typed1(AUDIO_SOURCE_TYPE, async (source: AudioSource | null): Promise<void> => await this.runtime.clearPreloaded(source)),
      )
      .asyncFunction('clearAllPreloadedSources', async (): Promise<void> => await this.runtime.clearAllPreloaded())
      .asyncFunction(
        'getPreloadedSources',
        ExpoFunction.typed0(async (): Promise<string[]> => this.runtime.getPreloadedSources()).returns(ExpoValueTypes.array(ExpoValueTypes.string())),
      )
      .onBackground((): void => {
        this.runtime.background().catch((error: Object): void => {
          console.error(`Expo Audio background transition failed: ${cleanError(error)}`);
        });
      })
      .onForeground((): void => {
        this.runtime.foreground().catch((error: Object): void => {
          console.error(`Expo Audio foreground transition failed: ${cleanError(error)}`);
        });
      })
      .onPrepareForReload(async (): Promise<void> => await this.runtime.prepareForReload())
      .onDestroy((): void => {
        this.runtime.destroy().catch((error: Object): void => {
          console.error(`Expo Audio destroy failed: ${cleanError(error)}`);
        });
      });
  }
}
