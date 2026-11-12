/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAppLifecycleState, ExpoModuleContext, ExpoModuleError, ExpoView, ExpoViewContext, ExpoViewContentContext, ExpoWindowKeepAwake } from '@expo-harmony/expo-modules-core';
import { window } from '@kit.ArkUI';
import { VideoPictureInPicture } from './VideoPictureInPicture';
import { VideoObserver, VideoPlayer } from './VideoPlayer';

export interface FullscreenOptions {
  enable?: boolean;
  orientation?: string;
  autoExitOnRotate?: boolean;
  // iOS-only; accepted for shared configurations, as on Android.
  keepFullscreenOnPiPStop?: string;
}

export interface ButtonOptions {
  showNext?: boolean;
  showPrevious?: boolean;
  showSeekForward?: boolean;
  showSeekBackward?: boolean;
  showSubtitles?: boolean | null;
  showSettings?: boolean;
  showPlayPause?: boolean;
  showBottomBar?: boolean;
}

export interface ContentPosition {
  dx?: number;
  dy?: number;
}

export class VideoScreenOn {
  private readonly holders: Set<VideoView> = new Set<VideoView>();
  private tail: Promise<void> = Promise.resolve();
  private target?: window.Window;
  private windowId?: number;
  private foreground: boolean;
  private destroyed: boolean = false;
  private retry: boolean = false;
  private readonly context: ExpoModuleContext;

  constructor(context: ExpoModuleContext) {
    this.context = context;
    this.foreground = context.appLifecycleState !== ExpoAppLifecycleState.BACKGROUND;
  }

  update(view: VideoView, enabled: boolean): void {
    if (this.destroyed || (this.holders.has(view) === enabled && !this.retry)) return;

    if (enabled) this.holders.add(view);
    else this.holders.delete(view);
    this.refresh();
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    this.refresh();
  }

  destroy(): Promise<void> {
    this.destroyed = true;
    this.holders.clear();
    return this.refresh();
  }

  refresh(): Promise<void> {
    this.tail = this.tail
      .then(async (): Promise<void> => {
        this.retry = false;
        if (this.destroyed || !this.foreground || this.holders.size === 0) {
          await this.releaseTarget();
          return;
        }

        const target = await this.context.getReactNativeWindow();
        if (this.destroyed || !this.foreground || this.holders.size === 0) return;

        const id = target.getWindowProperties().id;
        if (this.target !== undefined && this.windowId !== id) await this.releaseTarget();
        if (this.destroyed || !this.foreground || this.holders.size === 0) return;

        this.target = target;
        this.windowId = id;
        await ExpoWindowKeepAwake.acquire(target, this);
      })
      .catch((error: Error): void => {
        this.retry = true;
        console.warn(`ExpoVideo: keep-screen-on failed: ${error.message}`);
      });
    return this.tail;
  }

  private async releaseTarget(): Promise<void> {
    if (this.target === undefined) return;
    await ExpoWindowKeepAwake.release(this.target, this);
    this.target = undefined;
    this.windowId = undefined;
  }
}

@Observed
export class VideoView extends ExpoView implements VideoObserver {
  player: VideoPlayer | null = null;
  nativeControls: boolean = true;
  contentFit: string = 'contain';
  contentPosition: ContentPosition = {};
  fullscreenOptions: FullscreenOptions = { enable: true };
  buttonOptions: ButtonOptions = {};
  requiresLinearPlayback: boolean = false;
  showsTimecodes: boolean = true;
  fullscreen: boolean = false;
  playing: boolean = false;
  playbackRequested: boolean = false;
  position: number = 0;
  duration: number = 0;
  isLive: boolean = false;
  subtitle: string = '';
  videoWidth: number = 0;
  videoHeight: number = 0;
  frameReady: boolean = false;
  surfaceRevision: number = 0;
  private surface?: string;
  private surfaceController?: XComponentController;
  private allowsPictureInPicture: boolean = false;
  private startsPictureInPictureAutomatically: boolean = false;
  private pictureInPictureActive: boolean = false;
  private readonly pictureInPicture: VideoPictureInPicture;
  private destroyed: boolean = false;
  private announced: boolean = false;
  private readonly screen: VideoScreenOn;

