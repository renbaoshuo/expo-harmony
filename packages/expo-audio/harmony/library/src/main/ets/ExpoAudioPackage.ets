/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoAVSessionClient,
  ExpoAVSessionControls,
  ExpoAppLifecycleState,
  ExpoAudioSessionClient,
  ExpoFileAccessKey,
  fileUriFromPath,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoPermissionStatus,
  ExpoRawResourceFile,
  ExpoRecordShape,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoValueType,
  ExpoValueTypes,
  isRnohRawfileResourceUri,
  openRawResourceFile,
  rawResourcePathFromUri,
} from '@expo-harmony/expo-modules-core';
import { Permissions, wantAgent, WantAgent } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { audio } from '@kit.AudioKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { notificationManager } from '@kit.NotificationKit';
import deviceInfo from '@ohos.deviceInfo';
import fs from '@ohos.file.fs';
import { observeDefaultRingerMode } from './RingerModeObserver';
import {
  effectivePlaying,
  isDataAudioUri,
  isPackagedAudioUri,
  isRemoteAudioUri,
  isSupportedRecordingExtension,
  nextPlaylistIndex,
  previousPlaylistIndex,
  seekTargetMilliseconds,
} from './ExpoAudioSemantics';

const MODULE_NAME: string = 'ExpoAudio';
const PLAYER_CLASS_NAME: string = 'AudioPlayer';
const RECORDER_CLASS_NAME: string = 'AudioRecorder';
const PLAYLIST_CLASS_NAME: string = 'AudioPlaylist';
const STREAM_CLASS_NAME: string = 'AudioStream';
const STREAM_BUFFER_EVENT: string = 'audioStreamBuffer';
const STREAM_STATUS_EVENT: string = 'audioStreamStatus';
const PCM_16_BIT_NORMALIZER: number = 32_768;
const PLAYBACK_STATUS_EVENT: string = 'playbackStatusUpdate';
const RECORDING_STATUS_EVENT: string = 'recordingStatusUpdate';
const PLAYLIST_STATUS_EVENT: string = 'playlistStatusUpdate';
const TRACK_CHANGED_EVENT: string = 'trackChanged';
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const PERMISSION_PREFERENCES: string = 'ExpoAudioPermissions';
const MICROPHONE_DENIED: string = 'microphoneDenied';
const BACKGROUND_PLAYBACK_MODE: string = 'audioPlayback';
const BACKGROUND_RECORDING_MODE: string = 'audioRecording';
const MIN_UPDATE_INTERVAL_MS: number = 16;
const MIN_PLAYBACK_RATE: number = 0.1;
const MAX_PLAYBACK_RATE: number = 2.0;
const MIN_NATIVE_PLAYBACK_RATE: number = 0.125;
const MAX_TIMER_DELAY_MS: number = 2_147_483_647;
const SEEK_STEP_MS: number = 10_000;
const METERING_INTERVAL_MS: number = 100;
const SILENCE_LEVEL_DB: number = -160;
const PCM_16_BIT_MAX_AMPLITUDE: number = 32_767;
const INPUT_SELECTION_API: number = 21;
const DATA_URI_PREFIX: string = 'data:';
const DATA_URI_BASE64_MARKER: string = ';base64';
const FILE_URI_PREFIX: string = 'file://';
const DUCKING_VOLUME: number = 0.5;
const SOURCE_INITIALIZATION_TIMEOUT_MS: number = 15_000;
const SEEK_COMPLETION_TIMEOUT_MS: number = 15_000;
const MAX_DATA_URI_PAYLOAD_BYTES: number = 32 * 1024 * 1024;
const RAW_RESOURCE_NOT_FOUND: number = 9001005;
let sequence: number = 0;

type PlaylistLoopMode = 'none' | 'single' | 'all';
type InterruptionMode = 'mixWithOthers' | 'doNotMix' | 'duckOthers';

enum PermissionRequestReason {
  INVALID = 1,
  UNDECLARED = 2,
  CANNOT_REQUEST = 5,
  MANUAL_SETTINGS = 6,
}

interface AudioSource {
  uri?: string;
  headers?: Record<string, string>;
  name?: string;
}

interface AudioModeInput {
  playsInSilentMode?: boolean;
  shouldPlayInBackground?: boolean;
  shouldRouteThroughEarpiece?: boolean;
  interruptionMode?: string;
  allowsBackgroundRecording?: boolean;
}

interface RecordingOptionsInput {
  directory?: string;
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

    // The OS may already have released this descriptor even when close reports an error.
    this.closed = true;
    try {
      fs.closeSync(this.file);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (this.temporary) deleteFile(this.path);
    }
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
  isLiveStream?: boolean;
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
  isLive: boolean;
  currentOffsetFromLive: number | null = null;
  error: string | null;

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
    this.isLive = controller.isLive;
    this.error = controller.error;
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
  beforePlay(isCurrent: () => boolean): Promise<boolean>;
  playbackUsage(): audio.StreamUsage;
  playbackStateChanged(controller: PlaybackController): void;
  lockScreenStateChanged(controller: AudioPlayerController): void;
  setLockScreenPlayer(controller: AudioPlayerController, active: boolean, metadata?: AudioMetadataInput, options?: LockScreenOptionsInput): void;
  updateLockScreenMetadata(controller: AudioPlayerController, metadata?: AudioMetadataInput): void;
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

function sameSourceHeaders(first?: Record<string, string>, second?: Record<string, string>): boolean {
  const names: string[] = first === undefined ? [] : Object.keys(first);
  const count = second === undefined ? 0 : Object.keys(second).length;
  return names.length === count &&
    names.every((name: string): boolean => first?.[name] === second?.[name]);
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

function openSourceFile(path: string, temporary: boolean, context?: ExpoModuleContext): SourceFile {
  let file: fs.File | undefined;

  try {
    file = context === undefined
      ? fs.openSync(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NONBLOCK)
      : context.openFileForRead(path);
    const stat = fs.statSync(file.fd);

    if (!stat.isFile() || !Number.isSafeInteger(stat.size) || stat.size <= 0) {
      throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'The local audio source is empty or is not a regular file.');
    }

    return new SourceFile(path, file, 0, stat.size, temporary);
  } catch (error) {
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (_) {}
    }

    if (temporary) deleteFile(path);

    throw new ExpoAudioError('ERR_AUDIO_PLAYER_LOAD', `The local audio source '${path}' is not readable: ${cleanError(error as Object)}`);
  }
}

function openPackagedSource(context: ExpoModuleContext, uri: string): SourceFile {
  let name: string;
  try {
    name = rawResourcePathFromUri(uri);
  } catch (error) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', cleanError(error as Object));
  }

  const resources = context.uiAbilityContext.resourceManager;

  try {
    let descriptor: ExpoRawResourceFile;
    try {
      descriptor = openRawResourceFile(resources, name);
    } catch (error) {
      if (!/^asset:\/\//i.test(uri) || (error as BusinessError).code !== RAW_RESOURCE_NOT_FOUND) throw error as Error;

      let fallback: string;
      try {
        fallback = rawResourcePathFromUri(uri, true);
      } catch (_) {
        throw error as Error;
      }
      if (fallback === name) throw error as Error;

      name = fallback;
      descriptor = openRawResourceFile(resources, name);
    }

    if (descriptor.length === 0) {
      try { fs.closeSync(descriptor.file); } catch (_) {}
      throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', `The packaged audio '${name}' is empty.`);
    }

    return new SourceFile(uri, descriptor.file, descriptor.offset, descriptor.length, false);
  } catch (error) {
    throw new ExpoAudioError('ERR_AUDIO_PLAYER_LOAD', `The packaged audio '${name}' could not be opened: ${cleanError(error as Object)}`);
  }
}

