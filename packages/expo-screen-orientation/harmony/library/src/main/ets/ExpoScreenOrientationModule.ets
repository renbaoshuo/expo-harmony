/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { display, window } from '@kit.ArkUI';
import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import {
  canObserveWindowDisplayChange,
  fromPreferredOrientation,
  Orientation,
  OrientationLock,
  readOrientation,
  requireOrientationLockSupport,
  requirePlatformOrientation,
  supportsOrientationLock,
  toPreferredOrientation,
} from './ScreenOrientation';

const ORIENTATION_EVENT = 'expoDidUpdateDimensions';

interface OrientationInfo {
  orientation: Orientation;
}

interface OrientationChangeEvent {
  orientationLock: OrientationLock;
  orientationInfo: OrientationInfo;
}

interface AppliedOrientation {
  owner: ExpoScreenOrientationModule;
  value: window.Orientation;
}

interface WindowOrientations {
  target: window.Window;
  original: window.Orientation;
  locks: AppliedOrientation[];
}

// Expo runtimes attached to the same window share a single native orientation policy.
const windowOrientations: Map<number, WindowOrientations> = new Map();
let pendingWindowOperation: Promise<void> = Promise.resolve();

export class ExpoScreenOrientationModule extends ExpoModule {
  private cleanup: Promise<void> | null = null;
  private destroyed: boolean = false;
  private stage: window.WindowStage | null = null;
  private generation: number = 0;
  private observing: boolean = false;
  private lastOrientation: Orientation = Orientation.UNKNOWN;
  private stopObservingWindow?: () => void;

  definition(): ExpoModuleDefinition {
    return (
      new ExpoModuleDefinition()
        .name('ExpoScreenOrientation')
        .events([ORIENTATION_EVENT])
        .asyncFunction(
          'lockAsync',
          ExpoFunction.typed1(ExpoValueTypes.number(), async (value: number): Promise<void> => {
            await this.setOrientation(toPreferredOrientation(value));
          }),
        )
        .asyncFunction(
          'lockPlatformAsync',
          ExpoFunction.typed1(ExpoValueTypes.number(), async (value: number): Promise<void> => {
            await this.setOrientation(requirePlatformOrientation(value));
          }),
        )
        .asyncFunction('getOrientationAsync', async (): Promise<number> => {
          return this.useWindow(async (win: window.Window): Promise<number> => readOrientation(win));
        })
        .asyncFunction('getOrientationLockAsync', async (): Promise<number> => {
          return this.useWindow(async (win: window.Window): Promise<number> => fromPreferredOrientation(win.getPreferredOrientation()));
        })
        .asyncFunction('getPlatformOrientationLockAsync', async (): Promise<number> => {
          return this.useWindow(async (win: window.Window): Promise<number> => win.getPreferredOrientation());
        })
        .asyncFunction(
          'supportsOrientationLockAsync',
          ExpoFunction.typed1(ExpoValueTypes.number(), async (value: number): Promise<boolean> => {
            this.assertActive();

            return supportsOrientationLock(value);
          }),
        )
        .onStartObserving(ORIENTATION_EVENT, (): void => {
          this.observing = true;
          this.observeWindow();
        })
        .onStopObserving(ORIENTATION_EVENT, (): void => {
          this.observing = false;
          this.unobserveWindow();
          this.lastOrientation = Orientation.UNKNOWN;
        })
        .onWindowStageSetup((stage: window.WindowStage): void => {
          if (this.destroyed || this.stage === stage) return;

          this.releaseWindow();
          this.stage = stage;
          this.observeWindow();
        })
        .onWindowStageWillDestroy((): void => {
          this.releaseWindow();
        })
        .onPrepareForReload(async (): Promise<void> => this.destroy())
        .onAbilityDestroy((): void => this.destroyInBackground())
        .onDestroy((): void => this.destroyInBackground())
    );
  }

  private setOrientation(orientation: window.Orientation): Promise<void> {
    return this.useWindow(async (win: window.Window): Promise<void> => {
      requireOrientationLockSupport();

      const id = win.getWindowProperties().id;
      const previous = win.getPreferredOrientation();
      let state = windowOrientations.get(id);

      await win.setPreferredOrientation(orientation);

      // A host policy change ends the ownership chain before this new lock.
      if (state === undefined || state.locks[state.locks.length - 1].value !== previous) {
        state = { target: win, original: previous, locks: [] };
        windowOrientations.set(id, state);
      }

      const locks = state.locks;
      const index = locks.findIndex((lock: AppliedOrientation): boolean => lock.owner === this);
      if (index >= 0) locks.splice(index, 1);
      locks.push({ owner: this, value: orientation });
    });
  }