  constructor(context: ExpoViewContext, screen: VideoScreenOn) {
    super(context);
    this.screen = screen;
    this.pictureInPicture = new VideoPictureInPicture(
      context.moduleContext.uiAbilityContext,
      (active: boolean, event?: string): void => {
        if (this.destroyed) return;
        this.pictureInPictureActive = active;
        this.player?.setPictureInPictureActive(active);
        if (event !== undefined) this.sendEvent(event);
      },
      (play: boolean): void => {
        if (play) this.player?.play();
        else this.player?.pause();
      },
    );
  }

  setPlayer(player: VideoPlayer | null): void {
    if (this.destroyed || player === this.player) return;

    // Reserve the player before changing props. Each decoder receives a fresh surface so
    // the outgoing decoder can finish detaching without competing for the new one.
    player?.claimView(this);
    const previous = this.player;
    previous?.removeObserver(this);
    previous?.setPictureInPictureActive(false);
    previous?.releaseView(this);
    this.surface = undefined;
    this.surfaceController = undefined;
    this.pictureInPictureActive = false;
    this.surfaceRevision += 1;
    this.player = player;
    player?.addObserver(this);

    this.update();
  }

  update(): void {
    if (this.destroyed) return;

    this.playing = this.player?.playing ?? false;
    this.playbackRequested = this.player?.playbackRequested ?? false;
    this.position = this.player?.currentTime ?? 0;
    this.duration = this.player?.duration ?? 0;
    this.isLive = this.player?.isLive ?? false;
    this.subtitle = this.player?.subtitle ?? '';
    this.videoWidth = this.player?.width ?? 0;
    this.videoHeight = this.player?.height ?? 0;
    this.frameReady = this.player?.hasRenderedFrame ?? false;

    this.screen.update(this, this.playing && (this.player?.keepScreenOnWhilePlaying ?? false));
    this.updatePictureInPicture();
  }

  firstFrame(): void {
    if (!this.destroyed) {
      this.update();
      this.sendEvent('onFirstFrameRender');
    }
  }

  attach(surface: string, controller: XComponentController): void {
    if (this.destroyed || !surface || (this.surface === surface && this.surfaceController === controller)) return;

    this.player?.attachSurface(this, surface);
    this.surface = surface;
    this.surfaceController = controller;
    this.updatePictureInPicture();
  }

  detach(surface: string): void {
    if (this.surface !== surface) return;

    this.surface = undefined;
    this.surfaceController = undefined;
    this.player?.detachSurface(this, surface);
    this.updatePictureInPicture();
  }

  setAllowsPictureInPicture(allowed: boolean): void {
    this.allowsPictureInPicture = allowed;
    this.updatePictureInPicture();
  }

  setStartsPictureInPictureAutomatically(enabled: boolean): void {
    this.startsPictureInPictureAutomatically = enabled;
    this.updatePictureInPicture();
  }

  startPictureInPicture(): Promise<void> {
    if (!this.allowsPictureInPicture) {
      throw new ExpoModuleError('ERR_VIDEO_PIP_DISABLED', 'Enable allowsPictureInPicture before starting Picture in Picture.');
    }
    if (!this.frameReady) throw new ExpoModuleError('ERR_VIDEO_PIP_NOT_READY', 'Wait for the first video frame before starting Picture in Picture.');
    return this.pictureInPicture.start();
  }

  stopPictureInPicture(): Promise<void> {
    return this.pictureInPicture.stop();
  }

  private updatePictureInPicture(): void {
    const enabled = this.allowsPictureInPicture || this.startsPictureInPictureAutomatically;
    const autoStart = this.startsPictureInPictureAutomatically && this.frameReady && this.playbackRequested;
    this.pictureInPicture.update(this.videoWidth, this.videoHeight, this.playing);
    this.pictureInPicture.configure(enabled && this.player ? this.surfaceController : undefined, autoStart);
  }

  enterFullscreen(): void {
    if (this.destroyed) throw new ExpoModuleError('ERR_VIDEO_VIEW_DESTROYED', 'The VideoView has been destroyed.');
    if (this.fullscreenOptions.enable === false) throw new ExpoModuleError('ERR_VIDEO_FULLSCREEN_DISABLED', 'Fullscreen is disabled.');

    this.fullscreen = true;
  }

  exitFullscreen(): void {
    this.fullscreen = false;
  }

  didEnterFullscreen(): void {
    if (this.destroyed || !this.fullscreen || this.announced) return;

    this.announced = true;
    this.sendEvent('onFullscreenEnter');
  }

