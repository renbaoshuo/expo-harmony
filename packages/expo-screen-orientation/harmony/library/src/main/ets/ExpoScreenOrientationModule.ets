/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { window } from '@kit.ArkUI';
import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import {
  fromPreferredOrientation,
  readOrientation,
  requirePlatformOrientation,
  supportsOrientationLock,
  toPreferredOrientation,
} from './ScreenOrientation';

export class ExpoScreenOrientationModule extends ExpoModule {
  private pending: Promise<void> = Promise.resolve();
  private cleanup: Promise<void> | null = null;
  private destroyed: boolean = false;
  private stage: window.WindowStage | null = null;
  private generation: number = 0;
  private readonly originals: Map<window.Window, window.Orientation> = new Map();

  definition(): ExpoModuleDefinition {
    return (
      new ExpoModuleDefinition()
        .name('ExpoScreenOrientation')
        .events(['expoDidUpdateDimensions'])
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
        .onWindowStageSetup((stage: window.WindowStage): void => {
          if (this.destroyed || this.stage === stage) return;

          this.releaseWindow();
          this.stage = stage;
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
      const original = this.originals.has(win) ? undefined : win.getPreferredOrientation();

      // Always apply the request: the OS may have changed orientation since the
      // previous lock, including when returning to a previously applied policy.
      await win.setPreferredOrientation(orientation);
      if (original !== undefined) this.originals.set(win, original);
    });
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
    const next = this.pending.then(task);
    this.pending = next.then(
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
    this.cleanup = this.serialize(async (): Promise<void> => this.restoreOrientations());

    return this.cleanup;
  }

  private async restoreOrientations(): Promise<void> {
    let failure: Object | undefined;

    for (const entry of this.originals) {
      try {
        await entry[0].setPreferredOrientation(entry[1]);
      } catch (error) {
        failure = error;
      }
    }

    this.originals.clear();

    if (failure !== undefined) {
      throw new ExpoModuleError('ERR_SCREEN_ORIENTATION_RESTORE', `Unable to restore the initial window orientation: ${String(failure)}`);
    }
  }
}
