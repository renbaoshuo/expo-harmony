/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { audio } from '@kit.AudioKit';
import { ExpoAudioSessionClient } from '@expo-harmony/expo-modules-core';

export interface VideoAudioParticipant {
  audioMixingMode: string;
  audioIsAudible(): boolean;
  sessionFocusChanged(hint: audio.AudioSessionStateChangeHint): void;
}

const MIXING_PRIORITY: string[] = ['mixWithOthers', 'duckOthers', 'auto', 'doNotMix'];

export class VideoAudioSession {
  private readonly manager: audio.AudioSessionManager = audio.getAudioManager().getSessionManager();
  private readonly session: ExpoAudioSessionClient = new ExpoAudioSessionClient();
  private readonly players: Set<VideoAudioParticipant> = new Set<VideoAudioParticipant>();
  private readonly active: Set<VideoAudioParticipant> = new Set<VideoAudioParticipant>();
  private tail: Promise<void> = Promise.resolve();
  private listening: boolean = false;
  private destroyed: boolean = false;
  private readonly onState = (event: audio.AudioSessionStateChangedEvent): void => {
    if (ExpoAudioSessionClient.isDeactivating) return;

    const hint = event.stateChangeHint;

    // The system applies session duck/unduck itself. Applying volume again would double-duck.
    if (
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_DUCK ||
      hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_UNDUCK
    )
      return;

    const affected = hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME ? this.players : this.active;
    Array.from(affected).forEach((player: VideoAudioParticipant): void => player.sessionFocusChanged(hint));
  };

  add(player: VideoAudioParticipant): void {
    if (this.destroyed) return;
    if (!this.listening) {
      this.manager.on('audioSessionStateChanged', this.onState);
      this.listening = true;
    }
    this.players.add(player);
  }

  remove(player: VideoAudioParticipant): void {
    if (!this.players.delete(player)) return;
    this.update(player, false).catch((error: Error): void => console.warn(`ExpoVideo: audio session cleanup failed: ${error.message}`));
    if (this.players.size === 0) this.stopListening();
  }

  private stopListening(): void {
    if (this.listening) {
      this.manager.off('audioSessionStateChanged', this.onState);
      this.listening = false;
    }
  }

  destroy(): Promise<void> {
    this.destroyed = true;
    this.players.clear();
    this.active.clear();
    this.stopListening();
    this.tail = this.tail
      .then((): Promise<void> => this.session.release())
      .catch((error: Error): void => console.warn(`ExpoVideo: audio session cleanup failed: ${error.message}`));

    return this.tail;
  }

  update(player: VideoAudioParticipant, playing: boolean, retainingFocus: boolean = false): Promise<void> {
    if (this.destroyed) return Promise.resolve();
    if (playing && this.players.has(player)) this.active.add(player);
    else if (!retainingFocus || !this.players.has(player)) this.active.delete(player);

    const next = this.tail.then(async (): Promise<void> => {
      if (this.active.size === 0) {
        await this.session.release();
        return;
      }
      // Keep an interrupted player's lease until the native session can resume.
      if (retainingFocus && !this.session.isActive()) return;

      let priority = 0;
      let audible = false;
      this.active.forEach((candidate: VideoAudioParticipant): void => {
        priority = Math.max(priority, MIXING_PRIORITY.indexOf(candidate.audioMixingMode));
        audible = audible || candidate.audioIsAudible();
      });

      const mode = MIXING_PRIORITY[priority];
      let concurrency = audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS;
      if (mode === 'doNotMix' || (mode === 'auto' && audible)) concurrency = audio.AudioConcurrencyMode.CONCURRENCY_PAUSE_OTHERS;
      else if (mode === 'duckOthers' && audible) concurrency = audio.AudioConcurrencyMode.CONCURRENCY_DUCK_OTHERS;
      await this.session.acquire({
        concurrencyMode: concurrency,
        scene: audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA,
      });
    });

    this.tail = next.catch((): void => {});

    return next;
  }
}