function writeDataUri(uri: string, cacheDir: string): string {
  const comma = uri.indexOf(',');

  if (comma <= DATA_URI_PREFIX.length) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_DATA_URI', 'The audio data URI is malformed.');
  }

  const metadata = uri.slice(0, comma);
  if (!metadata.toLowerCase().endsWith(DATA_URI_BASE64_MARKER)) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_DATA_URI', 'HarmonyOS audio data URIs must use base64 encoding.');
  }

  const payload = uri.slice(comma + 1);
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

  if (bytes.byteLength > MAX_DATA_URI_PAYLOAD_BYTES) {
    throw new ExpoAudioError('ERR_AUDIO_DATA_URI_TOO_LARGE', `HarmonyOS audio data URIs are limited to ${MAX_DATA_URI_PAYLOAD_BYTES} decoded bytes.`);
  }

  const dir = `${cacheDir}/expo-audio/sources`;
  if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);

  sequence += 1;
  const path = `${dir}/source-${Date.now()}-${sequence}${dataUriExtension(metadata)}`;
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);

  try {
    if (fs.writeSync(file.fd, bytes.buffer) !== bytes.byteLength) {
      throw new ExpoAudioError('ERR_AUDIO_DATA_URI_WRITE', 'The cached audio source was only partially written.');
    }
  } catch (error) {
    try {
      fs.closeSync(file);
    } catch (_) {}

    deleteFile(path);

    throw new ExpoAudioError('ERR_AUDIO_DATA_URI_WRITE', `The audio data URI could not be cached: ${cleanError(error as Object)}`);
  }

  try {
    fs.closeSync(file);
  } catch (error) {
    deleteFile(path);
    throw new ExpoAudioError('ERR_AUDIO_DATA_URI_CLOSE', `The cached audio data URI file could not be closed: ${cleanError(error as Object)}`);
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

  if (isPackagedAudioUri(uri) || isRnohRawfileResourceUri(uri)) {
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

  if (uri.startsWith('/') || uri.toLowerCase().startsWith(FILE_URI_PREFIX)) {
    const file = openSourceFile(uri, false, context);

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

  if (context.services.get(ExpoFileAccessKey) !== undefined && !isRemoteAudioUri(uri)) {
    throw new ExpoAudioError('ERR_AUDIO_INVALID_SOURCE', 'This URI scheme is not supported by the project file policy.');
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

async function seekAndWait(player: media.AVPlayer, position: number): Promise<void> {
  let finish: (error?: ExpoAudioError) => void = (): void => {};
  let failure: ExpoAudioError | undefined;
  let settled = false;
  const complete = new Promise<void>((resolve: () => void): void => {
    finish = (error?: ExpoAudioError): void => {
      if (settled) return;

      settled = true;
      failure = error;
      resolve();
    };
  });

  const onSeekDone = (time: number): void => {
    if (time === position) finish();
  };
  const onError = (error: BusinessError): void => finish(new ExpoAudioError('ERR_AUDIO_SEEK', cleanError(error)));
  const onState = (state: media.AVPlayerState, _: media.StateChangeReason): void => {
    if (state === 'error' || state === 'released') {
      finish(new ExpoAudioError('ERR_AUDIO_SEEK', `HarmonyOS AVPlayer entered the ${state} state while seeking.`));
    }
  };
  let timer = -1;

  try {
    player.on('seekDone', onSeekDone);
    player.on('error', onError);
    player.on('stateChange', onState);

    timer = setTimeout((): void => {
      finish(new ExpoAudioError('ERR_AUDIO_SEEK_TIMEOUT', `HarmonyOS AVPlayer did not finish seeking within ${SEEK_COMPLETION_TIMEOUT_MS} ms.`));
    }, SEEK_COMPLETION_TIMEOUT_MS);

    player.seek(position, media.SeekMode.SEEK_CLOSEST);

    await complete;

    if (failure !== undefined) throw new ExpoAudioError(failure.code, failure.message);
  } finally {
    if (timer >= 0) clearTimeout(timer);

    try {
      player.off('seekDone', onSeekDone);
    } catch (_) {}
    try {
      player.off('error', onError);
    } catch (_) {}
    try {
      player.off('stateChange', onState);
    } catch (_) {}
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
  private readonly keepsAudioSessionActive: boolean;
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
  protected errorValue: string | null = null;
  protected duckedValue: boolean = false;
  private backgroundSuspended: boolean = false;
  private interruptionSuspended: boolean = false;
  private retainedAudioSession: boolean = false;
  private playRequest: number = 0;
  private seekWaiter?: (error?: ExpoAudioError, time?: number) => void;
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
  get suspendedForInterruption(): boolean {
    return this.interruptionSuspended;
  }
  get retainsAudioSession(): boolean {
    return this.retainedAudioSession;
  }
  get volume(): number {
    return this.volumeValue;
  }
  get playbackState(): string {
    return publicPlaybackState(this.state, this.bufferingValue);
  }
  get error(): string | null {
    return this.errorValue;
  }
  get isLive(): boolean {
    // AVPlayer documents -1 as the duration of a prepared live source.
    try {
      return this.loadedValue && this.player !== undefined && this.player.duration === -1;
    } catch (_) {
      return false;
    }
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
    this.schedule('replace source', async (): Promise<void> => this.replacePlayer(this.source, this.intendedPlaying, true));
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
    const playing = this.playing;
    this.intendedPlaying = true;
    const request = ++this.playRequest;
    const isCurrent = (): boolean => !this.destroyed && this.intendedPlaying && request === this.playRequest;

    if (playing !== this.playing) this.delegate.playbackStateChanged(this);
    this.emitStatus();

    this.enqueue(async (): Promise<void> => {
      if (!isCurrent() || sourceKey(this.source) === null) return;

      const player = this.requirePreparedPlayer('play');
      if (player.state === 'playing') return;

      if (!(await this.delegate.beforePlay(isCurrent))) {
        if (isCurrent()) {
          this.intendedPlaying = false;
          this.emitStatus();
        }
        if (!this.destroyed) this.delegate.playbackStateChanged(this);

        return;
      }

      if (!isCurrent() || this.player !== player) {
        this.delegate.playbackStateChanged(this);
        return;
      }

      if (player.state === 'completed' || this.state === 'completed') await this.seekAttachedPlayerAndWait(player, 0);
      if (!isCurrent() || this.player !== player) {
        this.delegate.playbackStateChanged(this);
        return;
      }

      const retained = this.retainedAudioSession;
      this.retainedAudioSession = this.keepsAudioSessionActive;
      try {
        await player.play();
      } catch (error) {
        if (this.player === player && this.retainedAudioSession) this.retainedAudioSession = retained;
        throw error as Error;
      }
      if (this.player !== player) return;

      this.errorValue = null;
      this.emitStatus();
    }).catch((error: Object): void => {
      if (isCurrent()) this.onScheduledError('play', error);
      else if (!this.destroyed) this.delegate.playbackStateChanged(this);
    });
  }

  pause(): void {
    const interrupted = this.interruptionSuspended;
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.pauseForSuspension(interrupted);
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

  clearAudioSessionRetention(): void {
    this.retainedAudioSession = false;
  }

  setDucked(ducked: boolean): void {
    if (this.duckedValue === ducked) return;

    this.duckedValue = ducked;
    this.schedule(ducked ? 'duck volume' : 'restore volume', async (): Promise<void> => this.applyVolume());
  }

  private pauseForSuspension(canceledInterruption: boolean = false): void {
    const wasPlaying = this.playing;
    this.intendedPlaying = false;

    if (canceledInterruption || wasPlaying !== this.playing) this.delegate.playbackStateChanged(this);
    this.emitStatus();

    this.schedule('pause', async (): Promise<void> => {
      const player = this.player;
      if (player !== undefined && player.state === 'playing') await player.pause();
    });
  }

  setPlaybackRate(rate: number): void {
    const value: number = bounded(rate, MIN_PLAYBACK_RATE, MAX_PLAYBACK_RATE);

    if (value < MIN_NATIVE_PLAYBACK_RATE) {
      throw new ExpoAudioError('ERR_AUDIO_PLAYBACK_RATE_UNSUPPORTED', `HarmonyOS cannot represent playback rates below ${MIN_NATIVE_PLAYBACK_RATE}.`);
    }
    if (deviceInfo.sdkApiVersion < 20) {
      const speed: number = legacySpeedValue(nearestLegacySpeed(value));

      if (Math.abs(speed - value) > 0.000001) {
        throw new ExpoAudioError('ERR_AUDIO_PLAYBACK_RATE_UNSUPPORTED', `HarmonyOS below API 20 cannot represent playback rate ${value}.`);
      }
    }

    this.rateValue = value;
    this.schedule('set playback rate', async (): Promise<void> => this.applyPlaybackRate());

    this.emitStatus();
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.seekWaiter?.(new ExpoAudioError('ERR_AUDIO_PLAYER_RELEASED', 'The audio object was released while seeking.'));
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

  protected async replacePlayer(source: AudioSource | null, resume: boolean, preserve: boolean = false): Promise<void> {
    if (this.destroyed) return;

    this.refreshPosition();
    const previous = this.player;
    const previousFile = this.sourceFile;
    const playing = this.playing;
    const position = preserve ? this.currentTimeMs : 0;
    const completed = preserve && this.state === 'completed';

    this.player = undefined;
    this.sourceFile = undefined;
    this.source = source;
    this.state = 'idle';
    this.loadedValue = false;
    this.bufferingValue = source !== null;
    this.playingValue = false;
    this.currentTimeMs = position;
    this.durationMs = 0;
    this.didJustFinish = false;
    this.errorValue = null;

    if (playing !== this.playing) this.delegate.playbackStateChanged(this);
    this.emitStatus();

    if (previous !== undefined && previous.state === 'playing') {
      try {
        await previous.pause();
      } catch (_) {}
    }

    await this.releasePlayer(previous, previousFile);
    if (this.destroyed || source === null) return;

    let next: media.AVPlayer | undefined;
    let nextFile: SourceFile | undefined;

    try {
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
      if (next.state !== 'prepared') {
        throw new ExpoAudioError('ERR_AUDIO_PLAYER_LOAD', `HarmonyOS AVPlayer entered the ${next.state} state while preparing the audio source.`);
      }

      const duration = this.safeDuration(next);

      // Live streams may have no seekable timeline.
      if (preserve && position > 0 && duration > 0 && this.isPreparedState(next.state)) {
        await seekAndWait(next, seekTargetMilliseconds(position / 1000, duration));
      }

      if (this.destroyed) {
        await this.releasePlayer(next, nextFile);

        return;
      }

      this.player = next;
      this.sourceFile = nextFile;
      this.attachPlayerCallbacks(next);
      this.state = completed ? 'completed' : next.state;
      this.loadedValue = this.isPreparedState(next.state);
      this.bufferingValue = false;
      this.durationMs = this.safeDuration(next);

      if (this.loadedValue) {
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

    await this.seekAttachedPlayerAndWait(player, target);
  }

  private async seekAttachedPlayerAndWait(player: media.AVPlayer, position: number): Promise<void> {
    let finish: (error?: ExpoAudioError, time?: number) => void = (): void => {};
    let failure: ExpoAudioError | undefined;
    let settled = false;
    const complete = new Promise<void>((resolve: () => void): void => {
      finish = (error?: ExpoAudioError, time?: number): void => {
        if (settled || (error === undefined && time !== position)) return;

        settled = true;
        failure = error;
        resolve();
      };
    });

    // AVPlayer keeps one listener per event, so attached seeks use the permanent callbacks.
    this.seekWaiter = finish;

    const timer = setTimeout((): void => {
      finish(new ExpoAudioError('ERR_AUDIO_SEEK_TIMEOUT', `HarmonyOS AVPlayer did not finish seeking within ${SEEK_COMPLETION_TIMEOUT_MS} ms.`));
    }, SEEK_COMPLETION_TIMEOUT_MS);

    try {
      player.seek(position, media.SeekMode.SEEK_CLOSEST);

      await complete;

      if (failure !== undefined) throw new ExpoAudioError(failure.code, failure.message);
    } finally {
      clearTimeout(timer);
      if (this.seekWaiter === finish) this.seekWaiter = undefined;
    }
  }

  protected onScheduledError(label: string, error: Object): void {
    if (this.destroyed && label !== 'release') return;

    this.errorValue = cleanError(error);
    console.error(`Expo Audio ${label} failed for ${this.id}: ${this.errorValue}`);

    if (
      label !== 'initialize' &&
      label !== 'replace source' &&
      label !== 'change playlist track' &&
      label !== 'advance after completion' &&
      label !== 'player state' &&
      label !== 'player callback'
    ) {
      if (label === 'play' && !this.playingValue) {
        this.intendedPlaying = false;
        this.delegate.playbackStateChanged(this);
      }
      this.emitStatus();
      return;
    }

    const player = this.player;
    const file = this.sourceFile;

    this.player = undefined;
    this.sourceFile = undefined;
    this.state = 'error';
    this.bufferingValue = false;
    this.playingValue = false;
    this.intendedPlaying = false;
    this.retainedAudioSession = false;
    this.loadedValue = false;
    this.currentTimeMs = 0;
    this.durationMs = 0;

    this.emitStatus();
    // Playlist edits can hide the failed source before this callback.
    this.delegate.playbackStateChanged(this);

    this.enqueue(async (): Promise<void> => this.releasePlayer(player, file)).catch((): void => {});
  }

  private attachPlayerCallbacks(target: media.AVPlayer): void {
    if (deviceInfo.sdkApiVersion < 20) {
      target.on('audioInterrupt', (event: audio.InterruptEvent): void => {
        if (this.destroyed || this.player !== target) return;

        if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
          this.suspendForInterruption();
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
          this.resumeFromInterruption();
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK &&
            event.forceType === audio.InterruptForceType.INTERRUPT_SHARE) {
          this.setDucked(true);
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
          this.setDucked(false);
        } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
          this.setDucked(false);
          this.pause();
        }
      });
    }
    target.on('stateChange', (state: media.AVPlayerState, _: media.StateChangeReason): void => {
      if (this.destroyed || this.player !== target) return;

      if (state === 'error' || state === 'released') {
        this.seekWaiter?.(new ExpoAudioError('ERR_AUDIO_SEEK', `HarmonyOS AVPlayer entered the ${state} state while seeking.`));
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
        const continuing: boolean = this.intendedPlaying && this.shouldContinueAfterCompletion();
        this.didJustFinish = !continuing;
        this.intendedPlaying = continuing;
        if (continuing) {
          this.schedule('advance after completion', async (): Promise<void> => {
            if (!this.destroyed && this.player === target && this.state === 'completed' && this.intendedPlaying) {
              await this.onCompleted();
            }
          });
        }
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
      this.seekWaiter?.(undefined, time);

      this.emitStatus();
    });
    target.on('audioOutputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo): void => {
      if (this.player !== target) return;
      if (info.changeReason !== audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) return;

      this.pause();
    });
    target.on('error', (error: BusinessError): void => {
      if (this.player !== target) return;

      this.seekWaiter?.(new ExpoAudioError('ERR_AUDIO_SEEK', cleanError(error)));
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

    if (deviceInfo.sdkApiVersion >= 20) {
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
    this.delegate.setLockScreenPlayer(this, active, metadata, options);
  }

  updateLockScreenMetadata(metadata?: AudioMetadataInput): void {
    this.delegate.updateLockScreenMetadata(this, metadata);
  }

  clearLockScreenControls(): void {
    this.delegate.setLockScreenPlayer(this, false);
  }

  protected emitStatus(): void {
    super.emitStatus();
    this.delegate.lockScreenStateChanged(this);
  }

  destroy(): void {
    this.clearLockScreenControls();
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

  // List edits precede queued AVPlayer replacement.
  private get hasCurrentSource(): boolean {
    return this.tracks.length > 0 && this.source === this.tracks[this.indexValue];
  }
  get playing(): boolean {
    return this.hasCurrentSource && super.playing;
  }
  get loaded(): boolean {
    return this.hasCurrentSource && super.loaded;
  }
  get buffering(): boolean {
    return this.hasCurrentSource && super.buffering;
  }
  get currentTimeSeconds(): number {
    return this.hasCurrentSource ? super.currentTimeSeconds : 0;
  }
  get durationSeconds(): number {
    return this.hasCurrentSource ? super.durationSeconds : 0;
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
    if (this.tracks.length === 1) this.scheduleCurrentTrackLoad(false);

    this.emitStatus();
  }

  insert(source: AudioSource | null, index: number): void {
    const position = Math.trunc(index);
    if (source === null || source.uri === undefined || source.uri.length === 0 || !(position >= 0 && position <= this.tracks.length)) return;

    this.tracks.splice(position, 0, source);

    if (this.tracks.length === 1) this.scheduleCurrentTrackLoad(false);
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
    this.delegate.playbackStateChanged(this);
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

  private scheduleCurrentTrackLoad(resume: boolean): void {
    this.schedule(
      'change playlist track',
      async (): Promise<void> => this.replacePlayer(this.tracks[this.indexValue] ?? null, resume && this.intendedPlaying),
    );
  }

  private scheduleTrackChange(index: number): void {
    this.schedule('change playlist track', async (): Promise<void> => {
      await this.changeTrack(index, this.intendedPlaying);
    });
  }

  private scheduleRelativeTrackChange(offset: number): void {
    this.schedule('change playlist track', async (): Promise<void> => {
      const index = offset > 0 ? this.nextIndex() : this.previousIndex();
      await this.changeTrack(index, this.intendedPlaying);
    });
  }

  private async changeTrack(index: number, resume: boolean): Promise<void> {
    if (!(index >= 0 && index < this.tracks.length)) return;

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
    if (!(index >= 0 && index < this.tracks.length)) return;

    const current = index === this.indexValue;
    const resume = this.playing || this.intendedPlaying;

    this.tracks.splice(index, 1);

    if (this.tracks.length === 0) {
      this.indexValue = 0;
      this.intendedPlaying = false;

      this.schedule('empty playlist', async (): Promise<void> => this.replacePlayer(null, false));
      this.delegate.playbackStateChanged(this);
    } else if (current) {
      this.indexValue = Math.min(index, this.tracks.length - 1);

      this.scheduleCurrentTrackLoad(resume);
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
    isLiveStream: input.isLiveStream === true,
  };
}

function readRecordingOptions(value: ESObject, fallback?: RecordingOptionsInput): RecordingOptionsInput {
  const options: RecordingOptionsInput = {};

  if (fallback !== undefined) {
    options.directory = fallback.directory;
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

  if (input.directory !== undefined) {
    if (input.directory !== 'cache' && input.directory !== 'document') {
      throw new ExpoAudioError('ERR_AUDIO_RECORDING_DIRECTORY', 'Recording directory must be cache or document.');
    }

    options.directory = input.directory as string;
  }
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
  options.directory = input.directory ?? fallback.directory;
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
  ensureRecordingAvailable(): void;
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
  private stopTimer: number = -1;
  private stoppingRecorder?: media.AVRecorder;
  private stopFailure: string | null = null;
  private observed: boolean = false;
  private failed: boolean = false;
  private backgroundSuspended: boolean = false;
  private interruptionSuspended: boolean = false;
  private recordingRequested: boolean = false;
  private recordGeneration: number = 0;
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
    return this.outputPath === null ? null : fileUriFromPath(this.outputPath);
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
    await this.enqueue(async (): Promise<void> => this.stopInternal());
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
    this.schedule('release recorder', async (): Promise<void> => this.stopInternal());
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
    this.elapsedBeforeStartMs = 0;
    this.startedAtMs = 0;

    this.clearTimers();
    const recorder = this.recorder;
    const file = this.outputFile;
    const path = this.outputPath;
    this.recorder = undefined;
    this.outputFile = undefined;
    this.outputPath = null;
    this.enqueue(async (): Promise<void> => {
      await this.closeNativeRecorder(recorder, file);
      if (path !== null) deleteFile(path);
    }).catch((): void => {});
    this.emitResult(message);
    this.delegate.recordingStateChanged();
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
    const root = options.directory === 'document' ? this.delegate.context.persistentFilesPath : this.delegate.context.cachePath;
    const folder = `${root}/expo-audio`;

    if (!fs.accessSync(folder)) fs.mkdirSync(folder, true);

    sequence += 1;
    const path = `${folder}/recording-${Date.now()}-${sequence}${profile.extension}`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);

    let recorder: media.AVRecorder | undefined;

    try {
      const current = await media.createAVRecorder();
      recorder = current;

      current.on('stateChange', (state: media.AVRecorderState, _: media.StateChangeReason): void => {
        if (this.recorder !== current || this.destroyed) return;

        this.handleStateChange(current, state);
      });
      current.on('error', (error: BusinessError): void => {
        if (this.recorder !== current) return;
        if (this.stoppingRecorder === current) {
          this.stopFailure = cleanError(error);
        } else if (current.state === 'error') {
          this.onScheduledError('recorder callback', error);
        } else {
          this.emitOperationError(cleanError(error));
        }
      });

      await recorder.prepare({
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: profile.profile,
        url: `fd://${file.fd}`,
      });

      if (deviceInfo.sdkApiVersion >= 20) await recorder.setWillMuteWhenInterrupted(true);
      if (this.destroyed) throw new ExpoAudioError('ERR_AUDIO_RECORDER_RELEASED', 'The audio recorder was released.');
      if (recorder.state !== 'prepared') {
        throw new ExpoAudioError('ERR_AUDIO_RECORDER_PREPARE', `HarmonyOS AVRecorder entered the ${recorder.state} state while preparing the recording.`);
      }
    } catch (error) {
      if (recorder !== undefined) {
        try {
          await recorder.release();
        } catch (_) {}
      }

      try {
        fs.closeSync(file);
      } catch (_) {}

      deleteFile(path);

      throw new ExpoAudioError('ERR_AUDIO_RECORDER_PREPARE', cleanError(error as Object));
    }

    if (recorder === undefined) {
      try {
        fs.closeSync(file);
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
    this.delegate.ensureRecordingAvailable();

    if (!this.preparedValue || this.recorder === undefined) {
      throw new ExpoAudioError('ERR_AUDIO_RECORDER_NOT_PREPARED', 'Call prepareToRecordAsync() before starting an audio recording.');
    }

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

    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.recordingRequested = true;
    this.recordGeneration += 1;
    const generation = this.recordGeneration;

    this.clearStopTimer();
    this.pendingDurationMs = options.forDuration === undefined ? -1 : positiveDelayMilliseconds(options.forDuration);
    this.scheduleRecordingStart(generation);
  }

  private scheduleRecordingStart(generation: number): void {
    const duration = this.pendingDurationMs;

    this.schedule('start recorder', async (): Promise<void> => {
      if (generation !== this.recordGeneration || this.backgroundSuspended || this.interruptionSuspended || !this.recordingRequested) return;

      const recorder = this.requireRecorder('start');
      this.delegate.ensureRecordingAvailable();

      if (!this.recordingValue) {
        if (this.pausedValue) await recorder.resume();
        else await recorder.start();

        if (this.recorder !== recorder || this.destroyed) return;

        this.startedAtMs = uptimeMilliseconds();
        this.recordingValue = true;
        this.pausedValue = false;
        this.startProgressTimers();
        this.delegate.recordingStateChanged();
      }

      if (generation === this.recordGeneration) this.pendingDurationMs = -1;

      // A newer record request owns the timer. Pausing an in-flight start
      // still preserves its duration, like pausing an active recording.
      if (duration >= 0 && (generation === this.recordGeneration || !this.recordingRequested)) {
        this.stopTimer = setTimeout((): void => {
          this.stopTimer = -1;
          this.backgroundSuspended = false;
          this.interruptionSuspended = false;
          this.recordingRequested = false;
          this.recordGeneration += 1;

          this.enqueue(async (): Promise<void> => this.stopInternal()).catch((error: Object): void => {
            console.error(`Expo Audio timed stop recorder failed for ${this.id}: ${cleanError(error)}`);
          });
        }, duration);
      }
    });
  }

  pause(): void {
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;
    this.schedule('pause recorder', async (): Promise<void> => this.pauseNativeRecorder());
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

    if (!this.recordingRequested || !this.preparedValue || this.interruptionSuspended) return;
    this.scheduleRecordingStart(this.recordGeneration);
  }

  cancelBackgroundSuspension(): void {
    if (!this.backgroundSuspended) return;

    this.backgroundSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;
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
    this.scheduleRecordingStart(this.recordGeneration);
  }

  cancelInterruptionSuspension(): void {
    if (!this.interruptionSuspended) return;

    this.interruptionSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;
  }

  private pauseForSuspension(): void {
    this.schedule('pause recorder', async (): Promise<void> => this.pauseNativeRecorder());
  }

  private async pauseNativeRecorder(): Promise<void> {
    if (!this.recordingValue) return;
    const recorder = this.requireRecorder('pause');
    await recorder.pause();
    if (this.recorder !== recorder || this.destroyed) return;

    this.elapsedBeforeStartMs = this.durationMillis;
    this.recordingValue = false;
    this.pausedValue = true;
    this.stopProgressTimers();
    this.delegate.recordingStateChanged();
  }

  private async stopInternal(): Promise<void> {
    this.backgroundSuspended = false;
    this.interruptionSuspended = false;
    this.recordingRequested = false;
    this.recordGeneration += 1;
    this.pendingDurationMs = -1;

    this.clearTimers();

    const recorder = this.recorder;
    if (recorder === undefined) return;

    const hasRecording = this.recordingValue || this.pausedValue ||
      recorder.state === 'started' || recorder.state === 'paused' || recorder.state === 'stopped';
    this.stoppingRecorder = recorder;
    this.stopFailure = null;
    try {
      if (recorder.state === 'started' || recorder.state === 'paused') await recorder.stop();
    } catch (cause) {
      if (this.stopFailure === null) this.stopFailure = cleanError(cause as Object);
    }
    const failure = this.stopFailure;
    this.stoppingRecorder = undefined;

    const discardedPath = !hasRecording || failure !== null ? this.outputPath : null;
    if (discardedPath !== null) this.outputPath = null;
    await this.releaseRecorder();
    if (discardedPath !== null) deleteFile(discardedPath);

    if (hasRecording || failure !== null) this.emitResult(failure);
    if (failure !== null) throw new ExpoAudioError('ERR_AUDIO_RECORDING_STOP', failure);
  }

  private async releaseRecorder(): Promise<void> {
    const recorder = this.recorder;
    const file = this.outputFile;
    this.recorder = undefined;
    this.outputFile = undefined;
    await this.closeNativeRecorder(recorder, file);

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

  private async closeNativeRecorder(recorder?: media.AVRecorder, file?: fs.File): Promise<void> {
    if (recorder !== undefined && recorder.state !== 'released') {
      try {
        await recorder.release();
      } catch (_) {}
    }

    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (_) {}
    }
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

    if (deviceInfo.sdkApiVersion < 21) {
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
      this.requireRecorder('select input');

      if (deviceInfo.sdkApiVersion >= 21) {
        await manager.getSessionManager().selectMediaInputDevice(input);
      }
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

  private handleStateChange(recorder: media.AVRecorder, state: media.AVRecorderState): void {
    if (this.stoppingRecorder === recorder) {
      if (state === 'error' && this.stopFailure === null) this.stopFailure = 'HarmonyOS AVRecorder entered the error state.';
      return;
    }
    if (state === 'stopped' && this.preparedValue) {
      this.backgroundSuspended = false;
      this.interruptionSuspended = false;
      this.recordingRequested = false;
      this.recordGeneration += 1;
      this.pendingDurationMs = -1;

      this.enqueue(async (): Promise<void> => {
        if (this.recorder === recorder) await this.stopInternal();
      }).catch((error: Object): void => {
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

  private clearStopTimer(): void {
    if (this.stopTimer >= 0) clearTimeout(this.stopTimer);
    this.stopTimer = -1;
  }

  private stopProgressTimers(): void {
    if (this.meteringTimer >= 0) clearInterval(this.meteringTimer);

    this.meteringTimer = -1;
  }

  private clearTimers(): void {
    this.clearStopTimer();
    this.stopProgressTimers();
  }
}

class ExpoAudioRuntime implements PlaybackDelegate, RecorderDelegate {
  readonly context: ExpoModuleContext;
  private readonly players: Map<number, AudioPlayerController> = new Map();
  private readonly recorders: Map<number, AudioRecorderController> = new Map();
  private readonly streams: Map<number, ExpoAudioStream> = new Map();
  private readonly volumeManager: audio.AudioVolumeGroupManager;
  private readonly unsubscribeRingerMode: () => void;
  private readonly onRingerModeChange: (mode: audio.AudioRingMode) => void = (mode: audio.AudioRingMode): void => {
    if (!this.destroyed && this.mode.playsInSilentMode === false && mode !== audio.AudioRingMode.RINGER_MODE_NORMAL) this.pauseAllPlayback();
  };
  private readonly onSessionDeactivated: (event: audio.AudioSessionDeactivatedEvent) => void = (event: audio.AudioSessionDeactivatedEvent): void => {
    if (this.destroyed || ExpoAudioSessionClient.isDeactivating || !this.audioSessionAcquired) return;
    if (deviceInfo.sdkApiVersion >= 20 && this.focusInterrupted && event.reason === audio.AudioSessionDeactivatedReason.DEACTIVATED_LOWER_PRIORITY) return;
    this.focusInterrupted = false;
    this.clearAudioSessionRetainers();
    this.pauseAllPlayback();
    this.deactivateAudioSession();
  };
  private readonly onSessionStateChanged: (event: audio.AudioSessionStateChangedEvent) => void = (event: audio.AudioSessionStateChangedEvent): void => {
    if (!this.destroyed) this.handleAudioSessionStateChanged(event);
  };
  private readonly playlists: Map<number, PlaylistController> = new Map();
  private readonly preloaded: Map<string, PreloadEntry> = new Map();
  private readonly sessionManager: audio.AudioSessionManager;
  private readonly audioSession: ExpoAudioSessionClient = new ExpoAudioSessionClient();
  private microphoneRequest?: Promise<PermissionRecord>;
  private active: boolean = true;
  private inBackground: boolean;
  private focusInterrupted: boolean = false;
  private mode: AudioModeInput = {};
  private interruptionMode: InterruptionMode = 'mixWithOthers';
  private audioSessionAcquired: boolean = false;
  private audioSessionTail: Promise<void> = Promise.resolve();
  private lockScreenPlayer?: AudioPlayerController;
  private lockScreenOptions?: LockScreenOptionsInput;
  private lockScreenMetadata?: AudioMetadataInput;
  private lockScreenSession?: ExpoAVSessionClient;
  private sessionController?: PlaybackController;
  private sessionOptions?: LockScreenOptionsInput;
  private sessionNeedsActivation: boolean = false;
  private requestedLockScreenActivation: number = 0;
  private publishedLockScreenActivation: number = 0;
  private mediaSessionTail: Promise<void> = Promise.resolve();
  private lockScreenGeneration: number = 0;
  private backgroundModes: string[] = [];
  private readonly backgroundTaskIds = new Map<string, number>();
  private readonly stoppingBackgroundTasks = new Set<number>();
  private readonly canceledBackgroundModes = new Set<string>();
  private listeningForBackgroundCancellation: boolean = false;
  private readonly onBackgroundTaskCanceled = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (this.destroyed || this.stoppingBackgroundTasks.has(info.id)) return;
    for (const entry of this.backgroundTaskIds) {
      const mode = entry[0];
      if (entry[1] !== info.id) continue;

      this.backgroundTaskIds.delete(mode);
      if (!this.inBackground) return;

      this.canceledBackgroundModes.add(mode);
      if (mode === BACKGROUND_PLAYBACK_MODE) {
        this.clearAudioSessionRetainers();
        this.pauseAllPlayback();
        if (this.lockScreenPlayer === undefined) this.clearMediaSession();
      } else {
        this.streams.forEach((stream: ExpoAudioStream): void => stream.stop());
        this.recorders.forEach((recorder: AudioRecorderController): void => {
          if (!recorder.recording) return;

          recorder.stop().catch((error: Object): void => {
            console.error(`Expo Audio recorder stop after background cancellation failed: ${cleanError(error)}`);
          });
        });
      }
      this.scheduleBackgroundTaskSync();
      return;
    }
  };
  private backgroundTaskTail: Promise<void> = Promise.resolve();
  private lifecycleTail: Promise<void> = Promise.resolve();
  private nextObjectId: number = 1;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    this.context = context;
    this.inBackground = context.appLifecycleState === ExpoAppLifecycleState.BACKGROUND;
    this.sessionManager = audio.getAudioManager().getSessionManager();
    this.volumeManager = audio.getAudioManager().getVolumeManager().getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID);
    this.unsubscribeRingerMode = observeDefaultRingerMode(this.volumeManager, this.onRingerModeChange);
    this.sessionManager.on('audioSessionDeactivated', this.onSessionDeactivated);

    if (deviceInfo.sdkApiVersion >= 20) {
      this.sessionManager.on('audioSessionStateChanged', this.onSessionStateChanged);
    }
  }

  get cacheDir(): string {
    return this.context.cachePath;
  }

  playbackUsage(): audio.StreamUsage {
    return this.mode.shouldRouteThroughEarpiece === true ? audio.StreamUsage.STREAM_USAGE_VOICE_MESSAGE : audio.StreamUsage.STREAM_USAGE_MUSIC;
  }

  async takePreloaded(source: AudioSource): Promise<PreparedPlayer | undefined> {
    const key = sourceKey(source);
    if (key === null) return undefined;

    const entry = this.preloaded.get(key);
    if (this.destroyed || entry === undefined || !sameSourceHeaders(entry.source.headers, source.headers)) return undefined;

    const prepared = this.createPreloadedPlayer(entry.source, entry.preferredBufferDuration);
    const replacement = new PreloadEntry(entry.source, entry.preferredBufferDuration, prepared);

    this.preloaded.set(key, replacement);
    prepared.catch((): void => {
      if (this.preloaded.get(key) === replacement) this.preloaded.delete(key);
    });

    const result = await entry.prepared.catch((): undefined => undefined);
    if (result === undefined || result.player.state === 'prepared') return result;

    await this.releasePreload(entry).catch((): void => {});
    return undefined;
  }

  private canPlay(): boolean {
    return this.active && !this.destroyed &&
      (!this.inBackground || this.canContinueInBackground(BACKGROUND_PLAYBACK_MODE)) && this.shouldPlayInSilentMode();
  }

  async beforePlay(isCurrent: () => boolean): Promise<boolean> {
    let allowed = false;
    await this.queueAudioSessionOperation(async (): Promise<void> => {
      if (!this.canPlay() || !isCurrent()) return;
      await this.acquireAudioSession(this.interruptionMode, this.mode.shouldRouteThroughEarpiece === true);
      allowed = this.canPlay() && isCurrent();
    });
    return allowed;
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
        this.lockScreenMetadata = undefined;
        this.lockScreenGeneration += 1;
        this.publishedLockScreenActivation = this.requestedLockScreenActivation;

        if (this.inBackground && this.mode.shouldPlayInBackground === true && this.hasActivePlayback()) {
          this.scheduleBackgroundTaskSync();
        } else {
          this.clearMediaSession();
        }
      }

      return;
    }

    this.lockScreenPlayer = controller;
    this.lockScreenOptions = options;
    this.requestedLockScreenActivation += 1;
    this.updateLockScreenMetadata(controller, metadata);
  }

  updateLockScreenMetadata(controller: AudioPlayerController, metadata?: AudioMetadataInput): void {
    if (this.destroyed || this.lockScreenPlayer !== controller) return;

    this.lockScreenMetadata = metadata;
    const options = this.lockScreenOptions;
    const generation = ++this.lockScreenGeneration;

    this.queueMediaSessionOperation(async (): Promise<void> => {
      if (generation !== this.lockScreenGeneration || this.lockScreenPlayer !== controller) return;

      const session = await this.ensureMediaSessionNow(controller, options);
      if (generation !== this.lockScreenGeneration || this.lockScreenPlayer !== controller) return;

      await this.setMediaSessionMetadata(session, controller, metadata, options);
      if (generation !== this.lockScreenGeneration || this.lockScreenPlayer !== controller) return;
      await session.setAVPlaybackState(this.mediaPlaybackState(controller), controller.playing ? 1 : 0);
      if (generation !== this.lockScreenGeneration || this.lockScreenPlayer !== controller) return;
      await this.activateMediaSession(session, controller);
    }).catch((error: Object): void => {
      console.error(`Expo Audio lock-screen setup failed: ${cleanError(error)}`);
    });
  }

  private async setMediaSessionMetadata(
    session: ExpoAVSessionClient,
    controller: PlaybackController,
    metadata?: AudioMetadataInput,
    options?: LockScreenOptionsInput,
  ): Promise<void> {
    const details: avSession.AVMetadata = { assetId: controller.id };
    if (metadata?.title !== undefined) details.title = metadata.title;
    if (metadata?.artist !== undefined) details.artist = metadata.artist;
    if (metadata?.albumTitle !== undefined) details.album = metadata.albumTitle;
    if (metadata?.artworkUrl !== undefined) details.mediaImage = metadata.artworkUrl;
    if (options?.isLiveStream !== true && controller.durationSeconds > 0) {
      details.duration = Math.round(controller.durationSeconds * 1000);
    }
    await session.setAVMetadata(details);
  }

  ensureRecordingPermission(): void {
    if (this.context.permissionStatus(MICROPHONE_PERMISSION) !== ExpoPermissionStatus.GRANTED) {
      throw new ExpoAudioError('ERR_AUDIO_RECORDING_PERMISSION', 'Microphone permission has not been granted.');
    }
  }

  ensureRecordingAvailable(): void {
    if (this.destroyed || (this.inBackground && !this.canContinueInBackground(BACKGROUND_RECORDING_MODE))) {
      throw new ExpoAudioError('ERR_AUDIO_RECORDING_UNAVAILABLE', 'Audio recording is unavailable in the current app state.');
    }
    this.ensureRecordingPermission();
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
    const streams = Array.from(this.streams.values());

    players.forEach((controller: AudioPlayerController): void => controller.destroy());
    recorders.forEach((controller: AudioRecorderController): void => controller.destroy());
    playlists.forEach((controller: PlaylistController): void => controller.destroy());
    streams.forEach((stream: ExpoAudioStream): void => stream.destroy());
    this.streams.clear();
    this.players.clear();
    this.recorders.clear();
    this.playlists.clear();

    for (let index = 0; index < players.length; index += 1) await players[index].waitForIdle();
    for (let index = 0; index < recorders.length; index += 1) await recorders[index].waitForIdle();
    for (let index = 0; index < playlists.length; index += 1) await playlists[index].waitForIdle();

    for (let index = 0; index < streams.length; index += 1) await streams[index].waitForIdle();

    await this.clearAllPreloaded();
    await this.stopBackgroundTask();
    if (deviceInfo.sdkApiVersion >= 21 && this.listeningForBackgroundCancellation) {
      try { backgroundTaskManager.off('continuousTaskCancel', this.onBackgroundTaskCanceled); } catch (_) {}
    }
    this.lockScreenPlayer = undefined;
    this.lockScreenOptions = undefined;
    this.lockScreenMetadata = undefined;
    this.clearMediaSession();
    await this.mediaSessionTail.catch((): void => {});
    await this.deactivateAudioSession();

    try {
      this.sessionManager.off('audioSessionDeactivated', this.onSessionDeactivated);
    } catch (_) {}
    try { this.unsubscribeRingerMode(); } catch (_) {}

    if (deviceInfo.sdkApiVersion >= 20) {
      try {
        this.sessionManager.off('audioSessionStateChanged', this.onSessionStateChanged);
      } catch (_) {}
    }
  }

  private async queueLifecycle(operation: () => Promise<void>): Promise<void> {
    const run = this.lifecycleTail.catch((): void => {}).then(operation);

    this.lifecycleTail = run.catch((): void => {});

    await run;
  }

  registerStream(stream: ExpoAudioStream): number {
    if (this.destroyed) throw new ExpoAudioError('ERR_AUDIO_MODULE_DESTROYED', 'Expo Audio has already been destroyed.');

    const id = this.allocateObjectId();
    this.streams.set(id, stream);

    return id;
  }

  releaseStream(id: number): void {
    this.streams.delete(id);
    this.recordingStateChanged();
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
    player.destroy();
    if (this.sessionController === player) this.clearMediaSession();
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

    this.clearAudioSessionRetainers();
    this.pauseAllPlayback();

    await this.deactivateAudioSession();
  }

  async setAudioMode(input: AudioModeInput): Promise<void> {
    await this.queueLifecycle(async (): Promise<void> => this.applyAudioMode(input));
  }

  private async applyAudioMode(input: AudioModeInput): Promise<void> {
    if (this.destroyed) return;

    const next: AudioModeInput = {
      playsInSilentMode: input.playsInSilentMode ?? this.mode.playsInSilentMode,
      shouldPlayInBackground: input.shouldPlayInBackground ?? this.mode.shouldPlayInBackground,
      shouldRouteThroughEarpiece: input.shouldRouteThroughEarpiece ?? this.mode.shouldRouteThroughEarpiece,
      allowsBackgroundRecording: input.allowsBackgroundRecording ?? this.mode.allowsBackgroundRecording,
      interruptionMode: input.interruptionMode ?? this.mode.interruptionMode,
    };
    const interruption: InterruptionMode = normalizeInterruptionMode(next.interruptionMode ?? 'mixWithOthers');
    const routeChanged: boolean = (next.shouldRouteThroughEarpiece === true) !== (this.mode.shouldRouteThroughEarpiece === true);
    const interruptionChanged = interruption !== this.interruptionMode;

    const earpiece = next.shouldRouteThroughEarpiece === true;
    if (routeChanged && earpiece && deviceInfo.sdkApiVersion < 20) {
      throw new ExpoAudioError('ERR_AUDIO_EARPIECE_ROUTING_UNSUPPORTED', 'Routing playback through the earpiece requires HarmonyOS API 20 or newer.');
    }

    if (routeChanged || interruptionChanged) {
      await this.queueAudioSessionOperation(async (): Promise<void> => {
        if (this.audioSession.isActive()) await this.acquireAudioSession(interruption, earpiece);
        this.mode = next;
        this.interruptionMode = interruption;
      });
    } else {
      this.mode = next;
    }

    if (!this.shouldPlayInSilentMode()) this.pauseAllPlayback();
    if (this.inBackground) this.suspendDisallowedBackgroundAudio();

    if (routeChanged) {
      await this.clearAllPreloaded();
      this.players.forEach((player: AudioPlayerController): void => player.refreshAudioRendererUsage());
      this.playlists.forEach((playlist: PlaylistController): void => playlist.refreshAudioRendererUsage());
    }

    if (this.inBackground) await this.queueBackgroundTaskSync();
  }

  private shouldPlayInSilentMode(): boolean {
    return this.mode.playsInSilentMode !== false || this.volumeManager.getRingerModeSync() === audio.AudioRingMode.RINGER_MODE_NORMAL;
  }

  private concurrencyMode(interruption: InterruptionMode): audio.AudioConcurrencyMode {
    if (interruption === 'doNotMix') return audio.AudioConcurrencyMode.CONCURRENCY_PAUSE_OTHERS;
    if (interruption === 'duckOthers') return audio.AudioConcurrencyMode.CONCURRENCY_DUCK_OTHERS;
    return audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS;
  }

  private hasActivePlayback(): boolean {
    return (
      Array.from(this.players.values()).some((player: AudioPlayerController): boolean => player.playing) ||
      Array.from(this.playlists.values()).some((playlist: PlaylistController): boolean => playlist.playing)
    );
  }

  private hasSessionRetainer(): boolean {
    return Array.from(this.players.values()).some((player: AudioPlayerController): boolean =>
      player.retainsAudioSession || player.suspendedForInterruption
    ) || Array.from(this.playlists.values()).some((playlist: PlaylistController): boolean => playlist.suspendedForInterruption);
  }

  private clearAudioSessionRetainers(): void {
    this.players.forEach((player: AudioPlayerController): void => player.clearAudioSessionRetention());
  }

  private pauseAllPlayback(): void {
    this.players.forEach((player: AudioPlayerController): void => player.pause());
    this.playlists.forEach((playlist: PlaylistController): void => playlist.pause());
  }

  private handleAudioSessionStateChanged(event: audio.AudioSessionStateChangedEvent): void {
    if (this.destroyed || ExpoAudioSessionClient.isDeactivating) return;

    if (deviceInfo.sdkApiVersion >= 20) {
      const hint = event.stateChangeHint;

      if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE) {
        this.focusInterrupted = true;

        this.players.forEach((player: AudioPlayerController): void => player.suspendForInterruption());
        this.playlists.forEach((playlist: PlaylistController): void => playlist.suspendForInterruption());
        this.recorders.forEach((recorder: AudioRecorderController): void => recorder.suspendForInterruption());

        return;
      }

      // AudioKit applies session ducking itself. Only RESUME ends a temporary pause.
      if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME) {
        this.focusInterrupted = false;

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

        this.clearAudioSessionRetainers();
        this.recorders.forEach((recorder: AudioRecorderController): void => {
          recorder.suspendForInterruption();
          recorder.cancelInterruptionSuspension();
        });
        this.pauseAllPlayback();
        this.deactivateAudioSession();
      }
    }
  }

  private resumeInterruptedPlayback(): void {
    this.players.forEach((player: AudioPlayerController): void => player.resumeFromInterruption());
    this.playlists.forEach((playlist: PlaylistController): void => playlist.resumeFromInterruption());
  }

  private resumeInterruptedRecorders(): void {
    this.recorders.forEach((recorder: AudioRecorderController): void => recorder.resumeFromInterruption());
  }

  private queueAudioSessionOperation(operation: () => Promise<void>): Promise<void> {
    const next = this.audioSessionTail.then(operation);
    this.audioSessionTail = next.catch((): void => {});
    return next;
  }

  private async acquireAudioSession(interruption: InterruptionMode, earpiece: boolean): Promise<void> {
    await this.audioSession.acquire({
      concurrencyMode: this.concurrencyMode(interruption),
      scene: earpiece ? audio.AudioSessionScene.AUDIO_SESSION_SCENE_VOICE_COMMUNICATION : undefined,
      outputDevice: earpiece ? audio.DeviceType.EARPIECE : undefined,
    });
    this.audioSessionAcquired = true;
  }

  private async deactivateAudioSession(): Promise<void> {
    await this.queueAudioSessionOperation(async (): Promise<void> => {
      if (!this.audioSessionAcquired) return;
      await this.audioSession.release();
      this.audioSessionAcquired = false;
    }).catch((error: Object): void => {
      console.error(`Expo Audio session release failed: ${cleanError(error as Object)}`);
    });
  }

  async preload(source: AudioSource | null, preferredBufferDuration: number): Promise<void> {
    const key = sourceKey(source);

    if (this.destroyed || source === null || key === null) return;

    const entry = this.preloaded.get(key);

    if (entry !== undefined && sameSourceHeaders(entry.source.headers, source.headers)) {
      await entry.prepared;

      return;
    }

    const duration = Math.max(0, finiteNumber(preferredBufferDuration, 0));
    const load = this.createPreloadedPlayer(source, duration);
    const next = new PreloadEntry(source, duration, load);

    this.preloaded.set(key, next);
    const cleanup = entry === undefined ? Promise.resolve() : this.releasePreload(entry).catch((): void => {});

    try {
      await load;
    } catch (error) {
      if (this.preloaded.get(key) === next) this.preloaded.delete(key);

      throw new ExpoAudioError('ERR_AUDIO_PRELOAD', cleanError(error as Object));
    } finally {
      await cleanup;
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

    await this.releasePreload(entry);
  }

  private async releasePreload(entry: PreloadEntry): Promise<void> {
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
      await this.releasePreload(entries[index]).catch((): void => {});
    }
  }

  async getRecordingPermission(): Promise<PermissionRecord> {
    let denied: boolean | undefined;
    if (deviceInfo.sdkApiVersion < 20) {
      try {
        const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PERMISSION_PREFERENCES });
        denied = (await store.get(MICROPHONE_DENIED, false)) === true;
      } catch (_) {}
    }
    const status = this.context.permissionStatus(MICROPHONE_PERMISSION, denied);
    if (status === ExpoPermissionStatus.GRANTED) return new PermissionRecord('granted', true);
    if (status === ExpoPermissionStatus.NOT_DETERMINED) return new PermissionRecord('undetermined', true);
    // Older systems expose permanent denial only in the request result.
    return new PermissionRecord('denied', status === ExpoPermissionStatus.DENIED && deviceInfo.sdkApiVersion < 20);
  }

  async requestRecordingPermission(): Promise<PermissionRecord> {
    if (this.microphoneRequest !== undefined) return await this.microphoneRequest;
    const pending = this.requestMicrophone();
    this.microphoneRequest = pending;
    try {
      return await pending;
    } finally {
      if (this.microphoneRequest === pending) this.microphoneRequest = undefined;
    }
  }

  private async requestMicrophone(): Promise<PermissionRecord> {
    const request = await this.context.requestPermissions([MICROPHONE_PERMISSION]).catch((error: Object): never => {
      throw new ExpoAudioError('ERR_AUDIO_PERMISSION_REQUEST', cleanError(error));
    });
    let blocked = false;
    let denied: boolean | undefined;
    for (const result of request.systemResults) {
      const index = result.permissions.indexOf(MICROPHONE_PERMISSION);
      const reason = deviceInfo.sdkApiVersion >= 18 ? result.errorReasons?.[index] : undefined;
      if (index < 0 || reason === PermissionRequestReason.INVALID || reason === PermissionRequestReason.UNDECLARED) {
        throw new ExpoAudioError('ERR_AUDIO_PERMISSION_REQUEST', 'Declare the microphone permission in module.json5 before requesting it.');
      }
      const granted = result.authResults[index] === ExpoPermissionStatus.GRANTED;
      blocked = !granted && (reason === PermissionRequestReason.CANNOT_REQUEST || reason === PermissionRequestReason.MANUAL_SETTINGS);
      if (granted || blocked || result.dialogShownResults?.[index] === true) denied = !granted;
    }
    if (deviceInfo.sdkApiVersion < 20 && denied !== undefined) {
      try {
        const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PERMISSION_PREFERENCES });
        await store.put(MICROPHONE_DENIED, denied);
        await store.flush();
      } catch (_) {}
    }
    const response = await this.getRecordingPermission();
    return blocked && !response.granted ? new PermissionRecord('denied', false) : response;
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

    if (this.canContinueInBackground(BACKGROUND_PLAYBACK_MODE) && this.hasActivePlayback()) modes.push(BACKGROUND_PLAYBACK_MODE);
    if (
      this.canContinueInBackground(BACKGROUND_RECORDING_MODE) &&
      (Array.from(this.recorders.values()).some((recorder: AudioRecorderController): boolean => recorder.recording) ||
        Array.from(this.streams.values()).some((stream: ExpoAudioStream): boolean => stream.isStreaming))
    ) {
      modes.push(BACKGROUND_RECORDING_MODE);
    }

    return modes;
  }

  private canContinueInBackground(mode: string): boolean {
    const enabled = mode === BACKGROUND_PLAYBACK_MODE ? this.mode.shouldPlayInBackground : this.mode.allowsBackgroundRecording;
    return enabled === true && !this.canceledBackgroundModes.has(mode);
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

    if (deviceInfo.sdkApiVersion >= 21) {
      const hadPlayback = this.backgroundTaskIds.has(BACKGROUND_PLAYBACK_MODE);
      await this.syncScopedBackgroundTasks(modes);
      if (hadPlayback && !modes.includes(BACKGROUND_PLAYBACK_MODE) && this.lockScreenPlayer === undefined) this.clearMediaSession();
      return;
    }

    let mediaSessionError: Error | undefined;
    if (modes.includes(BACKGROUND_PLAYBACK_MODE)) {
      try {
        await this.ensureBackgroundMediaSession();
      } catch (error) {
        this.suspendUnavailableBackgroundMode(BACKGROUND_PLAYBACK_MODE);
        modes.splice(modes.indexOf(BACKGROUND_PLAYBACK_MODE), 1);
        mediaSessionError = error as Error;
      }
    }
    await this.syncLegacyBackgroundTask(modes);
    if (mediaSessionError !== undefined) throw mediaSessionError;
  }

  private async syncLegacyBackgroundTask(modes: string[]): Promise<void> {
    if (this.sameBackgroundModes(modes)) return;

    if (modes.length === 0) {
      await this.stopBackgroundTaskNow();

      return;
    }

    try {
      if (this.backgroundModes.length > 0) {
        await backgroundTaskManager.updateBackgroundRunning(this.context.uiAbilityContext, modes);
      } else {
        await backgroundTaskManager.startBackgroundRunning(this.context.uiAbilityContext, modes, await this.createBackgroundWantAgent());
      }
    } catch (error) {
      for (const mode of modes) {
        if (!this.backgroundModes.includes(mode)) this.suspendUnavailableBackgroundMode(mode);
      }

      throw error as Error;
    }

    this.backgroundModes = modes;
    if (!modes.includes(BACKGROUND_PLAYBACK_MODE) && this.lockScreenPlayer === undefined) this.clearMediaSession();
  }

  private createBackgroundWantAgent(): Promise<WantAgent> {
    const ability = this.context.uiAbilityContext.abilityInfo;
    return wantAgent.getWantAgent({
      wants: [{ bundleName: ability.bundleName, moduleName: ability.moduleName, abilityName: ability.name }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    });
  }

  private async syncScopedBackgroundTasks(modes: string[]): Promise<void> {
    if (deviceInfo.sdkApiVersion < 21) return;

    let failure: Error | undefined;
    for (const entry of this.backgroundTaskIds) {
      const mode = entry[0];
      if (modes.includes(mode)) continue;
      try {
        await this.stopScopedBackgroundTask(mode, entry[1]);
      } catch (error) {
        failure ??= error as Error;
      }
    }

    for (const mode of modes) {
      try {
        if (mode === BACKGROUND_PLAYBACK_MODE) await this.ensureBackgroundMediaSession();
        if (!this.backgroundTaskIds.has(mode)) await this.startScopedBackgroundTask(mode);
      } catch (error) {
        this.suspendUnavailableBackgroundMode(mode);
        failure ??= error as Error;
      }
    }

    if (failure !== undefined) throw failure;
  }

  private async startScopedBackgroundTask(mode: string): Promise<void> {
    if (!this.listeningForBackgroundCancellation) {
      backgroundTaskManager.on('continuousTaskCancel', this.onBackgroundTaskCanceled);
      this.listeningForBackgroundCancellation = true;
    }

    const playback = mode === BACKGROUND_PLAYBACK_MODE;
    const request = new backgroundTaskManager.ContinuousTaskRequest();
    request.backgroundTaskModes = [playback
      ? backgroundTaskManager.BackgroundTaskMode.MODE_AUDIO_PLAYBACK
      : backgroundTaskManager.BackgroundTaskMode.MODE_AUDIO_RECORDING];
    request.backgroundTaskSubmodes = [playback
      ? backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_AVSESSION_AUDIO_PLAYBACK
      : backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_AUDIO_RECORD_NORMAL_NOTIFICATION];
    request.wantAgent = await this.createBackgroundWantAgent();

    const task = await backgroundTaskManager.startBackgroundRunning(this.context.uiAbilityContext, request);
    if (task.continuousTaskId === undefined || task.continuousTaskId < 0) {
      throw new ExpoAudioError('ERR_AUDIO_BACKGROUND_TASK', 'The system did not return an audio background task ID.');
    }

    this.backgroundTaskIds.set(mode, task.continuousTaskId);
  }

  private async stopScopedBackgroundTask(mode: string, taskId: number): Promise<void> {
    const context = this.context.uiAbilityContext;
    this.stoppingBackgroundTasks.add(taskId);
    try {
      await backgroundTaskManager.stopBackgroundRunning(context, taskId);
    } catch (error) {
      const active = await backgroundTaskManager.getAllContinuousTasks(context, true);
      if (active.some((task): boolean => task.continuousTaskId === taskId)) throw error as Error;
    } finally {
      this.stoppingBackgroundTasks.delete(taskId);
    }
    this.backgroundTaskIds.delete(mode);
  }

  private async stopBackgroundTask(): Promise<void> {
    await this.queueBackgroundTaskSync().catch((error: Object): void => {
      console.error(`Expo Audio background task cleanup failed: ${cleanError(error)}`);
    });
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
    await this.queueMediaSessionOperation(async (): Promise<void> => {
      if (this.destroyed || !this.inBackground || this.mode.shouldPlayInBackground !== true) return;

      const controller = this.activePlaybackController();
      if (controller === undefined) return;

      const lockScreen = controller === this.lockScreenPlayer;
      const options = lockScreen ? this.lockScreenOptions : undefined;
      const metadata = lockScreen ? this.lockScreenMetadata : undefined;
      const previous = this.sessionController;
      const session = await this.ensureMediaSessionNow(controller, options);
      if (!lockScreen || previous !== controller) await this.setMediaSessionMetadata(session, controller, metadata, options);
      await session.setAVPlaybackState(this.mediaPlaybackState(controller), controller.playing ? 1 : 0);
      if (this.destroyed || !this.inBackground) return;

      await this.activateMediaSession(session, controller);
    });
  }

  private async onBackground(): Promise<void> {
    if (this.destroyed) return;

    this.inBackground = true;
    this.suspendDisallowedBackgroundAudio();

    await this.queueBackgroundTaskSync();
  }

  private suspendDisallowedBackgroundAudio(): void {
    if (this.mode.shouldPlayInBackground !== true) this.suspendBackgroundMode(BACKGROUND_PLAYBACK_MODE);
    if (this.mode.allowsBackgroundRecording !== true) this.suspendBackgroundMode(BACKGROUND_RECORDING_MODE);
  }

  private suspendUnavailableBackgroundMode(mode: string): void {
    if (!this.inBackground || this.destroyed) return;

    this.canceledBackgroundModes.add(mode);
    this.suspendBackgroundMode(mode);
    if (mode === BACKGROUND_PLAYBACK_MODE && this.lockScreenPlayer === undefined) this.clearMediaSession();
  }

  private suspendBackgroundMode(mode: string): void {
    if (mode === BACKGROUND_PLAYBACK_MODE) {
      this.players.forEach((player: AudioPlayerController): void => player.suspendForBackground());
      this.playlists.forEach((playlist: PlaylistController): void => playlist.suspendForBackground());
    } else {
      this.streams.forEach((stream: ExpoAudioStream): void => stream.stop());
      this.recorders.forEach((recorder: AudioRecorderController): void => recorder.suspendForBackground());
    }
  }

  private async onForeground(): Promise<void> {
    if (this.destroyed) return;

    this.inBackground = false;
    this.canceledBackgroundModes.clear();

    await this.stopBackgroundTask();

    if (this.lockScreenPlayer === undefined) this.clearMediaSession();
    else if (this.sessionController !== this.lockScreenPlayer) {
      this.updateLockScreenMetadata(this.lockScreenPlayer, this.lockScreenMetadata);
    }

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

  private queueMediaSessionOperation(operation: () => Promise<void>): Promise<void> {
    const next = this.mediaSessionTail.then(operation);
    this.mediaSessionTail = next.catch((): void => {});
    return next;
  }

  private async ensureMediaSessionNow(controller: PlaybackController, options?: LockScreenOptionsInput): Promise<ExpoAVSessionClient> {
    let session = this.lockScreenSession;

    if (session === undefined) {
      session = new ExpoAVSessionClient(this.context.uiAbilityContext, { name: 'ExpoAudio', type: 'audio' });
      this.lockScreenSession = session;
    }
    if (this.sessionController === controller && this.sessionOptions === options) return session;

    const controls: ExpoAVSessionControls = {
      play: (): void => controller.play(),
      pause: (): void => controller.pause(),
    };

    if (options?.isLiveStream !== true) {
      controls.seek = (time: number): void => {
        controller.seekTo(time / 1000).catch((): void => {});
      };
    }

    if (options?.isLiveStream !== true && options?.showSeekForward === true) {
      controls.fastForward = (time?: number): void => {
        const offset = time ?? SEEK_STEP_MS;

        controller.seekTo(controller.currentTimeSeconds + offset / 1000).catch((): void => {});
      };
    }

    if (options?.isLiveStream !== true && options?.showSeekBackward === true) {
      controls.rewind = (time?: number): void => {
        const offset = time ?? SEEK_STEP_MS;

        controller.seekTo(Math.max(0, controller.currentTimeSeconds - offset / 1000)).catch((): void => {});
      };
    }

    await session.setControls(controls);
    if (this.sessionController !== controller) this.sessionNeedsActivation = true;
    this.sessionController = controller;
    this.sessionOptions = options;

    return session;
  }

  private async activateMediaSession(session: ExpoAVSessionClient, controller: PlaybackController): Promise<void> {
    const request = controller === this.lockScreenPlayer ? this.requestedLockScreenActivation : this.publishedLockScreenActivation;
    if (!this.sessionNeedsActivation && request === this.publishedLockScreenActivation) return;

    await session.activate();
    this.sessionNeedsActivation = false;
    this.publishedLockScreenActivation = request;
  }

  private mediaPlaybackState(controller: PlaybackController): avSession.AVPlaybackState {
    return {
      state: controller.playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      speed: controller.playing ? controller.playbackRate : 0,
      position: {
        elapsedTime: Math.round(controller.currentTimeSeconds * 1000),
        updateTime: Date.now(),
      },
      duration: controller === this.lockScreenPlayer && this.lockScreenOptions?.isLiveStream === true ? undefined : Math.round(controller.durationSeconds * 1000),
      muted: controller.muted,
      volume: controller.volume,
    };
  }

  private updateMediaPlaybackState(controller: PlaybackController): void {
    const session = this.lockScreenSession;

    if (session === undefined || this.sessionController !== controller) return;

    session.setAVPlaybackState(this.mediaPlaybackState(controller), controller.playing ? 1 : 0).catch((error: Object): void => {
      console.error(`Expo Audio lock-screen state update failed: ${cleanError(error)}`);
    });
  }

  private clearMediaSession(): void {
    this.lockScreenGeneration += 1;
    this.sessionController = undefined;
    this.queueMediaSessionOperation(async (): Promise<void> => {
      const session = this.lockScreenSession;
      this.lockScreenSession = undefined;
      this.sessionController = undefined;
      this.sessionOptions = undefined;
      this.sessionNeedsActivation = false;
      if (session === undefined) return;
      await session.destroy();
    }).catch((error: Object): void => {
      console.error(`Expo Audio lock-screen teardown failed: ${cleanError(error)}`);
    });
  }
}

abstract class ExpoAudioSharedObject extends ExpoSharedObject implements AudioObjectEventSink {
  emit(eventName: string, payload: ESObject): void {
    this.sendEvent(eventName, payload);
  }
}

interface AudioStreamOptionsInput {
  sampleRate: number;
  channels: number;
  encoding: string;
}

function readAudioStreamOptions(value: ESObject): AudioStreamOptionsInput {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoAudioError('ERR_AUDIO_STREAM_OPTIONS', 'Audio stream options must be an object.');
  }
  const input = value as Record<string, ESObject>;
  const sampleRate: number = input.sampleRate === undefined ? 48000 : input.sampleRate as number;
  const channels: number = input.channels === undefined ? 1 : input.channels as number;
  const encoding: string = input.encoding === undefined ? 'float32' : input.encoding as string;
  if (typeof sampleRate !== 'number' || !Number.isSafeInteger(sampleRate) || sampleRate <= 0) {
    throw new ExpoAudioError('ERR_AUDIO_STREAM_OPTIONS', 'The stream sample rate must be a positive integer.');
  }
  if (channels !== 1 && channels !== 2) {
    throw new ExpoAudioError('ERR_AUDIO_STREAM_OPTIONS', 'The stream channel count must be 1 or 2.');
  }
  if (encoding !== 'float32' && encoding !== 'int16') {
    throw new ExpoAudioError('ERR_AUDIO_STREAM_OPTIONS', 'The stream encoding must be float32 or int16.');
  }

  return { sampleRate, channels: channels as number, encoding: encoding as string };
}

class ExpoAudioStream extends ExpoAudioSharedObject {
  readonly id: string;
  sampleRate: number = 0;
  channels: number = 0;
  isStreaming: boolean = false;
  private readonly objectId: number;
  private readonly runtime: ExpoAudioRuntime;
  private readonly options: AudioStreamOptionsInput;
  private capturer?: audio.AudioCapturer;
  private tail: Promise<void> = Promise.resolve();
  private generation: number = 0;
  private destroyed: boolean = false;
  private startedAtMs: number = 0;

  constructor(context: ExpoModuleContext, runtime: ExpoAudioRuntime, options: AudioStreamOptionsInput) {
    super(context);
    this.runtime = runtime;
    this.options = options;
    this.objectId = runtime.registerStream(this);
    this.id = `expo-audio-stream-${this.objectId}`;
  }

  start(): Promise<void> {
    const generation = this.generation;
    return this.enqueue(async (): Promise<void> => {
      if (this.destroyed) throw new ExpoAudioError('ERR_AUDIO_STREAM_RELEASED', 'The audio stream was released.');
      if (generation !== this.generation || this.isStreaming) return;

      this.runtime.ensureRecordingAvailable();

      let capturer: audio.AudioCapturer | undefined;
      try {
        // S16LE is the portable capture format; float32 support is hardware-dependent.
        capturer = await audio.createAudioCapturer({
          streamInfo: {
            samplingRate: this.options.sampleRate as audio.AudioSamplingRate,
            channels: this.options.channels as audio.AudioChannel,
            sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
            encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
          },
          capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 },
        });
        if (generation !== this.generation || this.destroyed) {
          await capturer.release();
          return;
        }
        this.capturer = capturer;
        const info = capturer.getStreamInfoSync();
        this.sampleRate = info.samplingRate;
        this.channels = info.channels;
        const current = capturer;
        capturer.on('readData', (buffer: ArrayBuffer): void => {
          if (this.capturer !== current || !this.isStreaming || generation !== this.generation) return;
          this.emitBuffer(buffer);
        });
        capturer.on('audioInterrupt', (event: audio.InterruptEvent): void => {
          if (this.capturer !== current) return;
          if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP || event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) this.stop();
        });
        capturer.on('stateChange', (state: audio.AudioState): void => {
          if (this.capturer !== current || !this.isStreaming) return;
          if (state === audio.AudioState.STATE_STOPPED || state === audio.AudioState.STATE_RELEASED) this.stop();
        });
        await capturer.start();
        if (generation !== this.generation || this.destroyed) {
          await this.releaseCapturer();
          return;
        }
        this.startedAtMs = uptimeMilliseconds();
        this.isStreaming = true;
        this.emitStatus();
        this.runtime.recordingStateChanged();
      } catch (error) {
        if (this.capturer === capturer) await this.releaseCapturer();
        else if (capturer !== undefined && capturer.state !== audio.AudioState.STATE_RELEASED) {
          try { await capturer.release(); } catch (_) {}
        }
        throw new ExpoAudioError('ERR_AUDIO_STREAM_START', cleanError(error as Object));
      }
    });
  }

  stop(): void {
    this.generation += 1;
    if (this.isStreaming) {
      this.isStreaming = false;
      if (!this.destroyed) this.emitStatus();
      this.runtime.recordingStateChanged();
    }
    this.enqueue(async (): Promise<void> => this.releaseCapturer()).catch((error: Object): void => {
      console.error(`Expo Audio stream cleanup failed: ${cleanError(error)}`);
    });
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.stop();
    this.runtime.releaseStream(this.objectId);
  }

  override sharedObjectWillRelease(): void {
    this.destroy();
  }

  async waitForIdle(): Promise<void> {
    await this.tail;
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.tail.catch((): void => {}).then(operation);
    this.tail = next.catch((): void => {});
    return next;
  }

  private async releaseCapturer(): Promise<void> {
    const capturer = this.capturer;
    this.capturer = undefined;
    if (capturer === undefined) return;
    try {
      capturer.off('readData');
      capturer.off('audioInterrupt');
      capturer.off('stateChange');
      if (capturer.state === audio.AudioState.STATE_RUNNING) await capturer.stop();
    } finally {
      if (capturer.state !== audio.AudioState.STATE_RELEASED) await capturer.release();
    }
  }

  private emitStatus(): void {
    this.emit(STREAM_STATUS_EVENT, { isStreaming: this.isStreaming });
  }

  private emitBuffer(buffer: ArrayBuffer): void {
    let data: ArrayBuffer;
    if (this.options.encoding === 'float32') {
      const samples = new Int16Array(buffer);
      const floats = new Float32Array(samples.length);

      for (let i = 0; i < samples.length; i += 1) floats[i] = samples[i] / PCM_16_BIT_NORMALIZER;
      data = floats.buffer as ArrayBuffer;
    } else {
      // AudioCapturer can reuse this buffer before the asynchronous JS event is delivered.
      data = buffer.slice(0);
    }

    this.emit(STREAM_BUFFER_EVENT, {
      data,
      sampleRate: this.sampleRate,
      channels: this.channels,
      timestamp: (uptimeMilliseconds() - this.startedAtMs) / 1000,
    });
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
  if (typeof input.playsInSilentMode === 'boolean') mode.playsInSilentMode = input.playsInSilentMode;
  if (typeof input.shouldPlayInBackground === 'boolean') mode.shouldPlayInBackground = input.shouldPlayInBackground;
  if (typeof input.shouldRouteThroughEarpiece === 'boolean') mode.shouldRouteThroughEarpiece = input.shouldRouteThroughEarpiece;
  if (typeof input.allowsBackgroundRecording === 'boolean') mode.allowsBackgroundRecording = input.allowsBackgroundRecording;
  if (typeof input.interruptionMode === 'string') mode.interruptionMode = input.interruptionMode;

  return mode;
}

const AUDIO_STREAM_OPTIONS_TYPE: ExpoValueType<AudioStreamOptionsInput> = audioInputType<AudioStreamOptionsInput>(
  'audio stream options',
  (value: ESObject): AudioStreamOptionsInput => readAudioStreamOptions(value),
);
const AUDIO_STREAM_BUFFER_TYPE: ExpoValueType<Record<string, ESObject>> = ExpoValueTypes.shapedRecord<Record<string, ESObject>>(
  'AudioStreamBuffer',
  new ExpoRecordShape()
    .field('data', ExpoValueTypes.arrayBuffer(), { required: true })
    .field('sampleRate', ExpoValueTypes.number(), { required: true })
    .field('channels', ExpoValueTypes.number(), { required: true })
    .field('timestamp', ExpoValueTypes.number(), { required: true }),
  (fields: Record<string, ESObject>): Record<string, ESObject> => fields,
  (fields: Record<string, ESObject>): Record<string, ESObject> => fields,
);

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

    const streamClass = new ExpoSharedObjectClassDefinition<ExpoAudioStream>(STREAM_CLASS_NAME)
      .construct(ExpoFunction.ownedTyped1(
        AUDIO_STREAM_OPTIONS_TYPE,
        (context: ExpoModuleContext, options: AudioStreamOptionsInput): ExpoAudioStream => new ExpoAudioStream(context, this.runtime, options),
      ))
      .event(STREAM_BUFFER_EVENT, AUDIO_STREAM_BUFFER_TYPE)
      .events([STREAM_STATUS_EVENT])
      .property('id', ExpoValueTypes.string(), (object: ExpoAudioStream): string => object.id)
      .property('sampleRate', ExpoValueTypes.number(), (object: ExpoAudioStream): number => object.sampleRate)
      .property('channels', ExpoValueTypes.number(), (object: ExpoAudioStream): number => object.channels)
      .property('isStreaming', ExpoValueTypes.boolean(), (object: ExpoAudioStream): boolean => object.isStreaming)
      .asyncFunction('start', async (object: ExpoAudioStream): Promise<void> => await object.start())
      .syncFunction('stop', (object: ExpoAudioStream): void => object.stop());

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
      .sharedObjectClass(streamClass)
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
      .asyncFunction('getRecordingPermissionsAsync', async (): Promise<PermissionRecord> => await this.runtime.getRecordingPermission())
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