  didExitFullscreen(): void {
    if (!this.announced) return;
    this.announced = false;
    if (!this.destroyed) this.sendEvent('onFullscreenExit');
  }

  setButtonOptions(value: ButtonOptions): void {
    if (value.showNext || value.showPrevious || value.showSubtitles || value.showSettings)
      throw new ExpoModuleError(
        'ERR_VIDEO_UNSUPPORTED',
        'Next/previous, subtitle and settings buttons are not supported by expo-video on HarmonyOS.',
      );

    this.buttonOptions = value;
  }

  setFullscreenOptions(value: FullscreenOptions): void {
    if (value.orientation && value.orientation !== 'default')
      throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'Forced fullscreen orientation is not supported by expo-video on HarmonyOS.');
    if (value.autoExitOnRotate === true)
      throw new ExpoModuleError('ERR_VIDEO_UNSUPPORTED', 'autoExitOnRotate is not supported by expo-video on HarmonyOS.');

    this.fullscreenOptions = value;
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.pictureInPicture.configure(undefined, false);
    this.player?.setPictureInPictureActive(false);
    this.player?.removeObserver(this);
    this.player?.releaseView(this);
    this.player = null;
    this.fullscreen = false;

    this.screen.update(this, false);
  }
}
@Builder
export function buildVideoView(context: ExpoViewContentContext) {
  VideoViewContent({ state: context.nativeView as VideoView });
}

@Component
struct VideoViewContent {
  @ObjectLink state: VideoView;

  @Builder surface(inFullscreen: boolean) {
    ForEach(
      [this.state.surfaceRevision],
      (revision: number): void => {
        VideoSurface({ state: this.state, revision, inFullscreen });
      },
      (revision: number): string => String(revision),
    );
  }

  @Builder fullscreenContent() {
    Stack() {
      this.surface(true);
    }
    .width('100%')
    .height('100%');
  }

  build() {
    Stack() {
      if (!this.state.fullscreen) {
        this.surface(false);
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .bindContentCover(this.state.fullscreen, this.fullscreenContent, {
      modalTransition: ModalTransition.NONE,
      onAppear: (): void => this.state.didEnterFullscreen(),
      onWillDismiss: (action: DismissContentCoverAction): void => {
        this.state.exitFullscreen();
        action.dismiss();
      },
      onDisappear: (): void => this.state.didExitFullscreen(),
    });
  }
}

class VideoSurfaceController extends XComponentController {
  private readonly view: VideoView;
  private readonly revision: number;
  private readonly fullscreen: boolean;

  constructor(view: VideoView, revision: number, fullscreen: boolean) {
    super();
    this.view = view;
    this.revision = revision;
    this.fullscreen = fullscreen;
  }

  override onSurfaceChanged(surface: string, rect: SurfaceRect): void {
    if (this.view.surfaceRevision !== this.revision || this.view.fullscreen !== this.fullscreen) return;

    // An XComponent may exist before ArkUI gives its buffer queue a usable size.
    if (rect.surfaceWidth > 0 && rect.surfaceHeight > 0) this.view.attach(surface, this);
    else this.view.detach(surface);
  }

  override onSurfaceDestroyed(surface: string): void {
    if (this.view.surfaceRevision === this.revision) this.view.detach(surface);
  }
}

@Component
struct VideoSurface {
  @ObjectLink state: VideoView;
  revision: number = 0;
  inFullscreen: boolean = false;
  private controller?: VideoSurfaceController;
  @State areaWidth: number = 0;
  @State areaHeight: number = 0;
  @State seeking: boolean = false;
  @State seekValue: number = 0;

  private surfaceWidth(): number {
    if (!this.state.videoWidth || !this.state.videoHeight) return this.areaWidth;

    const ratio = this.state.videoWidth / this.state.videoHeight;

    return this.state.contentFit === 'cover' ? Math.max(this.areaWidth, this.areaHeight * ratio) : Math.min(this.areaWidth, this.areaHeight * ratio);
  }

  private surfaceHeight(): number {
    if (!this.state.videoWidth || !this.state.videoHeight) return this.areaHeight;

    return (this.surfaceWidth() * this.state.videoHeight) / this.state.videoWidth;
  }

  private timecode(seconds: number): string {
    const time = Math.max(0, Math.floor(seconds));
    const minutes = Math.floor(time / 60);

    return `${minutes}:${String(time % 60).padStart(2, '0')}`;
  }

  aboutToAppear(): void {
    this.controller = new VideoSurfaceController(this.state, this.revision, this.inFullscreen);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.Center }) {
        XComponent({ type: XComponentType.SURFACE, controller: this.controller })
          .width(this.areaWidth > 0 && this.areaHeight > 0 ? this.surfaceWidth() : '100%')
          .height(this.areaWidth > 0 && this.areaHeight > 0 ? this.surfaceHeight() : '100%')
          .scale({
            x: this.state.contentFit === 'fill' && this.surfaceWidth() > 0 ? this.areaWidth / this.surfaceWidth() : 1,
            y: this.state.contentFit === 'fill' && this.surfaceHeight() > 0 ? this.areaHeight / this.surfaceHeight() : 1,
          })
          .translate({ x: this.state.contentPosition.dx ?? 0, y: this.state.contentPosition.dy ?? 0 });

        if (!this.state.frameReady) {
          // Keep the native surface visible so the decoder can produce the first frame.
          Stack()
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Black)
            .hitTestBehavior(HitTestMode.None);
        }
      }
      .width('100%')
      .height('100%')
      .clip(true)

