/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoModuleError, ExpoSharedObject } from '@expo-harmony/expo-modules-core';
import { VideoAudioParticipant, VideoAudioSession } from './VideoAudioSession';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { isLocalHlsPlaylist, isRemote, normalizeUri, openVideoFile, requireFinite, validateSource, VideoFile, VideoSource } from './VideoSource';
import { generateThumbnails, ThumbnailOptions, VideoThumbnail } from './VideoThumbnail';
import { getVideoRanges, VideoRange } from './VideoRange';

const LOAD_TIMEOUT_MS: number = 30_000;
const MIN_BUFFER_SECONDS: number = 1;
const MAX_BUFFER_SECONDS: number = 20;
const INITIAL_CLEANUP_DELAY_MS: number = 250;
const MAX_CLEANUP_DELAY_MS: number = 30_000;
const MAX_TIMER_MS: number = 2_147_483_647;
const MIN_PLAYBACK_RATE: number = 0.125;
const MAX_PLAYBACK_RATE: number = 4;
const DUCKED_VOLUME_MULTIPLIER: number = 0.5;
export type PlayerStatus = 'idle' | 'loading' | 'readyToPlay' | 'error';
export interface BufferOptions {
  preferredForwardBufferDuration?: number;
  waitsToMinimizeStalling?: boolean;
  minBufferForPlayback?: number;
  maxBufferBytes?: number | null;
  prioritizeTimeOverSizeThreshold?: boolean;
}

export interface SeekTolerance {
  toleranceBefore?: number;
  toleranceAfter?: number;
}

export interface PlayerBuilderOptions {
  seekBackwardIncrement?: number;
  seekForwardIncrement?: number;
}

export interface MediaTrack {
  id: string;
  language: string;
  label: string;
  name?: string;
}

export interface VideoSize {
  width: number;
  height: number;
}

export interface VideoTrack {
  id: string;
  url: string | null;
  size: VideoSize;
  mimeType: string | null;
  isSupported: boolean;
  bitrate: number | null;
  averageBitrate: number | null;
  peakBitrate: number | null;
  frameRate: number | null;
  videoRange: VideoRange;
}

export interface VideoObserver {
  update(): void;
  firstFrame(): void;
}

class VideoLoad {
  player?: media.AVPlayer;
  file?: VideoFile;
  surface?: string;
  sourceInitialized: boolean = false;
  prepared: boolean = false;
  preparing: boolean = false;
  sourceLoaded: boolean = false;
  buffering: boolean = false;
  firstFrameRendered: boolean = false;
  videoRanges: Promise<Record<string, VideoRange>> = Promise.resolve<Record<string, VideoRange>>({});
  nativeError?: Error;
  disposal?: Promise<void>;
  disposed: boolean = false;
  initialized?: () => void;
  cancel?: (error: Error) => void;
  tail: Promise<void> = Promise.resolve();
}

export class VideoPlayer extends ExpoSharedObject implements VideoAudioParticipant {
  source: VideoSource | null = null;
  status: PlayerStatus = 'idle';
  playing: boolean = false;
  muted: boolean = false;
  volume: number = 1;
  loop: boolean = false;
  playbackRate: number = 1;
  currentTime: number = 0;
  duration: number = 0;
  isLive: boolean = false;
  bufferedPosition: number = -1;
  timeUpdateEventInterval: number = 0;
  keepScreenOnWhilePlaying: boolean = true;
  showNowPlayingNotification: boolean = false;
  staysActiveInBackground: boolean = false;
  audioMixingMode: string = 'auto';
  bufferOptions: BufferOptions = {};
  seekTolerance: SeekTolerance = {};
  availableAudioTracks: MediaTrack[] = [];
  availableSubtitleTracks: MediaTrack[] = [];
  availableVideoTracks: VideoTrack[] = [];
  audioTrack: MediaTrack | null = null;
  subtitleTrack: MediaTrack | null = null;
  videoTrack: VideoTrack | null = null;
  width: number = 0;
  height: number = 0;
  subtitle: string = '';
  readonly seekBackwardIncrement: number;
  readonly seekForwardIncrement: number;
  private load?: VideoLoad;
  private released: boolean = false;
  private intendedPlaying: boolean = false;
  private backgrounded: boolean = false;
  private pictureInPictureActive: boolean = false;
  private backgroundPlaybackAllowed: boolean = false;
  private interrupted: boolean = false;
  private ducked: boolean = false;
  private audioDisabled: boolean = false;
  private subtitlesDisabled: boolean = true;
  private pendingSeek?: number;
  private surface?: string;
  private owner?: VideoObserver;
  private observers: Set<VideoObserver> = new Set<VideoObserver>();
  private interval?: number;
  private readonly retired: Set<VideoLoad> = new Set<VideoLoad>();
  private cleanupTimer?: number;
  private cleanupDelay: number = INITIAL_CLEANUP_DELAY_MS;
  private subtitleEnd: number = 0;

  private readonly session: VideoAudioSession;
  private readonly onRelease: (player: VideoPlayer) => void;
  private readonly onUpdate?: () => void;

