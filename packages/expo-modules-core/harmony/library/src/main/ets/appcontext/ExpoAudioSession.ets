/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// WorkScheduler cannot load AudioKit.
import lazy { audio } from '@kit.AudioKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import deviceInfo from '@ohos.deviceInfo';

export interface ExpoAudioSessionOptions {
  readonly concurrencyMode: audio.AudioConcurrencyMode;
  readonly scene?: audio.AudioSessionScene;
  readonly outputDevice?: audio.DeviceType;
}

interface AudioSessionLease {
  readonly options: ExpoAudioSessionOptions;
  readonly revision: number;
}

// AudioKit reports an invalid state if a scene cannot be updated while active.
const AUDIO_SESSION_INVALID_STATE = 6800103;

class AudioSessionCoordinator {
  private readonly leases = new Map<ExpoAudioSessionClient, AudioSessionLease>();
  private tail: Promise<void> = Promise.resolve();
  private revision: number = 0;
  private manager?: audio.AudioSessionManager;
  private ownsSession: boolean = false;
  private appliedMode?: audio.AudioConcurrencyMode;
  private appliedScene?: audio.AudioSessionScene;
  private originalOutputDevice?: audio.DeviceType;
  private appliedOutputDevice?: audio.DeviceType;
  isDeactivating: boolean = false;

  acquire(client: ExpoAudioSessionClient, options: ExpoAudioSessionOptions): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      this.manager ??= audio.getAudioManager().getSessionManager();
      const previous = this.leases.get(client);

      if (previous === undefined || previous.options.concurrencyMode !== options.concurrencyMode ||
          previous.options.scene !== options.scene || previous.options.outputDevice !== options.outputDevice) {
        this.leases.set(client, { options, revision: ++this.revision });
      }

      let deactivated = false;
      try {
        await this.reconcile(true, (): void => { deactivated = true; });
      } catch (error) {
        if (previous === undefined) this.leases.delete(client);
        else this.leases.set(client, previous);

        // A failed update can already have changed the scene or output device.
        try { await this.reconcile(deactivated); } catch (_) {}
        throw error as Error;
      }
    });
  }

  release(client: ExpoAudioSessionClient): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      this.leases.delete(client);
      await this.reconcile(false);
    });
  }

  isActive(client: ExpoAudioSessionClient): boolean {
    return this.leases.has(client) && (this.manager?.isAudioSessionActivated() ?? false);
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.tail.then(operation);
    this.tail = next.catch((): void => {});
    return next;
  }

  private desired(): ExpoAudioSessionOptions | undefined {
    if (this.leases.size === 0) return undefined;

    const concurrencyOrder: audio.AudioConcurrencyMode[] = [
      audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT,
      audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS,
      audio.AudioConcurrencyMode.CONCURRENCY_DUCK_OTHERS,
      audio.AudioConcurrencyMode.CONCURRENCY_PAUSE_OTHERS,
    ];
    let priority = 0;
    let scene: AudioSessionLease | undefined;
    let route: AudioSessionLease | undefined;

    for (const lease of this.leases.values()) {
      const options = lease.options;
      priority = Math.max(priority, concurrencyOrder.indexOf(options.concurrencyMode));
      if (options.scene !== undefined && (scene === undefined || scene.revision < lease.revision)) scene = lease;
      if (options.outputDevice !== undefined && (route === undefined || route.revision < lease.revision)) route = lease;
    }

    return {
      concurrencyMode: concurrencyOrder[priority],
      scene: route?.options.scene ?? scene?.options.scene,
      outputDevice: route?.options.outputDevice,
    };
  }

  private async reconcile(mayActivate: boolean, onDeactivated?: () => void): Promise<void> {
    const manager = this.manager;
    if (manager === undefined) return;

    const desired = this.desired();
    const active = manager.isAudioSessionActivated();

    if (desired === undefined) {
      if (active && this.ownsSession) await this.deactivate(manager);
      this.ownsSession = false;
      this.appliedMode = undefined;
    } else if (!active && !mayActivate) {
      // Releasing a lease must not take focus back from a system interruption.
      return;
    }

    let reactivating = false;
    if (deviceInfo.sdkApiVersion >= 20) {
      const scene = desired?.scene ?? (this.appliedScene === undefined ? undefined : audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA);
      if (scene !== undefined && scene !== this.appliedScene) {
        try {
          manager.setAudioSessionScene(scene);
        } catch (error) {
          if (!active || !this.ownsSession || (error as BusinessError | undefined)?.code !== AUDIO_SESSION_INVALID_STATE) {
            throw error as Error;
          }
          // If the live scene change is rejected, set it between activations.
          await this.deactivate(manager);
          onDeactivated?.();
          reactivating = true;
          manager.setAudioSessionScene(scene);
        }
        this.appliedScene = scene;
        this.appliedMode = undefined;
      }

      if (desired?.outputDevice !== undefined && this.originalOutputDevice === undefined) {
        this.originalOutputDevice = manager.getDefaultOutputDevice();
        this.appliedOutputDevice = this.originalOutputDevice;
      }

      const device = desired?.outputDevice ?? this.originalOutputDevice;
      if (device !== undefined && device !== this.appliedOutputDevice) {
        await manager.setDefaultOutputDevice(device);
        this.appliedOutputDevice = device;
        this.appliedMode = undefined;
      }
      if (desired?.outputDevice === undefined) {
        this.originalOutputDevice = undefined;
        this.appliedOutputDevice = undefined;
      }
    }

    if (desired === undefined) {
      this.appliedScene = undefined;
      return;
    }

    const activated = manager.isAudioSessionActivated();
    if (!activated && !mayActivate && !reactivating) return;

    if (!activated || this.appliedMode !== desired.concurrencyMode) {
      this.appliedMode = undefined;
      await manager.activateAudioSession({ concurrencyMode: desired.concurrencyMode });
      this.ownsSession = true;
      this.appliedMode = desired.concurrencyMode;
    }
  }

  private async deactivate(manager: audio.AudioSessionManager): Promise<void> {
    this.isDeactivating = true;
    try {
      await manager.deactivateAudioSession();
    } finally {
      this.isDeactivating = false;
    }
  }
}

const coordinator = new AudioSessionCoordinator();

/** A module's lease on the app-level AudioKit focus session on the UI actor. */
export class ExpoAudioSessionClient {
  static get isDeactivating(): boolean { return coordinator.isDeactivating; }

  acquire(options: ExpoAudioSessionOptions): Promise<void> {
    if (deviceInfo.sdkApiVersion < 20 && (options.scene !== undefined || options.outputDevice !== undefined)) {
      return Promise.reject(new Error('Audio session scene and output device require HarmonyOS API 20 or newer.'));
    }
    return coordinator.acquire(this, {
      concurrencyMode: options.concurrencyMode,
      scene: options.scene,
      outputDevice: options.outputDevice,
    });
  }

  release(): Promise<void> { return coordinator.release(this); }

  isActive(): boolean { return coordinator.isActive(this); }
}