      if (this.state.subtitle) {
        Text(this.state.subtitle)
          .fontColor(Color.White)
          .fontSize(18)
          .textAlign(TextAlign.Center)
          .backgroundColor('#99000000')
          .padding(8)
          .margin({ bottom: this.state.nativeControls ? 76 : 16 });
      }

      if ((this.state.nativeControls && this.state.buttonOptions.showBottomBar !== false) || this.inFullscreen) {
        Column({ space: 4 }) {
          Row({ space: 12 }) {
            if (this.state.buttonOptions.showPlayPause !== false) {
              Button(this.state.playbackRequested ? 'Ⅱ' : '▶')
                .accessibilityText(this.state.playbackRequested ? 'Pause' : 'Play')
                .onClick((): void => {
                  if (this.state.playbackRequested) this.state.player?.pause();
                  else this.state.player?.play();
                });
            }
            if (!this.state.requiresLinearPlayback && this.state.buttonOptions.showSeekBackward !== false) {
              Button('↶')
                .accessibilityText('Seek backward')
                .enabled(!this.state.isLive && this.state.duration > 0)
                .onClick((): void => this.state.player?.seekBy(-(this.state.player?.seekBackwardIncrement ?? 10)));
            }
            if (!this.state.requiresLinearPlayback && this.state.buttonOptions.showSeekForward !== false) {
              Button('↷')
                .accessibilityText('Seek forward')
                .enabled(!this.state.isLive && this.state.duration > 0)
                .onClick((): void => this.state.player?.seekBy(this.state.player?.seekForwardIncrement ?? 10));
            }
            Blank()
            if (this.inFullscreen || this.state.fullscreenOptions.enable !== false) {
              Button(this.inFullscreen ? '↙' : '⛶')
                .accessibilityText(this.inFullscreen ? 'Exit fullscreen' : 'Fullscreen')
                .onClick((): void => {
                  if (this.inFullscreen) this.state.exitFullscreen();
                  else this.state.enterFullscreen();
                });
            }
          }.width('100%')

          Row({ space: 8 }) {
            if (this.state.showsTimecodes) {
              Text(this.timecode(this.state.position))
                .fontColor(Color.White)
                .fontSize(12);
            }
            Slider({ value: this.seeking ? this.seekValue : this.state.position, min: 0, max: Math.max(1, this.state.duration), step: 0.1 })
              .layoutWeight(1)
              .enabled(!this.state.requiresLinearPlayback && !this.state.isLive && this.state.duration > 0)
              .onChange((value: number, mode: SliderChangeMode): void => {
                this.seekValue = value;
                this.seeking = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.state.player?.seek(value);
              })
            if (this.state.showsTimecodes) {
              Text(this.timecode(this.state.duration))
                .fontColor(Color.White)
                .fontSize(12);
            }
          }
        }
        .padding(12)
        .width('100%')
        .backgroundColor('#99000000');
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onAreaChange((_old: Area, area: Area): void => {
      this.areaWidth = Number(area.width);
      this.areaHeight = Number(area.height);
    });
  }
}