  constructor(
    context: ExpoModuleContext,
    source: VideoSource | null,
    options: PlayerBuilderOptions,
    session: VideoAudioSession,
    onRelease: (player: VideoPlayer) => void,
    onUpdate?: () => void,
  ) {
    super(context);
    this.onRelease = onRelease;
    this.onUpdate = onUpdate;
    this.session = session;

    validateSource(source);
    this.seekBackwardIncrement = requireFinite(options.seekBackwardIncrement ?? 10, 'seekBackwardIncrement', 0.001);
    this.seekForwardIncrement = requireFinite(options.seekForwardIncrement ?? 10, 'seekForwardIncrement', 0.001);

    this.session.add(this);

    // Constructors run before SharedObject binding; defer the first native event.
    Promise.resolve().then((): void => {
      if (!this.released && this.load === undefined) this.replace(source);
    });
  }

  private active(load: VideoLoad): boolean {
    return !this.released && !load.disposed && this.load === load;
  }

  private emit(name: string, payload?: ESObject): void {
    if (!this.released && this.currentBinding() !== undefined && this.context.isValid) {
      if (payload === undefined) this.sendEvent(name);
      else this.sendEvent(name, payload);
    }
  }

  private notify(): void {
    this.observers.forEach((observer: VideoObserver): void => observer.update());
    this.onUpdate?.();
  }

  addObserver(observer: VideoObserver): void {
    this.observers.add(observer);
  }

  removeObserver(observer: VideoObserver): void {
    this.observers.delete(observer);
  }

  private setStatus(status: PlayerStatus, error?: Error): void {
    const oldStatus = this.status;
    this.status = status;

    if (oldStatus !== status || error !== undefined) {
      if (error) {
        const detail: Record<string, string> = {};
        detail['message'] = error.message;
        this.emit('statusChange', { status, oldStatus, error: detail });
      } else this.emit('statusChange', { status, oldStatus });
    }

    this.notify();
  }

  private setPlaying(value: boolean): void {
    if (value === this.playing) return;

    const oldIsPlaying = this.playing;
    this.playing = value;
    this.emit('playingChange', { isPlaying: value, oldIsPlaying });
    this.notify();
  }

  private fail(load: VideoLoad, error: Error): void {
    if (!this.active(load)) return;

    load.cancel?.(error);
    load.firstFrameRendered = false;
    this.setPlaying(false);
    this.releaseAudioFocus();
    this.setStatus('error', error);

    void this.dispose(load);
  }

  private schedule(load: VideoLoad, operation: (player: media.AVPlayer) => Promise<void>): void {
    const next = load.tail.then(async (): Promise<void> => {
      if (this.active(load) && load.player !== undefined) await operation(load.player);
    });
    load.tail = next.catch((error: Error): void => this.fail(load, error));
  }

  replace(source: VideoSource | null): void {
    validateSource(source);
    this.replaceAsync(source).catch((): void => {});
  }

  async replaceAsync(source: VideoSource | null): Promise<void> {
    validateSource(source);
    if (this.released) throw new ExpoModuleError('ERR_VIDEO_RELEASED', 'The video player has been released.');
    if (source?.uri === undefined) source = null;

    const oldSource = this.source;
    const previous = this.load;
    const load = new VideoLoad();

    this.load = load;
    this.source = source;
    this.releaseAudioFocus();

    if (previous !== undefined) this.pendingSeek = undefined;
    this.currentTime = 0;
    this.duration = 0;
    this.isLive = false;
    this.bufferedPosition = source === null ? -1 : 0;
    this.interrupted = false;
    this.ducked = false;
    this.width = 0;
    this.height = 0;
    this.subtitle = '';

    this.resetTracks();
    this.setPlaying(false);
    this.setStatus(source === null ? 'idle' : 'loading');
    this.emit('sourceChange', { source, oldSource });

    if (previous) void this.dispose(previous);
    if (source === null) return;

    await this.initialize(load, source);
  }

  private async initialize(load: VideoLoad, source: VideoSource): Promise<void> {
    const cancelled = new Promise<void>((_resolve, reject): void => {
      load.cancel = (error: Error): void => reject(error);
    });

    try {
      await withLoadTimeout(
        Promise.race([this.initializeSource(load, source), cancelled]),
        'Video source initialization timed out.',
      );
      if (!this.active(load)) throw new ExpoModuleError('ERR_VIDEO_LOAD_CANCELLED', 'Video loading was cancelled.');

      load.sourceInitialized = true;
      this.prepareIfAttached(load);
    } catch (error) {
      this.fail(load, error as Error);
      void this.dispose(load);

      throw new ExpoModuleError(
        error instanceof ExpoModuleError ? error.code : 'ERR_VIDEO_LOAD',
        error instanceof Error ? error.message : String(error),
        error as Object,
      );
    } finally {
      load.cancel = undefined;
      load.initialized?.();
      load.initialized = undefined;
    }
  }

