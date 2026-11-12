/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface ExpoAVSessionControls {
  play(): void;
  pause(): void;
  seek?: (milliseconds: number) => void;
  fastForward?: (milliseconds?: number) => void;
  rewind?: (milliseconds?: number) => void;
}

export interface ExpoAVSessionOptions {
  readonly name: string;
  readonly type: avSession.AVSessionType;
}

const SESSION_NOT_FOUND = 6600102;

class SessionClientState {
  readonly context: common.UIAbilityContext;
  readonly options: ExpoAVSessionOptions;
  activation: number = 0;
  priority: number = 0;
  released: boolean = false;
  controls?: ExpoAVSessionControls;
  metadata?: avSession.AVMetadata;
  playback?: avSession.AVPlaybackState;
  metadataRevision: number = 0;
  playbackRevision: number = 0;
  launchAbility?: WantAgent;
  private defaultLaunchAbility?: WantAgent;

  constructor(context: common.UIAbilityContext, options: ExpoAVSessionOptions) {
    this.context = context;
    this.options = { name: options.name, type: options.type };
  }

  async launchTarget(): Promise<WantAgent> {
    if (this.launchAbility !== undefined) return this.launchAbility;
    if (this.defaultLaunchAbility === undefined) {
      const ability = this.context.abilityInfo;
      this.defaultLaunchAbility = await wantAgent.getWantAgent({
        wants: [{ bundleName: ability.bundleName, moduleName: ability.moduleName, abilityName: ability.name }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      });
    }

    return this.launchAbility ?? this.defaultLaunchAbility;
  }
}

class SessionPublication {
  readonly owner: SessionClientState;
  metadataRevision: number = -1;
  playbackRevision: number = -1;
  launchAbility?: WantAgent;

  constructor(owner: SessionClientState) {
    this.owner = owner;
  }
}

interface SessionControlBinding {
  owner: SessionClientState;
  controls: ExpoAVSessionControls;
  revision: number;
  play: () => void;
  pause: () => void;
  seek: (milliseconds: number) => void;
  fastForward: (milliseconds?: number) => void;
  rewind: (milliseconds?: number) => void;
}

class ExpoAVSessionCoordinator {
  private readonly clients = new Set<SessionClientState>();
  private activation: number = 0;
  private controlRevision: number = 0;
  private tail: Promise<void> = Promise.resolve();
  private session?: avSession.AVSession;
  private sessionOptions?: ExpoAVSessionOptions;
  private active: boolean = false;
  private retiring: boolean = false;
  private publication?: SessionPublication;
  private binding?: SessionControlBinding;

  activate(client: SessionClientState): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      if (client.released) return;
      if (client.metadata === undefined || client.playback === undefined) {
        throw new Error('Set AVSession metadata and playback state before activating.');
      }

      const previous = client.activation;
      client.activation = ++this.activation;
      this.clients.add(client);

