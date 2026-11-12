/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import { PiPWindow } from '@kit.ArkUI';
import { ExpoModuleError } from '@expo-harmony/expo-modules-core';

export function isPictureInPictureSupported(): boolean {
  return canIUse('SystemCapability.Window.SessionManager') && PiPWindow.isPiPEnabled();
}

export class VideoPictureInPicture {
  private target?: XComponentController;
  private owner?: XComponentController;
  private controller?: PiPWindow.PiPController;
  private tail: Promise<void> = Promise.resolve();
  private autoStart: boolean = false;
  private active: boolean = false;
  private starting: boolean = false;
  private stopping: boolean = false;
  private width: number = 0;
  private height: number = 0;
  private playing: boolean = false;
  private readonly context: common.UIAbilityContext;
  private readonly onState: (active: boolean, event?: string) => void;
  private readonly onPlayPause: (play: boolean) => void;

  constructor(
    context: common.UIAbilityContext,
    onState: (active: boolean, event?: string) => void,
    onPlayPause: (play: boolean) => void,
  ) {
    this.context = context;
    this.onState = onState;
    this.onPlayPause = onPlayPause;
  }

  configure(target: XComponentController | undefined, autoStart: boolean): void {
    if (this.target === target && this.autoStart === autoStart) return;

    this.target = target;
    this.autoStart = autoStart;

    this.enqueue(async (): Promise<void> => {
      if (this.owner !== this.target) await this.release();
      if (this.target && this.autoStart && isPictureInPictureSupported()) {
        const controller = await this.getController(this.target);
        controller?.setAutoStartEnabled(this.autoStart);
      } else {
        this.controller?.setAutoStartEnabled(false);
      }
    }).catch((error: Error): void => console.warn(`ExpoVideo: PiP configuration failed: ${error.message}`));
  }

  update(width: number, height: number, playing: boolean): void {
    const controller = this.controller;
    try {
      if ((this.width !== width || this.height !== height) && width > 0 && height > 0) {
        controller?.updateContentSize(Math.round(width), Math.round(height));
      }
      if (this.active && this.playing !== playing) this.updatePlaybackStatus(playing);
    } catch (error) {
      console.warn(`ExpoVideo: PiP controls update failed: ${String(error)}`);
    }
    this.width = width;
    this.height = height;
    this.playing = playing;
  }

  start(): Promise<void> {
    const target = this.target;
    return this.enqueue(async (): Promise<void> => {
      if (!isPictureInPictureSupported()) throw new ExpoModuleError('ERR_VIDEO_PIP_UNAVAILABLE', 'Picture in Picture is unavailable on this device.');
      if (!target || this.target !== target) {
        throw new ExpoModuleError('ERR_VIDEO_PIP_NOT_READY', 'Picture in Picture requires a ready VideoView surface.');
      }
      if (this.owner !== target) await this.release();
      const controller = await this.getController(target);
      if (!controller) throw new ExpoModuleError('ERR_VIDEO_PIP_NOT_READY', 'The VideoView surface changed while starting Picture in Picture.');
      if (this.active || this.starting) return;
      this.starting = true;
      this.onState(true);
      try {
        await controller.startPiP();
      } catch (error) {
        this.finish();
        throw error as Error;
      }
    });
  }

  stop(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      if (this.controller) await this.stopController(this.controller);
    });
  }

  private enqueue(action: () => Promise<void>): Promise<void> {
    const next = this.tail.then(action);
    this.tail = next.catch((): void => {});
    return next;
  }

  private async getController(target: XComponentController): Promise<PiPWindow.PiPController | undefined> {
    if (this.controller && this.owner === target) return this.controller;
    if (this.target !== target) return undefined;

    const config: PiPWindow.PiPConfiguration = {
      context: this.context,
      componentController: target,
      templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
    };
    if (this.width > 0 && this.height > 0) {
      config.contentWidth = Math.round(this.width);
      config.contentHeight = Math.round(this.height);
    }
    const controller = await PiPWindow.create(config);
    if (this.target !== target) return undefined;

    this.owner = target;
    this.controller = controller;
    controller.on('stateChange', (state: PiPWindow.PiPState, _reason: string): void => {
      if (this.controller !== controller) return;
      const detached = this.target !== target;
      if (state === PiPWindow.PiPState.ABOUT_TO_START) {
        if (this.starting || this.active) return;
        this.starting = true;
        if (!detached) this.onState(true);
      } else if (state === PiPWindow.PiPState.STARTED && !this.active) {
        if (detached) {
          this.starting = true;
        } else {
          this.starting = false;
          this.active = true;
          this.onState(true, 'onPictureInPictureStart');
          this.updatePlaybackStatus(this.playing);
        }
      } else if (state === PiPWindow.PiPState.ABOUT_TO_STOP) {
        this.stopping = true;
      } else if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ERROR) {
        this.finish();
      }
      if (detached && [PiPWindow.PiPState.STARTED, PiPWindow.PiPState.STOPPED, PiPWindow.PiPState.ERROR].includes(state)) {
        // A native auto-start can complete after the surface has been detached.
        this.enqueue(async (): Promise<void> => {
          if (this.controller === controller && this.owner !== this.target) await this.release();
        }).catch((error: Error): void => console.warn(`ExpoVideo: PiP cleanup failed: ${error.message}`));
      }
    });
    controller.on('controlEvent', (event: PiPWindow.ControlEventParam): void => {
      if (this.controller !== controller || this.target !== target || !this.active) return;
      if (event.controlType === PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
        this.onPlayPause(event.status === PiPWindow.PiPControlStatus.PLAY);
      }
    });

    return controller;
  }

  private updatePlaybackStatus(playing: boolean): void {
    this.controller?.updatePiPControlStatus(
      PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
      playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE,
    );
  }

  private finish(): void {
    const announced = this.active;
    const pending = this.starting;
    this.active = false;
    this.starting = false;
    this.stopping = false;
    if (announced || pending) this.onState(false, announced ? 'onPictureInPictureStop' : undefined);
  }

  private async stopController(controller: PiPWindow.PiPController): Promise<void> {
    if ((!this.active && !this.starting) || this.stopping) return;
    this.stopping = true;
    try {
      await controller.stopPiP();
    } catch (error) {
      this.stopping = false;
      throw error as Error;
    }
  }

  private async release(): Promise<void> {
    const controller = this.controller;
    if (!controller) return;
    controller.setAutoStartEnabled(false);
    // Keep listening if a native start is still in progress and rejects a stop request.
    await this.stopController(controller);
    this.controller = undefined;
    this.owner = undefined;
    this.finish();
    controller.off('stateChange');
    controller.off('controlEvent');
  }
}
