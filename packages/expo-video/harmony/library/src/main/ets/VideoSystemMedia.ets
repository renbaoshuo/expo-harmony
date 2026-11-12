/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ExpoAVSessionClient } from '@expo-harmony/expo-modules-core';
import { VideoPlayer } from './VideoPlayer';
import { VideoSource } from './VideoSource';

export function supportsBackgroundVideoPlayback(): boolean {
  return deviceInfo.sdkApiVersion >= 22 &&
    canIUse('SystemCapability.Multimedia.AVSession.Core') &&
    canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask');
}

export class VideoSystemMedia {
  private readonly context: common.UIAbilityContext;
  private session?: ExpoAVSessionClient;
  private sessionActivated: boolean = false;
  private sessionRetiring: boolean = false;
  private taskId?: number;
  private stoppingTaskId?: number;
  private selected?: VideoPlayer;
  private desired?: VideoPlayer;
  private failedSessionOwner?: VideoPlayer;
  private taskDesired: boolean = false;
  private taskDenied: boolean = false;
  private listening: boolean = false;
  private work?: Promise<void>;
  private dirty: boolean = false;
  private destroyed: boolean = false;
  private source?: VideoSource;
  private assetId: number = 0;
  private lastDuration: number = -1;
  private lastState?: avSession.PlaybackState;
  private lastRate?: number;
  private lastPosition?: number;
  private lastUpdate: number = 0;
  private readonly onTaskCancelled = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (info.id !== this.taskId) return;
    this.taskId = undefined;
    if (info.id === this.stoppingTaskId) return;
    this.taskDenied = true;
    this.selected?.setBackgroundPlaybackAllowed(false);
  };

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  update(players: Set<VideoPlayer>): void {
    if (this.destroyed) return;

    let owner: VideoPlayer | undefined;
    let priority = -1;
    players.forEach((player: VideoPlayer): void => {
      if (!player.source || !player.isAvailable || player.status === 'error') return;
      if (!player.showNowPlayingNotification && !(player.staysActiveInBackground && player.playbackRequested)) return;
      const candidate = (player.staysActiveInBackground && player.playbackRequested ? 4 : 0) +
        (player.playing ? 2 : 0) + (player === this.desired ? 1 : 0);
      if (candidate > priority) {
        owner = player;
        priority = candidate;
      }
    });
    const taskDesired = owner?.staysActiveInBackground === true &&
      owner.playbackRequested && owner.playbackPrepared;
    if (owner !== this.desired || taskDesired !== this.taskDesired) {
      this.taskDenied = false;
      this.failedSessionOwner = undefined;
    }
    this.desired = owner;
    this.taskDesired = taskDesired;
    if (!this.desired && !this.session && this.taskId === undefined && !this.work) return;

    void this.schedule();
  }

  foreground(): void {
    this.taskDenied = false;
    this.failedSessionOwner = undefined;
  }

  destroy(): Promise<void> {
    this.destroyed = true;
    this.desired = undefined;
    this.taskDesired = false;
    return this.schedule();
  }

  private schedule(): Promise<void> {
    this.dirty = true;
    if (!this.work) this.work = Promise.resolve().then((): Promise<void> => this.sync());
    return this.work;
  }

  private async sync(): Promise<void> {
    try {
      while (this.dirty) {
        this.dirty = false;
        try {
          await this.apply();
        } catch (error) {
          console.warn(`ExpoVideo: system media controls failed: ${String(error)}`);
        }
      }
    } finally {
      this.work = undefined;
    }
  }

  private async apply(): Promise<void> {
    const owner = this.desired;
    const needsTask = this.taskDesired && !this.taskDenied;
    if (!owner) {
      this.selected?.setBackgroundPlaybackAllowed(false);
      this.selected = undefined;
      try {
        await this.stopTask();
      } finally {
        await this.destroySession();
      }
      return;
    }

    if (this.selected !== owner || !needsTask) {
      this.selected?.setBackgroundPlaybackAllowed(false);
      await this.stopTask();
    }
    if (owner !== this.desired) return;

    this.selected = owner;
    if (owner === this.failedSessionOwner) return;

    let session: ExpoAVSessionClient;
    try {
      session = await this.ensureSession();
    } catch (error) {
      this.failedSessionOwner = owner;
      throw error as Error;
    }
    if (owner !== this.desired || !owner.source) return;
    if (owner.source !== this.source || owner.duration !== this.lastDuration) {
      if (owner.source !== this.source) this.assetId += 1;
      const source = owner.source;
      const duration = owner.duration;
      const metadata = owner.source.metadata;
      const details: avSession.AVMetadata = { assetId: String(this.assetId) };
      if (metadata?.title !== undefined) details.title = metadata.title;
      if (metadata?.artist !== undefined) details.artist = metadata.artist;
      if (metadata?.artwork !== undefined) details.mediaImage = metadata.artwork;
      if (!owner.isLive && owner.duration > 0) details.duration = Math.round(owner.duration * 1000);
      await session.setAVMetadata(details);
      this.source = source;
      this.lastDuration = duration;
    }
    const state = owner.playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
      (owner.status === 'loading' && owner.playbackRequested ? avSession.PlaybackState.PLAYBACK_STATE_BUFFERING :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
    const rate = owner.playing ? owner.playbackRate : 0;
    const now = Date.now();
    const position = Math.round(owner.currentTime * 1000);
    if (state !== this.lastState || rate !== this.lastRate || now - this.lastUpdate >= 1000 ||
        (!owner.playing && this.lastPosition !== position)) {
      await session.setAVPlaybackState({
        state,
        speed: rate,
        position: { elapsedTime: position, updateTime: now },
        bufferedTime: Math.max(0, Math.round(owner.bufferedPosition * 1000)),
      }, owner.playing ? 1 : 0);
      this.lastState = state;
      this.lastRate = rate;
      this.lastPosition = position;
      this.lastUpdate = now;
    }
    if (!this.sessionActivated && owner === this.desired) {
      try {
        await session.activate();
        this.sessionActivated = true;
      } catch (error) {
        this.failedSessionOwner = owner;
        await this.destroySession().catch((): void => {});
        throw error as Error;
      }
    }
    if (owner !== this.desired || !this.taskDesired || !needsTask) return;

    if (this.taskId === undefined) {
      try {
        const request = new backgroundTaskManager.ContinuousTaskRequest();
        request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_AUDIO_PLAYBACK];
        request.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_AVSESSION_AUDIO_PLAYBACK];
        request.wantAgent = await this.createWantAgent();
        if (owner !== this.desired || !this.taskDesired) return;
        if (!this.listening) {
          backgroundTaskManager.on('continuousTaskCancel', this.onTaskCancelled);
          this.listening = true;
        }

        const task = await backgroundTaskManager.startBackgroundRunning(this.context, request);
        this.taskId = task.continuousTaskId;
      } catch (error) {
        this.taskDenied = true;
        console.warn(`ExpoVideo: background playback needs the audioPlayback background mode and permission: ${String(error)}`);
      }
    }
    owner.setBackgroundPlaybackAllowed(owner === this.desired && this.taskDesired && this.taskId !== undefined);
  }

  private async ensureSession(): Promise<ExpoAVSessionClient> {
    if (this.sessionRetiring) await this.destroySession();
    if (this.session) return this.session;
    const session = new ExpoAVSessionClient(this.context, { name: 'ExpoVideo', type: 'video' });
    try {
      await session.setControls({
        play: (): void => { if (this.selected === this.desired) this.selected?.play(); },
        pause: (): void => { if (this.selected === this.desired) this.selected?.pause(); },
        seek: (milliseconds: number): void => {
          if (this.selected && this.selected === this.desired && !this.selected.isLive && Number.isFinite(milliseconds)) {
            this.selected.seek(milliseconds / 1000);
          }
        },
      });
    } catch (error) {
      await session.destroy().catch((): void => {});
      throw error as Error;
    }

    this.session = session;
    return session;
  }

  private createWantAgent(): Promise<WantAgent> {
    const ability = this.context.abilityInfo;
    return wantAgent.getWantAgent({
      wants: [{ bundleName: ability.bundleName, moduleName: ability.moduleName, abilityName: ability.name }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    });
  }

  private async stopTask(): Promise<void> {
    const taskId = this.taskId;
    if (taskId === undefined) return;
    this.stoppingTaskId = taskId;
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context, taskId);
      this.taskId = undefined;
    } finally {
      this.stoppingTaskId = undefined;
    }
  }

  private async destroySession(): Promise<void> {
    if (this.listening) {
      backgroundTaskManager.off('continuousTaskCancel', this.onTaskCancelled);
      this.listening = false;
    }

    const session = this.session;
    if (!session) return;
    this.sessionRetiring = true;
    await session.destroy();
    this.session = undefined;
    this.sessionActivated = false;
    this.sessionRetiring = false;
    this.source = undefined;
    this.lastDuration = -1;
    this.lastState = undefined;
  }
}