      try {
        await this.publishWithRecovery();
      } catch (error) {
        if (previous === 0) this.clients.delete(client);
        client.activation = previous;

        try { await this.publishWithRecovery(); } catch (_) {}
        throw error as Error;
      }
    });
  }

  release(client: SessionClientState): Promise<void> {
    client.released = true;
    this.clients.delete(client);
    return client.activation === 0 ? Promise.resolve() : this.enqueue((): Promise<void> => this.publishWithRecovery());
  }

  update(client: SessionClientState): Promise<void> {
    return this.clients.has(client) ? this.enqueue((): Promise<void> => this.publishWithRecovery()) : Promise.resolve();
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.tail.then(operation);
    this.tail = next.catch((): void => {});
    return next;
  }

  private async publishWithRecovery(): Promise<void> {
    try {
      await this.publish();
    } catch (error) {
      if (this.session === undefined || (error as BusinessError | undefined)?.code !== SESSION_NOT_FOUND) throw error as Error;

      // The system can retire a session when its originating ability exits.
      this.clearSession();
      await this.publish();
    }
  }

  private owner(): SessionClientState | undefined {
    let selected: SessionClientState | undefined;
    this.clients.forEach((client: SessionClientState): void => {
      if (selected === undefined || client.priority > selected.priority ||
          (client.priority === selected.priority && client.activation > selected.activation)) {
        selected = client;
      }
    });

    return selected;
  }

  private async publish(): Promise<void> {
    if (this.retiring) await this.destroySession();

    const owner = this.owner();
    if (owner === undefined) {
      await this.destroySession();
      return;
    }

    const options = owner.options;
    if (this.sessionOptions !== undefined && (this.sessionOptions.name !== options.name || this.sessionOptions.type !== options.type)) {
      await this.destroySession();
      if (owner !== this.owner()) return;
    }
    const session = this.session ?? await avSession.createAVSession(owner.context, options.name, options.type);
    this.session = session;
    this.sessionOptions = options;
    if (owner !== this.owner()) return;

    if (this.publication?.owner !== owner) {
      this.unbindControls(session);
      this.publication = new SessionPublication(owner);
    }
    const published = this.publication;

    const metadataRevision = owner.metadataRevision;
    if (published.metadataRevision !== metadataRevision) {
      await session.setAVMetadata(owner.metadata!);
      published.metadataRevision = metadataRevision;
      if (owner !== this.owner()) return;
    }

    const playbackRevision = owner.playbackRevision;
    if (published.playbackRevision !== playbackRevision) {
      await session.setAVPlaybackState(owner.playback!);
      published.playbackRevision = playbackRevision;
      if (owner !== this.owner()) return;
    }

    const launchAbility = await owner.launchTarget();
    if (owner !== this.owner()) return;
    if (published.launchAbility !== launchAbility) {
      await session.setLaunchAbility(launchAbility);
      published.launchAbility = launchAbility;
      if (owner !== this.owner()) return;
    }

    this.bindControls(session, owner);
    if (!this.active) {
      await session.activate();
      this.active = true;
    }
  }

  private async destroySession(): Promise<void> {
    const session = this.session;
    if (session === undefined) return;

    this.retiring = true;
    this.unbindControls(session);

    // The destroy Promise can resolve before AVSessionKit frees the process slot.
    const controller = await session.getController();
    let onDestroyed: () => void = (): void => {};
    const destroyed = new Promise<void>((resolve): void => { onDestroyed = resolve; });

    try {
      controller.on('sessionDestroy', onDestroyed);
      await session.destroy();
      await destroyed;
      this.clearSession();
    } finally {
      try { controller.off('sessionDestroy', onDestroyed); } catch (_) {}
      try { await controller.destroy(); } catch (_) {}
    }
  }

  private clearSession(): void {
    this.session = undefined;
    this.sessionOptions = undefined;
    this.active = false;
    this.retiring = false;
    this.publication = undefined;
    this.binding = undefined;
  }

  private currentControls(revision: number): ExpoAVSessionControls | undefined {
    const binding = this.binding;
    if (binding?.revision !== revision || binding.owner !== this.owner() || binding.owner.controls !== binding.controls) {
      return undefined;
    }

    return binding.controls;
  }

  private bindControls(session: avSession.AVSession, owner: SessionClientState): void {
    const controls = owner.controls;
    if (this.binding?.owner === owner && this.binding?.controls === controls) return;

    this.unbindControls(session);
    if (controls === undefined) return;

    const revision = ++this.controlRevision;
    const binding: SessionControlBinding = {
      owner,
      controls,
      revision,
      play: (): void => this.currentControls(revision)?.play(),
      pause: (): void => this.currentControls(revision)?.pause(),
      seek: (time: number): void => this.currentControls(revision)?.seek?.(time),
      fastForward: (time?: number): void => this.currentControls(revision)?.fastForward?.(time),
      rewind: (time?: number): void => this.currentControls(revision)?.rewind?.(time),
    };
    this.binding = binding;

    try {
      session.on('play', binding.play);
      session.on('pause', binding.pause);
      if (controls.seek !== undefined) session.on('seek', binding.seek);
      if (controls.fastForward !== undefined) session.on('fastForward', binding.fastForward);
      if (controls.rewind !== undefined) session.on('rewind', binding.rewind);
    } catch (error) {
      this.unbindControls(session);
      throw error as Error;
    }
  }

  private unbindControls(session: avSession.AVSession): void {
    const binding = this.binding;
    if (binding === undefined) return;

    this.binding = undefined;
    try { session.off('play', binding.play); } catch (_) {}
    try { session.off('pause', binding.pause); } catch (_) {}
    if (binding.controls.seek !== undefined) {
      try { session.off('seek', binding.seek); } catch (_) {}
    }
    if (binding.controls.fastForward !== undefined) {
      try { session.off('fastForward', binding.fastForward); } catch (_) {}
    }
    if (binding.controls.rewind !== undefined) {
      try { session.off('rewind', binding.rewind); } catch (_) {}
    }
  }
}

// AVSessionKit admits one publisher per process. Audio and Video share this queue.
const coordinator = new ExpoAVSessionCoordinator();

/** A media module's state and controls within the process's shared AVSession. */
export class ExpoAVSessionClient {
  private state?: SessionClientState;
  private destruction?: Promise<void>;

  constructor(context: common.UIAbilityContext, options: ExpoAVSessionOptions = { name: 'ExpoMedia', type: 'audio' }) {
    this.state = new SessionClientState(context, options);
  }

  setControls(controls: ExpoAVSessionControls): Promise<void> {
    const state = this.state;
    if (state === undefined || state.released) return Promise.resolve();
    state.controls = controls;
    return coordinator.update(state);
  }

  setAVMetadata(metadata: avSession.AVMetadata): Promise<void> {
    const state = this.state;
    if (state === undefined || state.released) return Promise.resolve();
    state.metadata = metadata;
    state.metadataRevision += 1;
    return coordinator.update(state);
  }

  setAVPlaybackState(playback: avSession.AVPlaybackState, priority: number = 0): Promise<void> {
    const state = this.state;
    if (state === undefined || state.released) return Promise.resolve();
    state.playback = playback;
    state.priority = priority;
    state.playbackRevision += 1;
    return coordinator.update(state);
  }

  setLaunchAbility(ability: WantAgent): Promise<void> {
    const state = this.state;
    if (state === undefined || state.released) return Promise.resolve();
    state.launchAbility = ability;
    return coordinator.update(state);
  }

  activate(): Promise<void> {
    const state = this.state;
    return state === undefined ? Promise.resolve() : coordinator.activate(state);
  }

  destroy(): Promise<void> {
    const state = this.state;
    if (state === undefined) return Promise.resolve();
    if (this.destruction === undefined) {
      this.destruction = coordinator.release(state).then((): void => {
        this.state = undefined;
        this.destruction = undefined;
      }, (error: Error): void => {
        this.destruction = undefined;
        throw error;
      });
    }
    return this.destruction;
  }
}
