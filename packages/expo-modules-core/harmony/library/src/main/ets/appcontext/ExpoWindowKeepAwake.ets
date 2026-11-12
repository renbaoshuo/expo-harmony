/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { window } from '@kit.ArkUI';

class WindowKeepAwakeState {
  readonly id: number;
  readonly owners: Set<Object> = new Set<Object>();
  target: window.Window;
  pending: Promise<void> = Promise.resolve();
  ownsFlag: boolean = false;
  closed: boolean = false;
  private readonly listenerTarget: window.Window;
  private onWindowEvent?: (event: window.WindowEventType) => void;

  constructor(id: number, target: window.Window) {
    this.id = id;
    this.target = target;
    this.listenerTarget = target;
  }

  observeDestruction(onDestroy: () => void): void {
    const listener = (event: window.WindowEventType): void => {
      if (event === window.WindowEventType.WINDOW_DESTROYED) onDestroy();
    };

    try {
      this.listenerTarget.on('windowEvent', listener);
      this.onWindowEvent = listener;
    } catch (error) {
      console.warn(`Unable to observe Expo keep-screen-on window destruction: ${String(error)}`);
    }
  }

  close(): void {
    this.closed = true;
    this.owners.clear();

    if (this.onWindowEvent === undefined) return;

    try {
      this.listenerTarget.off('windowEvent', this.onWindowEvent);
    } catch (_) {
      // The window can be gone before its destruction event reaches the UI actor.
    }

    this.onWindowEvent = undefined;
  }
}

/** Coordinates Expo callers writing the same ArkUI window's keep-screen-on flag. */
export class ExpoWindowKeepAwake {
  private static readonly states: Map<number, WindowKeepAwakeState> = new Map<number, WindowKeepAwakeState>();
  private static readonly targets: WeakMap<window.Window, WindowKeepAwakeState> = new WeakMap<window.Window, WindowKeepAwakeState>();

  /** Acquires or refreshes a lease for this owner. An unsuccessful first acquire can be cleaned up with release. */
  static async acquire(target: window.Window, owner: Object): Promise<void> {
    const id: number = target.getWindowProperties().id;
    let state: WindowKeepAwakeState | undefined = ExpoWindowKeepAwake.states.get(id);

    if (state === undefined) {
      const created = new WindowKeepAwakeState(id, target);
      ExpoWindowKeepAwake.states.set(id, created);
      created.observeDestruction((): void => ExpoWindowKeepAwake.close(created));
      state = created;
    }
    ExpoWindowKeepAwake.targets.set(target, state);

    const lease: WindowKeepAwakeState = state;
    await ExpoWindowKeepAwake.serialize(lease, async (): Promise<void> => {
      if (lease.closed) throw new Error('The Expo keep-screen-on window was destroyed.');

      const awake: boolean = target.getWindowProperties().isKeepScreenOn;
      lease.target = target;
      if (!awake) {
        lease.ownsFlag = true;

        try {
          await target.setWindowKeepScreenOn(true);
        } catch (error) {
          if (lease.owners.size === 0) {
            try {
              await ExpoWindowKeepAwake.restore(lease);
            } catch (cleanupError) {
              console.warn(`Unable to roll back Expo keep-screen-on: ${String(cleanupError)}`);
            }
          }
          throw error as Error;
        }
      }

      if (lease.closed) throw new Error('The Expo keep-screen-on window was destroyed.');
      lease.owners.add(owner);
    });
  }

  /** Releases this owner's lease. A failed final write retains the lease so callers can retry. */
  static async release(target: window.Window, owner: Object): Promise<void> {
    const known: WindowKeepAwakeState | undefined = ExpoWindowKeepAwake.targets.get(target);
    const state: WindowKeepAwakeState | undefined = known ?? ExpoWindowKeepAwake.states.get(target.getWindowProperties().id);
    if (state === undefined || state.closed) return;

    await ExpoWindowKeepAwake.serialize(state, async (): Promise<void> => {
      if (state.closed || (state.owners.size > 0 && !state.owners.has(owner))) return;

      if (known === undefined) state.target = target;
      if (state.owners.size <= 1) await ExpoWindowKeepAwake.restore(state);
      state.owners.delete(owner);
    });
  }

  private static async restore(state: WindowKeepAwakeState): Promise<void> {
    if (state.closed || !state.ownsFlag) return;
    if (state.target.getWindowProperties().isKeepScreenOn) await state.target.setWindowKeepScreenOn(false);
    state.ownsFlag = false;
  }

  private static async serialize(state: WindowKeepAwakeState, task: () => Promise<void>): Promise<void> {
    const result: Promise<void> = state.pending.then(task);
    const tail: Promise<void> = result.catch((): void => {});
    state.pending = tail;

    try {
      await result;
    } finally {
      if (state.pending === tail && state.owners.size === 0 && !state.ownsFlag) ExpoWindowKeepAwake.close(state);
    }
  }

  private static close(state: WindowKeepAwakeState): void {
    if (ExpoWindowKeepAwake.states.get(state.id) === state) ExpoWindowKeepAwake.states.delete(state.id);
    if (!state.closed) state.close();
  }
}