  private async initializeSource(load: VideoLoad, source: VideoSource): Promise<void> {
    const player = await media.createAVPlayer();
    load.player = player;
    if (!this.active(load)) {
      void this.dispose(load);
      return;
    }

    this.listen(load, player);
    const ready = new Promise<void>((resolve): void => {
      load.initialized = resolve;
    });
    if (isRemote(source.uri!)) {
      await Promise.all([player.setMediaSource(media.createMediaSourceWithUrl(normalizeUri(source.uri!), source.headers)), ready]);
    } else {
      load.file = openVideoFile(this.context, source.uri!);
      const descriptor = load.file.descriptor;
      if (isLocalHlsPlaylist(source)) {
        const url = `fd://${descriptor.fd}?offset=${descriptor.offset ?? 0}&size=${descriptor.length ?? 0}`;
        const mediaSource = media.createMediaSourceWithUrl(url, source.headers);
        mediaSource.setMimeType(media.AVMimeTypes.APPLICATION_M3U8);
        await Promise.all([player.setMediaSource(mediaSource), ready]);
      } else {
        load.videoRanges = getVideoRanges(this.context, source);
        player.fdSrc = descriptor;
        await ready;
      }
    }

    if (this.active(load)) player.audioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_MOVIE, rendererFlags: 0 };
  }

  claimView(owner: VideoObserver): void {
    if (this.released) throw new ExpoModuleError('ERR_VIDEO_RELEASED', 'The video player has been released.');
    if (this.owner !== undefined && this.owner !== owner) {
      throw new ExpoModuleError('ERR_VIDEO_SURFACE_IN_USE', 'A HarmonyOS VideoPlayer can be attached to only one VideoView at a time.');
    }

    this.owner = owner;
  }

  releaseView(owner: VideoObserver): void {
    if (this.owner !== owner) return;
    if (this.surface !== undefined) this.detachSurface(owner, this.surface);
    this.owner = undefined;
  }

  attachSurface(owner: VideoObserver, surface: string): void {
    if (this.owner !== owner || this.surface === surface) return;

    const previous = this.surface;
    this.surface = surface;

    const load = this.load;
    if (!load) return;

    if (load.preparing && previous !== surface) {
      this.restartPreparation(load);
      return;
    }

    if (load.prepared && load.player) {
      this.schedule(load, async (player: media.AVPlayer): Promise<void> => {
        if (this.surface !== surface) return;

        player.surfaceId = surface;
        load.surface = surface;
      });
      this.reconcilePlayback();
    } else this.prepareIfAttached(load);
  }

  detachSurface(owner: VideoObserver, surface: string): void {
    if (this.owner !== owner || this.surface !== surface) return;

    this.surface = undefined;
    this.notify();

    // Preserve play intent for reattachment. A preparing decoder must stop rendering its first
    // frame into the outgoing surface; AVPlayer does not document an empty/null surface setter.
    const load = this.load;
    if (load?.preparing) this.restartPreparation(load);
    else this.reconcilePlayback();
  }

  private restartPreparation(previous: VideoLoad): void {
    if (this.released || this.load !== previous || this.source === null) return;

    const load = new VideoLoad();

    this.load = load;
    this.setPlaying(false);
    this.setStatus('loading');
    this.releaseAudioFocus();
    void this.dispose(previous);
    this.initialize(load, this.source).catch((): void => {});
  }

  private prepareIfAttached(load: VideoLoad): void {
    if (!this.active(load) || !load.sourceInitialized || load.preparing || load.prepared || !this.surface ||
        load.player?.state !== 'initialized') return;

    load.preparing = true;
    this.schedule(load, async (player: media.AVPlayer): Promise<void> => {
      const surface = this.surface;
      if (!surface) {
        load.preparing = false;
        return;
      }

      // Let the retiring decoder stop writing to this surface before a replacement prepares on it.
      const retiring = Array.from(this.retired).filter((previous: VideoLoad): boolean => previous.surface === surface);
      if (retiring.length > 0) {
        await withLoadTimeout(
          Promise.all(retiring.map((previous: VideoLoad): Promise<void> => this.dispose(previous))),
          'Previous video surface release timed out.',
        );
        if (!this.active(load)) return;
        if (retiring.some((previous: VideoLoad): boolean => previous.player !== undefined)) {
          throw new ExpoModuleError('ERR_VIDEO_PLAYBACK', 'The previous video surface could not be released.');
        }
      }

      const strategy: media.PlaybackStrategy = { showFirstFrameOnPrepare: true };
      if ((this.bufferOptions.preferredForwardBufferDuration ?? 0) > 0) {
        strategy.preferredBufferDuration = this.bufferOptions.preferredForwardBufferDuration;
      }
      await player.setPlaybackStrategy(strategy);
      if (!this.active(load) || !this.surface) {
        load.preparing = false;
        return;
      }

      player.surfaceId = surface;
      load.surface = surface;
      await withLoadTimeout(player.prepare(), 'Video preparation timed out.');
      if (!this.active(load)) return;

      load.prepared = true;
      load.preparing = false;
      this.updateDuration(player.duration);
      this.width = finiteNonnegative(player.width) ?? 0;
      this.height = finiteNonnegative(player.height) ?? 0;

      if (!this.isLive) player.loop = this.loop;
      this.applyVolume(player);
      await player.setMediaMuted(media.MediaType.MEDIA_TYPE_AUD, this.audioDisabled);
      if (!this.active(load)) return;
      if (!this.isLive) player.setPlaybackRate(this.playbackRate);
      if (this.pendingSeek !== undefined) this.performSeek(player, this.pendingSeek);

      await this.updateTracks(load, player);
      if (!this.active(load)) return;

      load.sourceLoaded = true;
      this.setStatus(load.buffering ? 'loading' : 'readyToPlay');
      this.emit('sourceLoad', {
        videoSource: this.source,
        duration: this.duration,
        availableVideoTracks: this.availableVideoTracks,
        availableAudioTracks: this.availableAudioTracks,
        availableSubtitleTracks: this.availableSubtitleTracks,
      });
      this.reconcilePlayback();
    });
  }

  private listen(load: VideoLoad, player: media.AVPlayer): void {
    player.on('error', (error: BusinessError): void => {
      if (!this.active(load)) return;
      load.nativeError = error;
      // Media Kit can report recoverable operation errors without entering its error state.
      if (player.state === 'error') this.fail(load, error);
      else console.warn(`ExpoVideo: native player reported: ${error.message}`);
    });

    player.on('stateChange', (state: media.AVPlayerState): void => {
      if (load.disposed && state === 'released') void this.dispose(load);
      if (!this.active(load)) return;
      if (state === 'initialized') load.initialized?.();
      else if (state === 'error') {
        this.fail(load, load.nativeError ?? (new ExpoModuleError('ERR_VIDEO_PLAYBACK', 'The native video player entered the error state.') as Error));
      } else if (state === 'playing') this.setPlaying(!load.buffering);
      else if (state === 'paused' || state === 'completed') this.setPlaying(false);
    });

    player.on('endOfStream', (): void => {
      if (!this.active(load)) return;

      this.emit('playToEnd');
      if (!this.loop || this.isLive) {
        this.intendedPlaying = false;
        this.releaseAudioFocus();
        this.notify();
      }
    });

    player.on('timeUpdate', (milliseconds: number): void => {
      if (!this.active(load) || !Number.isFinite(milliseconds) || milliseconds < 0) return;

      this.currentTime = milliseconds / 1000;
      if (milliseconds >= this.subtitleEnd) this.subtitle = '';
      this.notify();
    });

    player.on('seekDone', (milliseconds: number): void => {
      if (!this.active(load) || !Number.isFinite(milliseconds) || milliseconds < 0) return;

      this.currentTime = milliseconds / 1000;
      this.notify();
    });

    player.on('durationUpdate', (milliseconds: number): void => {
      if (!this.active(load)) return;

      this.updateDuration(milliseconds);
      this.notify();
    });

    player.on('bufferingUpdate', (kind: media.BufferingInfoType, value: number): void => {
      if (!this.active(load)) return;

      if (kind === media.BufferingInfoType.BUFFERING_START) {
        load.buffering = true;
        this.bufferedPosition = 0;
        this.setPlaying(false);
        if (load.sourceLoaded) this.setStatus('loading');
      }
      if (kind === media.BufferingInfoType.BUFFERING_END) {
        load.buffering = false;
        this.setPlaying(player.state === 'playing');
        if (load.sourceLoaded) this.setStatus('readyToPlay');
      }
      if (kind === media.BufferingInfoType.CACHED_DURATION && !load.buffering && Number.isFinite(value) && value >= 0) {
        this.bufferedPosition = this.currentTime + value / 1000;
        if (!this.isLive && this.duration > 0) this.bufferedPosition = Math.min(this.duration, this.bufferedPosition);
      }
    });

    player.on('videoSizeChange', (width: number, height: number): void => {
      if (!this.active(load)) return;

      this.width = finiteNonnegative(width) ?? 0;
      this.height = finiteNonnegative(height) ?? 0;
      this.notify();
    });

    player.on('startRenderFrame', (): void => {
      if (!this.active(load)) return;
      load.firstFrameRendered = true;
      this.observers.forEach((observer: VideoObserver): void => observer.firstFrame());
    });

    player.on('subtitleUpdate', (info: media.SubtitleInfo): void => {
      if (!this.active(load)) return;

      this.subtitle = this.subtitlesDisabled ? '' : (info.text ?? '');
      this.subtitleEnd = (info.startTime ?? this.currentTime * 1000) + (info.duration ?? 0);
      this.notify();
    });

    player.on('trackChange', (): void => {
      if (this.active(load) && load.prepared) this.schedule(load, async (native: media.AVPlayer): Promise<void> => this.updateTracks(load, native));
    });

    player.on('trackInfoUpdate', (): void => {
      if (this.active(load) && load.prepared) this.schedule(load, async (native: media.AVPlayer): Promise<void> => this.updateTracks(load, native));
    });

    player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (!this.active(load)) return;
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) this.interrupted = true;
      else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) this.interrupted = false;
      else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        this.intendedPlaying = false;
        this.interrupted = false;
        this.notify();
      } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK && event.forceType === audio.InterruptForceType.INTERRUPT_SHARE)
        this.ducked = true;
      else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) this.ducked = false;
      this.schedule(load, async (native: media.AVPlayer): Promise<void> => {
        if (load.prepared) this.applyVolume(native);
      });
      this.reconcilePlayback();
    });
  }

  private updateDuration(milliseconds: number): void {
    if (!Number.isFinite(milliseconds)) return;

    this.duration = Math.max(0, milliseconds / 1000);
    this.isLive = milliseconds < 0;
  }

  play(): void {
    this.interrupted = false;
    this.intendedPlaying = true;
    this.notify();
    this.reconcilePlayback();
  }

  pause(): void {
    this.intendedPlaying = false;
    this.notify();
    this.reconcilePlayback();
  }

  replay(): void {
    this.seek(0);
    this.play();
  }

  seekBy(seconds: number): void {
    requireFinite(seconds, 'seconds', -Number.MAX_VALUE);
    this.seek(this.currentTime + seconds);
  }

  seek(seconds: number): void {
    requireFinite(seconds, 'currentTime', -Number.MAX_VALUE);
    if (this.isLive) throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Seeking a live stream is not supported by expo-video on HarmonyOS.');

    this.pendingSeek = Math.max(0, seconds);
    this.subtitle = '';

    const load = this.load;
    if (load?.prepared)
      this.schedule(load, async (player: media.AVPlayer): Promise<void> => {
        this.performSeek(player, Math.max(0, seconds));
      });
  }

  private performSeek(player: media.AVPlayer, seconds: number): void {
    if (this.isLive) {
      this.pendingSeek = undefined;
      return;
    }

    const target = Math.min(seconds, this.duration);
    player.seek(Math.round(target * 1000), media.SeekMode.SEEK_CLOSEST);
    this.pendingSeek = undefined;
  }

  setBackgrounded(value: boolean): void {
    const returningToForeground = this.backgrounded && !value;
    this.backgrounded = value;
    if (returningToForeground && this.status === 'error' && this.load && this.source !== null) {
      // Like upstream's reloadIfFailed: rebuild the decoder, preserving position and play intent.
      this.pendingSeek = this.isLive ? undefined : this.currentTime;
      this.interrupted = false;
      this.restartPreparation(this.load);
      return;
    }

    this.reconcilePlayback();
  }

  get hasRenderedFrame(): boolean {
    return !this.released && (this.load?.firstFrameRendered ?? false);
  }

  get playbackRequested(): boolean {
    return this.intendedPlaying && !this.released;
  }

  get playbackPrepared(): boolean {
    return this.surface !== undefined && (this.load?.sourceLoaded ?? false);
  }

  get isAvailable(): boolean {
    return !this.released;
  }

  setNowPlayingNotification(enabled: boolean): void {
    this.showNowPlayingNotification = enabled;
    this.notify();
  }

  setStaysActiveInBackground(enabled: boolean): void {
    this.staysActiveInBackground = enabled;
    this.notify();
    this.reconcilePlayback();
  }

  setBackgroundPlaybackAllowed(enabled: boolean): void {
    if (this.backgroundPlaybackAllowed === enabled) return;
    this.backgroundPlaybackAllowed = enabled;
    this.reconcilePlayback();
  }

  setPictureInPictureActive(active: boolean): void {
    if (this.pictureInPictureActive === active) return;
    this.pictureInPictureActive = active;
    this.reconcilePlayback();
  }

  private reconcilePlayback(): void {
    const load = this.load;
    if (!load?.prepared) return;

    this.schedule(load, async (player: media.AVPlayer): Promise<void> => {
      const play = this.shouldPlay();
      if (!play && player.state === 'playing') await player.pause();
      if (!this.active(load) || play !== this.shouldPlay()) return;

      try {
        await this.session.update(this, play, this.interrupted && this.canRequestPlayback());
      } catch (error) {
        if (!this.active(load)) return;
        if (play) this.interrupted = this.intendedPlaying;
        if (player.state === 'playing') await player.pause();
        this.setPlaying(false);
        this.releaseAudioFocus();
        console.warn(`ExpoVideo: audio focus request failed: ${String(error)}`);
        return;
      }

      if (!this.active(load) || play !== this.shouldPlay()) return;
      if (play && ['prepared', 'paused', 'completed'].includes(player.state)) await player.play();
    });
  }

  private shouldPlay(): boolean {
    return !this.interrupted && this.canRequestPlayback();
  }

  private canRequestPlayback(): boolean {
    return this.intendedPlaying && (!this.backgrounded || this.pictureInPictureActive ||
      (this.staysActiveInBackground && this.backgroundPlaybackAllowed)) &&
      this.surface !== undefined;
  }

  audioIsAudible(): boolean {
    return !this.muted && !this.audioDisabled && this.volume > 0 && this.availableAudioTracks.length > 0;
  }

  sessionFocusChanged(hint: audio.AudioSessionStateChangeHint): void {
    if (this.released) return;
    if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE) this.interrupted = this.intendedPlaying;
    else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME) {
      if (!this.interrupted) return;
      this.interrupted = false;
    } else if (
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP ||
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP
    ) {
      this.intendedPlaying = false;
      this.interrupted = false;
      this.notify();
    } else return;

    this.reconcilePlayback();
  }

  private releaseAudioFocus(): void {
    this.session.update(this, false).catch((error: Error): void => console.warn(`ExpoVideo: audio focus release failed: ${error.message}`));
  }

  setMuted(value: boolean): void {
    if (this.muted === value) return;

    const oldMuted = this.muted;
    this.muted = value;
    this.updateVolume();
    this.emit('mutedChange', { muted: value, oldMuted });
  }

  setVolume(value: number): void {
    requireFinite(value, 'volume');
    if (value > 1) throw new ExpoModuleError('ERR_VIDEO_INVALID_ARGUMENT', 'volume must be between 0 and 1.');
    if (this.volume === value) return;

    const oldVolume = this.volume;
    this.volume = value;
    this.updateVolume();
    this.emit('volumeChange', { volume: value, oldVolume });
  }

  private applyVolume(player: media.AVPlayer): void {
    player.setVolume(this.muted ? 0 : this.volume * (this.ducked ? DUCKED_VOLUME_MULTIPLIER : 1));
  }

  private updateVolume(): void {
    const load = this.load;
    if (load?.prepared) this.schedule(load, async (player: media.AVPlayer): Promise<void> => this.applyVolume(player));
    this.reconcilePlayback();
    this.notify();
  }

  setLoop(value: boolean): void {
    if (value && this.isLive)
      throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Looping a live stream is not supported by expo-video on HarmonyOS.');

    this.loop = value;
    const load = this.load;
    if (load?.prepared)
      this.schedule(load, async (player: media.AVPlayer): Promise<void> => {
        if (!this.isLive) player.loop = value;
      });
  }

  setRate(value: number): void {
    requireFinite(value, 'playbackRate', MIN_PLAYBACK_RATE);
    if (value > MAX_PLAYBACK_RATE) throw new ExpoModuleError('ERR_VIDEO_INVALID_ARGUMENT', 'HarmonyOS playbackRate must be between 0.125 and 4.');
    if (this.isLive) throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Changing live playback speed is not supported by expo-video on HarmonyOS.');
    if (value === this.playbackRate) return;

    const oldPlaybackRate = this.playbackRate;
    this.playbackRate = value;
    const load = this.load;
    if (load?.prepared) this.schedule(load, async (player: media.AVPlayer): Promise<void> => player.setPlaybackRate(value));
    this.emit('playbackRateChange', { playbackRate: value, oldPlaybackRate });
    this.notify();
  }

  setInterval(seconds: number): void {
    requireFinite(seconds, 'timeUpdateEventInterval');
    if (seconds * 1000 > MAX_TIMER_MS)
      throw new ExpoModuleError('ERR_VIDEO_INVALID_ARGUMENT', 'timeUpdateEventInterval exceeds the native timer range.');

    this.timeUpdateEventInterval = seconds;
    if (this.interval !== undefined) clearInterval(this.interval);
    this.interval = undefined;

    if (seconds > 0)
      this.interval = setInterval(
        (): void => {
          this.emit('timeUpdate', {
            currentTime: this.currentTime,
            currentLiveTimestamp: null,
            currentOffsetFromLive: null,
            bufferedPosition: this.bufferedPosition,
          });
        },
        Math.max(1, Math.round(seconds * 1000)),
      );
  }

  setKeepScreenOn(value: boolean): void {
    this.keepScreenOnWhilePlaying = value;
    this.notify();
  }

  setAudioMixingMode(value: string): void {
    if (!['auto', 'doNotMix', 'mixWithOthers', 'duckOthers'].includes(value))
      throw new ExpoModuleError('ERR_VIDEO_INVALID_ARGUMENT', 'Invalid audioMixingMode.');

    this.audioMixingMode = value;
    this.reconcilePlayback();
  }

  setBufferOptions(value: BufferOptions): void {
    if (value.preferredForwardBufferDuration !== undefined) {
      requireFinite(value.preferredForwardBufferDuration, 'preferredForwardBufferDuration');
      if (
        value.preferredForwardBufferDuration !== 0 &&
        (value.preferredForwardBufferDuration < MIN_BUFFER_SECONDS || value.preferredForwardBufferDuration > MAX_BUFFER_SECONDS)
      )
        throw new ExpoModuleError(
          'ERR_VIDEO_INVALID_ARGUMENT',
          'preferredForwardBufferDuration must be zero (system default) or between 1 and 20 seconds on HarmonyOS.',
        );
    }
    if (this.load?.prepared || this.load?.preparing)
      throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Buffer options must be set before the source is prepared on HarmonyOS.');
    if (
      value.minBufferForPlayback !== undefined ||
      value.maxBufferBytes != null ||
      value.prioritizeTimeOverSizeThreshold !== undefined ||
      value.waitsToMinimizeStalling !== undefined
    ) {
      throw new ExpoModuleError(
        'ERR_VIDEO_UNSUPPORTED',
        'Custom buffer thresholds other than preferredForwardBufferDuration are not supported by expo-video on HarmonyOS.',
      );
    }

    this.bufferOptions = value;
  }

  setSeekTolerance(value: SeekTolerance): void {
    if ((value.toleranceBefore ?? 0) !== 0 || (value.toleranceAfter ?? 0) !== 0)
      throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Nonzero seek tolerances are not supported by expo-video on HarmonyOS.');

    this.seekTolerance = value;
  }

  async thumbnails(times: number[], options: ThumbnailOptions): Promise<VideoThumbnail[]> {
    const result = await generateThumbnails(this.context, this.source, times, options);
    if (this.released) {
      result.forEach((thumbnail: VideoThumbnail): void => thumbnail.sharedObjectWillRelease());
      throw new ExpoModuleError('ERR_VIDEO_RELEASED', 'The player was released while generating thumbnails.');
    }

    return result;
  }

  selectTrack(track: MediaTrack | null, subtitle: boolean): void {
    const tracks = subtitle ? this.availableSubtitleTracks : this.availableAudioTracks;
    if (track !== null && !tracks.some((item: MediaTrack): boolean => item.id === track.id)) {
      throw new ExpoModuleError('ERR_VIDEO_INVALID_TRACK', 'Select a track from this player’s available tracks.');
    }

    if (subtitle) this.subtitlesDisabled = track === null;
    else this.audioDisabled = track === null;

    const load = this.load;
    if (!load?.prepared) {
      if (track !== null) throw new ExpoModuleError('ERR_VIDEO_NOT_READY', 'Tracks are not available until the source loads.');
      return;
    }

    this.schedule(load, async (player: media.AVPlayer): Promise<void> => {
      const previous = subtitle ? this.subtitleTrack : this.audioTrack;
      if (!subtitle) {
        // deselectTrack restores the system default audio track, whereas Expo null disables audio.
        if (track) await player.selectTrack(Number(track.id));
        if (!this.active(load)) return;
        await player.setMediaMuted(media.MediaType.MEDIA_TYPE_AUD, track === null);
      } else if (track === null && previous) await player.deselectTrack(Number(previous.id));
      else if (track) await player.selectTrack(Number(track.id));

      if (!this.active(load)) return;
      if (subtitle) this.subtitle = '';
      await this.updateTracks(load, player);
      this.reconcilePlayback();
    });
  }

  private resetTracks(): void {
    this.applyTracks([], [], [], []);
  }

  private async updateTracks(load: VideoLoad, player: media.AVPlayer): Promise<void> {
    if (!canReadTracks(player)) return;

    let descriptions: media.MediaDescription[];
    let selected: number[];
    try {
      descriptions = await player.getTrackDescription();
      if (!this.active(load) || !canReadTracks(player)) return;
      selected = await player.getSelectedTracks();
    } catch (error) {
      // A short clip can finish while an adaptive track update is being queried.
      if (!this.active(load) || !canReadTracks(player)) return;
      throw error as Error;
    }
    if (!this.active(load) || !canReadTracks(player)) return;

    const ranges = await load.videoRanges;
    if (!this.active(load)) return;

    const audios: MediaTrack[] = [],
      subtitles: MediaTrack[] = [],
      videos: VideoTrack[] = [];
    const seen = new Set<number>();
    descriptions.forEach((entry: media.MediaDescription): void => {
      const index = entry[media.MediaDescriptionKey.MD_KEY_TRACK_INDEX];
      const kind = entry[media.MediaDescriptionKey.MD_KEY_TRACK_TYPE];
      if (typeof index !== 'number' || !Number.isSafeInteger(index) || index < 0 || seen.has(index)) return;
      if (kind !== media.MediaType.MEDIA_TYPE_AUD && kind !== media.MediaType.MEDIA_TYPE_SUBTITLE && kind !== media.MediaType.MEDIA_TYPE_VID) return;
      seen.add(index);
      const id = String(index);
      const languageValue = entry[media.MediaDescriptionKey.MD_KEY_LANGUAGE];
      const language = typeof languageValue === 'string' && languageValue.length > 0 ? languageValue : 'und';
      const name = entry[media.MediaDescriptionKey.MD_KEY_TRACK_NAME];
      const track: MediaTrack = { id, language, label: typeof name === 'string' ? name : language };
      if (typeof name === 'string') track.name = name;
      if (kind === media.MediaType.MEDIA_TYPE_AUD) audios.push(track);
      if (kind === media.MediaType.MEDIA_TYPE_SUBTITLE) subtitles.push(track);
      if (kind === media.MediaType.MEDIA_TYPE_VID) {
        videos.push({
          id,
          url: null,
          size: {
            width: finiteNonnegative(entry[media.MediaDescriptionKey.MD_KEY_WIDTH]) ?? 0,
            height: finiteNonnegative(entry[media.MediaDescriptionKey.MD_KEY_HEIGHT]) ?? 0,
          },
          mimeType: typeof entry[media.MediaDescriptionKey.MD_KEY_CODEC_MIME] === 'string'
            ? entry[media.MediaDescriptionKey.MD_KEY_CODEC_MIME] as string : null,
          isSupported: true,
          bitrate: finiteNonnegative(entry[media.MediaDescriptionKey.MD_KEY_BITRATE]) || null,
          averageBitrate: null,
          peakBitrate: null,
          frameRate: (finiteNonnegative(entry[media.MediaDescriptionKey.MD_KEY_FRAME_RATE]) ?? 0) / 100 || null,
          videoRange: ranges[id] ?? 'sdr',
        });
      }
    });

    if (this.subtitlesDisabled) {
      for (const track of subtitles) {
        if (selected.includes(Number(track.id))) {
          await player.deselectTrack(Number(track.id));
          if (!this.active(load)) return;
        }
      }
    }

    this.applyTracks(audios, subtitles, videos, selected);
    this.reconcilePlayback();
  }

  private applyTracks(audios: MediaTrack[], subtitles: MediaTrack[], videos: VideoTrack[], selected: number[]): void {
    const oldAvailableAudioTracks = this.availableAudioTracks;
    const oldAvailableSubtitleTracks = this.availableSubtitleTracks;
    const oldAudioTrack = this.audioTrack;
    const oldSubtitleTrack = this.subtitleTrack;
    const oldVideoTrack = this.videoTrack;

    this.availableAudioTracks = audios;
    this.availableSubtitleTracks = subtitles;
    this.availableVideoTracks = videos;
    this.audioTrack = this.audioDisabled ? null : (audios.find((track: MediaTrack): boolean => selected.includes(Number(track.id))) ?? null);
    this.subtitleTrack = this.subtitlesDisabled
      ? null
      : (subtitles.find((track: MediaTrack): boolean => selected.includes(Number(track.id))) ?? null);
    this.videoTrack = videos.find((track: VideoTrack): boolean => selected.includes(Number(track.id))) ?? null;

    if (JSON.stringify(audios) !== JSON.stringify(oldAvailableAudioTracks))
      this.emit('availableAudioTracksChange', { availableAudioTracks: audios, oldAvailableAudioTracks });
    if (JSON.stringify(subtitles) !== JSON.stringify(oldAvailableSubtitleTracks))
      this.emit('availableSubtitleTracksChange', { availableSubtitleTracks: subtitles, oldAvailableSubtitleTracks });
    if (JSON.stringify(this.audioTrack) !== JSON.stringify(oldAudioTrack))
      this.emit('audioTrackChange', { audioTrack: this.audioTrack, oldAudioTrack });
    if (JSON.stringify(this.subtitleTrack) !== JSON.stringify(oldSubtitleTrack))
      this.emit('subtitleTrackChange', { subtitleTrack: this.subtitleTrack, oldSubtitleTrack });
    if (JSON.stringify(this.videoTrack) !== JSON.stringify(oldVideoTrack))
      this.emit('videoTrackChange', { videoTrack: this.videoTrack, oldVideoTrack });
  }

  override sharedObjectWillRelease(): void {
    if (this.released) return;

    this.released = true;
    this.playing = false;
    this.status = 'idle';
    this.notify();

    if (this.interval !== undefined) clearInterval(this.interval);
    this.observers.clear();
    this.owner = undefined;
    this.surface = undefined;

    const load = this.load;
    this.load = undefined;
    if (load) void this.dispose(load);

    this.session.remove(this);
    this.onRelease(this);
  }

  private async dispose(load: VideoLoad): Promise<void> {
    load.disposed = true;
    load.cancel?.(new ExpoModuleError('ERR_VIDEO_LOAD_CANCELLED', 'Video loading was cancelled.') as Error);
    if (load.disposal) return load.disposal;

    // A cancelled createAVPlayer may still complete; that continuation calls dispose again.
    if (!load.player && !load.file) return;

    this.retired.add(load);
    load.disposal = this.releaseResources(load);

    try {
      await load.disposal;
    } finally {
      load.disposal = undefined;
      if (!load.player && !load.file) this.retired.delete(load);
      this.scheduleCleanup();
    }
  }

  private async releaseResources(load: VideoLoad): Promise<void> {
    const player = load.player;
    // Do not await load.tail: disposal from its catch would deadlock.
    if (player) {
      try {
        if (player.state !== 'released') await player.release();
      } catch (error) {
        console.warn(`ExpoVideo: player release failed: ${String(error)}`);
        if (player.state !== 'released') return; // Never close a descriptor the decoder may still own.
      }
      load.player = undefined;
    }

    try {
      load.file?.close();
      load.file = undefined;
    } catch (error) {
      console.warn(`ExpoVideo: source close failed: ${String(error)}`);
    }
  }

  private scheduleCleanup(): void {
    if (this.retired.size === 0) {
      if (this.cleanupTimer !== undefined) clearTimeout(this.cleanupTimer);
      this.cleanupTimer = undefined;
      this.cleanupDelay = INITIAL_CLEANUP_DELAY_MS;
      return;
    }
    if (this.cleanupTimer !== undefined) return;

    // Retain failed native resources for retry after the SharedObject is released.
    this.cleanupTimer = setTimeout((): void => {
      this.cleanupTimer = undefined;
      Array.from(this.retired).forEach((load: VideoLoad): void => {
        void this.dispose(load);
      });
    }, this.cleanupDelay);

    this.cleanupDelay = Math.min(MAX_CLEANUP_DELAY_MS, this.cleanupDelay * 2);
  }
}

async function withLoadTimeout<T>(operation: Promise<T>, message: string): Promise<T> {
  let timer: number | undefined;

  try {
    return await Promise.race([
      operation,
      new Promise<T>((_resolve, reject): void => {
        timer = setTimeout((): void => reject(new ExpoModuleError('ERR_VIDEO_LOAD_TIMEOUT', message)), LOAD_TIMEOUT_MS);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

function finiteNonnegative(value: ESObject): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
}

function canReadTracks(player: media.AVPlayer): boolean {
  return ['prepared', 'playing', 'paused'].includes(player.state);
}
