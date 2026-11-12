/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoRecordShape,
  ExpoSharedObjectClassDefinition,
  ExpoValueType,
  ExpoValueTypes,
  ExpoViewContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import { VideoAudioSession } from './VideoAudioSession';
import { isPictureInPictureSupported } from './VideoPictureInPicture';
import { BufferOptions, MediaTrack, PlayerBuilderOptions, SeekTolerance, VideoPlayer } from './VideoPlayer';
import { requireFinite, VIDEO_SOURCE, VideoSource } from './VideoSource';
import { supportsBackgroundVideoPlayback, VideoSystemMedia } from './VideoSystemMedia';
import { ThumbnailOptions, VideoThumbnail } from './VideoThumbnail';
import { buildVideoView, ButtonOptions, ContentPosition, FullscreenOptions, VideoScreenOn, VideoView } from './VideoView';

function record<T>(name: string, shape: ExpoRecordShape): ExpoValueType<T> {
  return ExpoValueTypes.shapedRecord<T>(
    name,
    shape,
    (fields: Record<string, ESObject>): T => fields as T,
    (value: T): Record<string, ESObject> => value as Record<string, ESObject>,
  );
}
const OPTIONAL_NUMBER = ExpoValueTypes.number().optional();
const OPTIONAL_BOOLEAN = ExpoValueTypes.boolean().optional();
const BUILDER = record<PlayerBuilderOptions>(
  'PlayerBuilderOptions',
  new ExpoRecordShape().field('seekBackwardIncrement', OPTIONAL_NUMBER).field('seekForwardIncrement', OPTIONAL_NUMBER),
);
const BUFFER = record<BufferOptions>(
  'BufferOptions',
  new ExpoRecordShape()
    .field('preferredForwardBufferDuration', OPTIONAL_NUMBER)
    .field('waitsToMinimizeStalling', OPTIONAL_BOOLEAN)
    .field('minBufferForPlayback', OPTIONAL_NUMBER)
    .field('maxBufferBytes', ExpoValueTypes.number().nullable().optional())
    .field('prioritizeTimeOverSizeThreshold', OPTIONAL_BOOLEAN),
);
const SEEK = record<SeekTolerance>(
  'SeekTolerance',
  new ExpoRecordShape().field('toleranceBefore', OPTIONAL_NUMBER).field('toleranceAfter', OPTIONAL_NUMBER),
);
const TRACK = record<MediaTrack>(
  'MediaTrack',
  new ExpoRecordShape()
    .field('id', ExpoValueTypes.string())
    .field('language', ExpoValueTypes.string().optional())
    .field('label', ExpoValueTypes.string().optional())
    .field('name', ExpoValueTypes.string().optional()),
);
const THUMBNAIL = record<ThumbnailOptions>(
  'VideoThumbnailOptions',
  new ExpoRecordShape().field('maxWidth', OPTIONAL_NUMBER).field('maxHeight', OPTIONAL_NUMBER),
);
const FULLSCREEN = record<FullscreenOptions>(
  'FullscreenOptions',
  new ExpoRecordShape()
    .field('enable', OPTIONAL_BOOLEAN)
    .field('orientation', ExpoValueTypes.string().optional())
    .field('autoExitOnRotate', OPTIONAL_BOOLEAN)
    .field('keepFullscreenOnPiPStop', ExpoValueTypes.enumerable<string>('KeepFullscreenOnPiPStopBehavior', {
      always: 'always', autoEnter: 'autoEnter', never: 'never',
    }).optional()),
);
const BUTTONS = record<ButtonOptions>(
  'ButtonOptions',
  new ExpoRecordShape()
    .field('showNext', OPTIONAL_BOOLEAN)
    .field('showPrevious', OPTIONAL_BOOLEAN)
    .field('showSeekForward', OPTIONAL_BOOLEAN)
    .field('showSeekBackward', OPTIONAL_BOOLEAN)
    .field('showSubtitles', ExpoValueTypes.boolean().nullable().optional())
    .field('showSettings', OPTIONAL_BOOLEAN)
    .field('showPlayPause', OPTIONAL_BOOLEAN)
    .field('showBottomBar', OPTIONAL_BOOLEAN),
);
const POSITION = record<ContentPosition>('ContentPosition', new ExpoRecordShape().field('dx', OPTIONAL_NUMBER).field('dy', OPTIONAL_NUMBER));
const SCRUBBING = ExpoValueTypes.record(ExpoValueTypes.boolean());
const FIT_VALUES: Record<string, string> = { 'contain': 'contain', 'cover': 'cover', 'fill': 'fill' };
const FIT = ExpoValueTypes.enumerable<string>('VideoContentFit', FIT_VALUES);