  private observeWindow(): void {
    const stage = this.stage;
    if (!this.observing || stage === null || this.destroyed || this.context.isHeadless || this.stopObservingWindow) return;
    if (!canIUse('SystemCapability.WindowManager.WindowManager.Core')) return;

    try {
      const win = stage.getMainWindowSync();
      let active = true;

      const refresh = (notify: boolean): void => {
        if (!active || !this.context.isValid) return;

        try {
          const orientation = readOrientation(win);
          if (orientation === Orientation.UNKNOWN || orientation === this.lastOrientation) return;

          if (!notify) {
            this.lastOrientation = orientation;
            return;
          }

          const event: OrientationChangeEvent = {
            orientationLock: fromPreferredOrientation(win.getPreferredOrientation()),
            orientationInfo: { orientation },
          };

          this.lastOrientation = orientation;
          this.sendEvent(ORIENTATION_EVENT, event);
        } catch (error) {
          console.warn(`Unable to read the Expo ScreenOrientation window update: ${String(error)}`);
        }
      };

      const onChange = (): void => refresh(true);

      const subscriptions: (() => void)[] = [];
      const subscribe = (attach: () => void, detach: () => void): void => {
        try {
          attach();
          subscriptions.push(detach);
        } catch (error) {
          console.warn(`Unable to observe Expo ScreenOrientation changes: ${String(error)}`);
        }
      };

      subscribe((): void => display.on('change', onChange), (): void => display.off('change', onChange));
      subscribe((): void => win.on('windowSizeChange', onChange), (): void => win.off('windowSizeChange', onChange));
      if (canObserveWindowDisplayChange()) {
        subscribe((): void => win.on('displayIdChange', onChange), (): void => win.off('displayIdChange', onChange));
      }

      this.stopObservingWindow = (): void => {
        active = false;

        for (const detach of subscriptions) {
          try {
            detach();
          } catch (error) {
            console.warn(`Unable to stop observing Expo ScreenOrientation changes: ${String(error)}`);
          }
        }
      };

      refresh(this.lastOrientation !== Orientation.UNKNOWN);
    } catch (error) {
      console.warn(`Unable to start observing the Expo ScreenOrientation window: ${String(error)}`);
    }
  }

  private unobserveWindow(): void {
    this.stopObservingWindow?.();
    this.stopObservingWindow = undefined;
  }

  private useWindow<T>(task: (win: window.Window) => Promise<T>): Promise<T> {
    const generation = this.generation;

    return this.serialize(async (): Promise<T> => {
      this.assertWindowAvailable(generation);

      let win: window.Window;

      try {
        win = this.stage!.getMainWindowSync();
      } catch (error) {
        throw new ExpoModuleError('ERR_SCREEN_ORIENTATION_WINDOW', 'Screen orientation requires a current UIAbility window.', error);
      }

      const result = await task(win);

      this.assertWindowAvailable(generation);

      return result;
    });
  }

  private serialize<T>(task: () => Promise<T>): Promise<T> {
    const next = pendingWindowOperation.then(task);
    pendingWindowOperation = next.then(
      (): void => {},
      (): void => {},
    );

    return next;
  }

  private assertActive(): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoModuleError('ERR_SCREEN_ORIENTATION_DESTROYED', 'The Expo ScreenOrientation runtime has been destroyed.');
    }
  }

  private assertWindowAvailable(generation: number): void {
    this.assertActive();

    if (this.context.isHeadless || this.stage === null || generation !== this.generation) {
      throw new ExpoModuleError('ERR_SCREEN_ORIENTATION_WINDOW', 'Screen orientation requires a current UIAbility window.');
    }
  }

  private releaseWindow(): void {
    if (this.stage === null) return;

    this.unobserveWindow();
    this.stage = null;
    this.generation += 1;

    // A replaced stage may stay alive: restore after pending writes, before replacement writes.
    this.serialize(async (): Promise<void> => this.restoreOrientations()).catch((error: Object): void => {
      console.warn(`Unable to restore the Expo ScreenOrientation window policy: ${String(error)}`);
    });
  }

  private destroyInBackground(): void {
    this.destroy().catch((error: Object): void => {
      console.warn(`Unable to restore the Expo ScreenOrientation window policy: ${String(error)}`);
    });
  }

  private destroy(): Promise<void> {
    if (this.cleanup !== null) return this.cleanup;

    this.destroyed = true;
    this.unobserveWindow();
    this.cleanup = this.serialize(async (): Promise<void> => this.restoreOrientations());

    return this.cleanup;
  }

  private async restoreOrientations(): Promise<void> {
    let failure: Object | undefined;

    for (const entry of windowOrientations) {
      const id = entry[0];
      const state = entry[1];
      const locks = state.locks;
      const index = locks.findIndex((lock: AppliedOrientation): boolean => lock.owner === this);
      if (index < 0) continue;

      const current = index === locks.length - 1;
      const applied = locks[index].value;
      locks.splice(index, 1);
      if (locks.length === 0) windowOrientations.delete(id);
      if (!current) continue;

      try {
        if (state.target.getPreferredOrientation() !== applied) {
          windowOrientations.delete(id);
          continue;
        }

        const previous = locks.length === 0 ? state.original : locks[locks.length - 1].value;
        if (previous !== applied) {
          await state.target.setPreferredOrientation(previous);
        }
      } catch (error) {
        windowOrientations.delete(id);
        failure = error;
      }
    }

    if (failure !== undefined) {
      throw new ExpoModuleError('ERR_SCREEN_ORIENTATION_RESTORE', `Unable to restore the previous window orientation: ${String(failure)}`, failure);
    }
  }
}