export class ExpoVideoModule extends ExpoModule {
  private readonly players: Set<VideoPlayer> = new Set<VideoPlayer>();
  private readonly session: VideoAudioSession = new VideoAudioSession();
  private readonly screen: VideoScreenOn;
  private readonly systemMedia: VideoSystemMedia;
  private backgrounded: boolean;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.backgrounded = context.appLifecycleState === ExpoAppLifecycleState.BACKGROUND;
    this.screen = new VideoScreenOn(context);
    this.systemMedia = new VideoSystemMedia(context.uiAbilityContext);
  }

  override definition(): ExpoModuleDefinition {
    const thumbnail = new ExpoSharedObjectClassDefinition<VideoThumbnail>('VideoThumbnail')
      .sharedRef('image')
      .property('width', ExpoValueTypes.number(), (value: VideoThumbnail): number => value.width)
      .property('height', ExpoValueTypes.number(), (value: VideoThumbnail): number => value.height)
      .property('requestedTime', ExpoValueTypes.number(), (value: VideoThumbnail): number => value.requestedTime);

    const player = new ExpoSharedObjectClassDefinition<VideoPlayer>('VideoPlayer')
      .construct(
        ExpoFunction.ownedTyped3(
          VIDEO_SOURCE,
          ExpoValueTypes.boolean().optional(),
          BUILDER.nullable().optional(),
          (context: ExpoModuleContext, source: VideoSource | null, _synchronous?: boolean, options?: PlayerBuilderOptions | null): VideoPlayer => {
            const instance = new VideoPlayer(context, source, options ?? {}, this.session, (value: VideoPlayer): void => {
              this.players.delete(value);
              this.systemMedia.update(this.players);
            }, (): void => this.systemMedia.update(this.players));
            instance.setBackgrounded(this.backgrounded);
            this.players.add(instance);

            return instance;
          },
        ),
      )
      .events([
        'statusChange',
        'playingChange',
        'playbackRateChange',
        'volumeChange',
        'mutedChange',
        'playToEnd',
        'timeUpdate',
        'sourceChange',
        'sourceLoad',
        'availableSubtitleTracksChange',
        'subtitleTrackChange',
        'availableAudioTracksChange',
        'audioTrackChange',
        'videoTrackChange',
        'isExternalPlaybackActiveChange',
      ])
      .property('playing', ExpoValueTypes.boolean(), (player: VideoPlayer): boolean => player.playing)
      .property('status', ExpoValueTypes.string(), (player: VideoPlayer): string => player.status)
      .property('duration', ExpoValueTypes.number(), (player: VideoPlayer): number => player.duration)
      .property('isLive', ExpoValueTypes.boolean(), (player: VideoPlayer): boolean => player.isLive)
      .property('bufferedPosition', ExpoValueTypes.number(), (player: VideoPlayer): number => player.bufferedPosition)
      .property('currentLiveTimestamp', ExpoValueTypes.number().nullable(), (): number | null => null)
      .property('currentOffsetFromLive', ExpoValueTypes.number().nullable(), (): number | null => null)
      .property('isExternalPlaybackActive', ExpoValueTypes.boolean(), (): boolean => false)
      .property(
        'muted',
        ExpoValueTypes.boolean(),
        (player: VideoPlayer): boolean => player.muted,
        (player: VideoPlayer, value: boolean): void => player.setMuted(value),
      )
      .property(
        'volume',
        ExpoValueTypes.number(),
        (player: VideoPlayer): number => player.volume,
        (player: VideoPlayer, value: number): void => player.setVolume(value),
      )
      .property(
        'loop',
        ExpoValueTypes.boolean(),
        (player: VideoPlayer): boolean => player.loop,
        (player: VideoPlayer, value: boolean): void => player.setLoop(value),
      )
      .property(
        'currentTime',
        ExpoValueTypes.number(),
        (player: VideoPlayer): number => player.currentTime,
        (player: VideoPlayer, value: number): void => player.seek(value),
      )
      .property(
        'playbackRate',
        ExpoValueTypes.number(),
        (player: VideoPlayer): number => player.playbackRate,
        (player: VideoPlayer, value: number): void => player.setRate(value),
      )
      .property(
        'timeUpdateEventInterval',
        ExpoValueTypes.number(),
        (player: VideoPlayer): number => player.timeUpdateEventInterval,
        (player: VideoPlayer, value: number): void => player.setInterval(value),
      )
      .property(
        'keepScreenOnWhilePlaying',
        ExpoValueTypes.boolean(),
        (player: VideoPlayer): boolean => player.keepScreenOnWhilePlaying,
        (player: VideoPlayer, value: boolean): void => player.setKeepScreenOn(value),
      )
      .property(
        'audioMixingMode',
        ExpoValueTypes.string(),
        (player: VideoPlayer): string => player.audioMixingMode,
        (player: VideoPlayer, value: string): void => player.setAudioMixingMode(value),
      )
      .property(
        'bufferOptions',
        BUFFER,
        (player: VideoPlayer): BufferOptions => player.bufferOptions,
        (player: VideoPlayer, value: BufferOptions): void => player.setBufferOptions(value),
      )
      .property(
        'seekTolerance',
        SEEK.nullable(),
        (player: VideoPlayer): SeekTolerance => player.seekTolerance,
        (player: VideoPlayer, value: SeekTolerance | null): void => player.setSeekTolerance(value ?? {}),
      )
      .property('availableAudioTracks', (player: VideoPlayer): MediaTrack[] => player.availableAudioTracks)
      .property('availableSubtitleTracks', (player: VideoPlayer): MediaTrack[] => player.availableSubtitleTracks)
      .property('availableVideoTracks', (player: VideoPlayer): ESObject => player.availableVideoTracks)
      .property('videoTrack', (player: VideoPlayer): ESObject => player.videoTrack)
      .property(
        'audioTrack',
        TRACK.nullable(),
        (player: VideoPlayer): MediaTrack | null => player.audioTrack,
        (player: VideoPlayer, value: MediaTrack | null): void => player.selectTrack(value, false),
      )
      .property(
        'subtitleTrack',
        TRACK.nullable(),
        (player: VideoPlayer): MediaTrack | null => player.subtitleTrack,
        (player: VideoPlayer, value: MediaTrack | null): void => player.selectTrack(value, true),
      )
      .property(
        'preservesPitch',
        ExpoValueTypes.boolean(),
        (): boolean => true,
        (_player: VideoPlayer, value: boolean): void => {
          if (!value) throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Disabling pitch correction is not supported by expo-video on HarmonyOS.');
        },
      )
      .property(
        'showNowPlayingNotification',
        ExpoValueTypes.boolean(),
        (player: VideoPlayer): boolean => player.showNowPlayingNotification,
        (player: VideoPlayer, value: boolean): void => {
          if (value && !canIUse('SystemCapability.Multimedia.AVSession.Core')) {
            throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'AVSession is unavailable on this device.');
          }

          player.setNowPlayingNotification(value);
        },
      )
      .property(
        'staysActiveInBackground',
        ExpoValueTypes.boolean(),
        (player: VideoPlayer): boolean => player.staysActiveInBackground,
        (player: VideoPlayer, value: boolean): void => {
          if (value && !supportsBackgroundVideoPlayback()) {
            throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Background video playback needs HarmonyOS API 22 and AVSession.');
          }

          player.setStaysActiveInBackground(value);
        },
      )
      .property(
        'allowsExternalPlayback',
        ExpoValueTypes.boolean(),
        (): boolean => false,
        (_player: VideoPlayer, value: boolean): void => {
          if (value) throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'External playback is not supported by expo-video on HarmonyOS.');
        },
      )
      .property(
        'targetOffsetFromLive',
        ExpoValueTypes.number(),
        (): number => 0,
        (_player: VideoPlayer, value: number): void => {
          requireFinite(value, 'targetOffsetFromLive');
          if (value !== 0) throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Live target offset is not supported by expo-video on HarmonyOS.');
        },
      )
      .property(
        'scrubbingModeOptions',
        SCRUBBING.nullable(),
        (): Record<string, boolean> => {
          const options: Record<string, boolean> = {};
          options['scrubbingModeEnabled'] = false;
          return options;
        },
        (_player: VideoPlayer, value: Record<string, boolean> | null): void => {
          if (value && Object.keys(value).some((key: string): boolean => value[key]))
            throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'ExoPlayer scrubbing mode is not supported by expo-video on HarmonyOS.');
        },
      )
      .syncFunction('play', (player: VideoPlayer): void => player.play())
      .syncFunction('pause', (player: VideoPlayer): void => player.pause())
      .syncFunction('replay', (player: VideoPlayer): void => player.replay())
      .syncFunction(
        'seekBy',
        ExpoFunction.ownedTyped1(ExpoValueTypes.number(), (player: VideoPlayer, seconds: number): void => player.seekBy(seconds)),
      )
      .syncFunction(
        'replace',
        ExpoFunction.ownedTyped1(VIDEO_SOURCE, (player: VideoPlayer, source: VideoSource | null): void => player.replace(source)),
      )
      .asyncFunction(
        'replaceAsync',
        ExpoFunction.ownedTyped1(VIDEO_SOURCE, (player: VideoPlayer, source: VideoSource | null): Promise<void> => player.replaceAsync(source)),
      )
      .asyncFunction(
        'generateThumbnailsAsync',
        ExpoFunction.ownedTyped2(
          ExpoValueTypes.number().or(ExpoValueTypes.array(ExpoValueTypes.number())),
          THUMBNAIL.nullable().optional(),
          async (player: VideoPlayer, times: number | number[], options?: ThumbnailOptions | null): Promise<VideoThumbnail[]> => {
            const thumbnails = await player.thumbnails(typeof times === 'number' ? [times] : times, options ?? {});

            return thumbnails.map((image: VideoThumbnail): VideoThumbnail => thumbnail.instance(image));
          },
        ).returns(ExpoValueTypes.array(thumbnail.valueType())),
      );

    const view = new ExpoViewDefinition<VideoView>(
      'VideoView',
      (context: ExpoViewContext): VideoView => new VideoView(context, this.screen),
      wrapBuilder(buildVideoView),
    )
      .prop('player', player.valueType().nullable(), (view: VideoView, player: VideoPlayer | null): void => view.setPlayer(player), null)
      .prop(
        'nativeControls',
        ExpoValueTypes.boolean(),
        (view: VideoView, value: boolean): void => {
          view.nativeControls = value;
        },
        true,
      )
      .prop(
        'surfaceType',
        ExpoValueTypes.string(),
        (_view: VideoView, value: string): void => {
          if (value !== 'surfaceView')
            throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'TextureView rendering is not supported by expo-video on HarmonyOS.');
        },
        'surfaceView',
      )
      .prop(
        'contentFit',
        FIT,
        (view: VideoView, value: string): void => {
          view.contentFit = value;
        },
        'contain',
      )
      .prop(
        'contentPosition',
        POSITION.nullable(),
        (view: VideoView, value: ContentPosition | null): void => {
          view.contentPosition = value ?? {};
        },
        null,
      )
      .prop(
        'fullscreenOptions',
        FULLSCREEN.nullable(),
        (view: VideoView, value: FullscreenOptions | null): void => view.setFullscreenOptions(value ?? { enable: true }),
        null,
      )
      .prop(
        'buttonOptions',
        BUTTONS.nullable(),
        (view: VideoView, value: ButtonOptions | null): void => {
          view.setButtonOptions(value ?? {});
        },
        null,
      )
      .prop(
        'requiresLinearPlayback',
        ExpoValueTypes.boolean(),
        (view: VideoView, value: boolean): void => {
          view.requiresLinearPlayback = value;
        },
        false,
      )
      .prop(
        'showsTimecodes',
        ExpoValueTypes.boolean(),
        (view: VideoView, value: boolean): void => {
          view.showsTimecodes = value;
        },
        true,
      )
      .prop(
        'allowsPictureInPicture',
        ExpoValueTypes.boolean(),
        (view: VideoView, value: boolean): void => view.setAllowsPictureInPicture(value),
        false,
      )
      .prop(
        'startsPictureInPictureAutomatically',
        ExpoValueTypes.boolean(),
        (view: VideoView, value: boolean): void => view.setStartsPictureInPictureAutomatically(value),
        false,
      )
      .events(['onPictureInPictureStart', 'onPictureInPictureStop', 'onFullscreenEnter', 'onFullscreenExit', 'onFirstFrameRender'])
      .asyncFunction('enterFullscreen', async (view: VideoView): Promise<void> => view.enterFullscreen())
      .asyncFunction('exitFullscreen', async (view: VideoView): Promise<void> => view.exitFullscreen())
      .asyncFunction('startPictureInPicture', async (view: VideoView): Promise<void> => view.startPictureInPicture())
      .asyncFunction('stopPictureInPicture', async (view: VideoView): Promise<void> => view.stopPictureInPicture())
      .onDestroy((view: VideoView): void => view.destroy());

    return new ExpoModuleDefinition()
      .name('ExpoVideo')
      .sharedObjectClass(player)
      .sharedObjectClass(thumbnail)
      .view(view)
      .syncFunction('isPictureInPictureSupported', (): boolean => isPictureInPictureSupported())
      .syncFunction('getCurrentVideoCacheSize', (): number => 0)
      .asyncFunction('clearVideoCacheAsync', async (): Promise<void> => this.assertNoPlayers())
      .asyncFunction(
        'setVideoCacheSizeAsync',
        ExpoFunction.typed1(ExpoValueTypes.number(), async (bytes: number): Promise<void> => {
          this.assertNoPlayers();
          requireFinite(bytes, 'sizeBytes');

          throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Persistent video caching is not supported by expo-video on HarmonyOS.');
        }),
      )
      .onBackground((): void => {
        this.backgrounded = true;
        this.screen.setForeground(false);
        this.players.forEach((player: VideoPlayer): void => player.setBackgrounded(true));
      })
      .onForeground((): void => {
        this.backgrounded = false;
        this.screen.setForeground(true);
        this.systemMedia.foreground();
        this.players.forEach((player: VideoPlayer): void => player.setBackgrounded(false));
        this.systemMedia.update(this.players);
      })
      .onContentAppeared((): void => { this.screen.refresh(); })
      .onPrepareForReload(async (): Promise<void> => {
        await Promise.all([this.screen.destroy(), this.systemMedia.destroy(), this.session.destroy()]);
      })
      .onDestroy((): void => {
        void this.screen.destroy();
        void this.systemMedia.destroy();
        void this.session.destroy();
        Array.from(this.players).forEach((player: VideoPlayer): void => player.sharedObjectWillRelease());
      });
  }

  private assertNoPlayers(): void {
    if (this.players.size > 0)
      throw new ExpoModuleError('ERR_VIDEO_CACHE_IN_USE', 'Release all VideoPlayer instances before changing the video cache.');
  }
}
