/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ExpoAppLifecycleState, ExpoModule, ExpoModuleDefinition, ExpoModuleError } from '@expo-harmony/expo-modules-core';

const SCREENSHOT_EVENT: string = 'onScreenshot';

interface WindowBinding {
  target: window.Window;
  generation: number;
}

interface ScreenshotObserver {
  id: number;
  callback: () => void;
  detach: () => void;
}

// Several React Native runtimes can share one native window and its single privacy flag.
const privacyLeases: Map<number, WindowPrivacyLease> = new Map<number, WindowPrivacyLease>();

class WindowPrivacyLease {
  private readonly id: number;
  private readonly owners: Set<Object> = new Set<Object>();
  private pending: Promise<void> = Promise.resolve();
  private pendingRetains: number = 0;
  private enabledByExpo: boolean = false;

  constructor(id: number) {
    this.id = id;
  }

  retain(owner: Object, target: window.Window, isWindowCurrent: () => boolean): Promise<void> {
    this.pendingRetains += 1;
    return this.serialize(async (): Promise<void> => {
      try {
        if (!isWindowCurrent()) return;

        if (!target.getWindowProperties().isPrivacyMode) {
          await target.setWindowPrivacyMode(true);
          this.enabledByExpo = true;
        }

        if (isWindowCurrent()) this.owners.add(owner);
      } finally {
        this.pendingRetains -= 1;
        this.deleteIfIdle();
      }
    });
  }

  release(owner: Object, target: window.Window): Promise<void> {
    return this.serialize(async (): Promise<void> => {
      if (!this.owners.has(owner)) return;

      if (this.owners.size === 1 && this.enabledByExpo) {
        await target.setWindowPrivacyMode(false);
        this.enabledByExpo = false;
      }

      this.forget(owner);
    });
  }

  forget(owner: Object): void {
    this.owners.delete(owner);
    this.deleteIfIdle();
  }

  private deleteIfIdle(): void {
    if (this.owners.size === 0 && this.pendingRetains === 0 && privacyLeases.get(this.id) === this) {
      privacyLeases.delete(this.id);
    }
  }

  private serialize(task: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.pending.then(task);
    this.pending = next.catch((): void => {});
    return next;
  }
}

interface WindowProtection {
  target: window.Window;
  lease: WindowPrivacyLease;
}

export class ExpoScreenCaptureModule extends ExpoModule {
  private pending: Promise<void> = Promise.resolve();
  private readonly windows: Map<number, WindowProtection> = new Map<number, WindowProtection>();
  private readonly retiredObservers: Set<ScreenshotObserver> = new Set<ScreenshotObserver>();
  private observer: ScreenshotObserver | null = null;
  private protecting: boolean = false;
  private listening: boolean = false;
  private destroyed: boolean = false;
  private available: boolean = true;
  private generation: number = 0;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoScreenCapture')
      .events([SCREENSHOT_EVENT])
      .asyncFunction('preventScreenCapture', (): Promise<void> => this.serialize(async (): Promise<void> => {
        await this.protectWindow(await this.currentWindow());
      }))
      .asyncFunction('allowScreenCapture', (): Promise<void> => this.serialize(async (): Promise<void> => {
        this.assertActive();

        this.protecting = false;
        await this.releaseWindows();
      }))
      .onStartObserving(SCREENSHOT_EVENT, (): void => {
        this.listening = true;
        this.refresh();
      })
      .onStopObserving(SCREENSHOT_EVENT, (): void => {
        this.listening = false;
        this.stopObserving();
      })
      .onForeground((): void => this.refresh())
      .onBackground((): void => this.stopObserving())
      .onContentAppeared((): void => this.refresh())
      .onWindowStageSetup((): void => {
        this.available = true;
        this.refresh();
      })
      .onWindowStageWillDestroy((): void => {
        this.available = false;
        this.generation += 1;

        this.stopObserving();

        this.retiredObservers.clear();
        this.windows.forEach((protection: WindowProtection): void => protection.lease.forget(this));
        this.windows.clear();
      })
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onDestroy((): void => {
        this.destroy().catch((error: Object): void => this.warn('release screen-capture protection', error));
      });
  }

  private async currentWindow(): Promise<WindowBinding> {
    this.assertActive();
    if (this.context.isHeadless || !this.available) {
      throw new ExpoModuleError('ERR_SCREEN_CAPTURE_WINDOW', 'Screen capture requires a UIAbility window.');
    }

    const generation: number = this.generation;

    try {
      const target: window.Window = await this.context.getReactNativeWindow();

      return { target, generation };
    } catch (error) {
      this.assertActive();
      throw new ExpoModuleError('ERR_SCREEN_CAPTURE_WINDOW', `Unable to find the React Native window: ${String(error)}`);
    }
  }

  private assertCurrentWindow(binding: WindowBinding): void {
    this.assertActive();
    if (!this.available || binding.generation !== this.generation) {
      throw new ExpoModuleError('ERR_SCREEN_CAPTURE_WINDOW', 'The React Native window is no longer available.');
    }
  }

  private async protectWindow(binding: WindowBinding): Promise<void> {
    this.assertCurrentWindow(binding);

    const target: window.Window = binding.target;
    const id: number = target.getWindowProperties().id;
    let lease: WindowPrivacyLease | undefined = privacyLeases.get(id);

    if (lease === undefined) {
      lease = new WindowPrivacyLease(id);
      privacyLeases.set(id, lease);
    }

    // Record ownership before the asynchronous write so stage destruction can retire it.
    this.windows.set(id, { target, lease });
    await lease.retain(this, target, (): boolean => this.available && binding.generation === this.generation);
    this.assertCurrentWindow(binding);

    this.protecting = true;

    try {
      await this.releaseWindows(id);
    } catch (error) {
      // The current window is already protected. Rejecting would drop the JS owner's key.
      this.warn('release previous window privacy mode', error);
    }
  }

  private async releaseWindows(except?: number): Promise<void> {
    let failure: string | undefined;

    for (const entry of this.windows.entries()) {
      const id: number = entry[0];
      if (id === except) continue;

      try {
        await entry[1].lease.release(this, entry[1].target);
        this.windows.delete(id);
      } catch (error) {
        failure = String(error);
      }
    }

    if (failure !== undefined) {
      throw new ExpoModuleError('ERR_SCREEN_CAPTURE_RELEASE', `Unable to release window privacy mode: ${failure}`);
    }
  }

  private refresh(): void {
    if (this.destroyed || !this.available || this.context.isHeadless) return;

    this.serialize(async (): Promise<void> => {
      if (this.destroyed || !this.available) return;

      try {
        if (!this.protecting && !this.shouldObserve()) return;

        const binding: WindowBinding = await this.currentWindow();
        this.assertCurrentWindow(binding);

        this.refreshObserver(binding.target);
        if (this.protecting) await this.protectWindow(binding);
      } finally {
        if (!this.protecting && !this.destroyed) await this.releaseWindows();
      }
    }).catch((error: Object): void => this.warn('refresh screen-capture state', error));
  }

  private refreshObserver(target: window.Window): void {
    if (!this.shouldObserve()) return;

    try {
      const id: number = target.getWindowProperties().id;
      if (this.observer?.id === id) return;

      this.stopObserving();
      const callback = (): void => {
        if (this.observer?.callback === callback && this.shouldObserve()) this.sendEvent(SCREENSHOT_EVENT);
      };
      this.observer = { id, callback, detach: this.subscribeToScreenshots(target, callback) };
    } catch (error) {
      this.warn('attach the screenshot listener', error);
    }
  }

  private subscribeToScreenshots(target: window.Window, callback: () => void): () => void {
    if (deviceInfo.sdkApiVersion >= 20) {
      try {
        const listener = (event: window.ScreenshotEventType): void => {
          if (event === window.ScreenshotEventType.SYSTEM_SCREENSHOT || event === window.ScreenshotEventType.SCROLL_SHOT_END) callback();
        };
        // The legacy event overlaps with the Control Panel event. Use one listener per window.
        target.on('screenshotAppEvent', listener);
        return (): void => {
          if (deviceInfo.sdkApiVersion >= 20) target.off('screenshotAppEvent', listener);
        };
      } catch (error) {
        this.warn('attach the screenshot action listener', error);
      }
    }

    target.on('screenshot', callback);
    return (): void => target.off('screenshot', callback);
  }

  private shouldObserve(): boolean {
    return (
      !this.destroyed &&
      this.available &&
      this.listening &&
      this.context.isValid &&
      !this.context.isHeadless &&
      this.context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND
    );
  }

  private detachObservers(): void {
    if (this.observer !== null) {
      this.retiredObservers.add(this.observer);
      this.observer = null;
    }

    let failure: string | undefined;

    for (const observer of this.retiredObservers) {
      try {
        observer.detach();
        this.retiredObservers.delete(observer);
      } catch (error) {
        failure = String(error);
      }
    }

    if (failure !== undefined) {
      throw new ExpoModuleError('ERR_SCREEN_CAPTURE_OBSERVER', `Unable to detach the screenshot listener: ${failure}`);
    }
  }

  private stopObserving(): void {
    try {
      this.detachObservers();
    } catch (error) {
      console.warn(String(error));
    }
  }

  private destroy(): Promise<void> {
    this.destroyed = true;
    this.listening = false;
    this.protecting = false;

    // Serialize after pending setters: a late completion cannot re-enable a released window.
    return this.serialize(async (): Promise<void> => {
      try {
        this.detachObservers();
      } finally {
        await this.releaseWindows();
      }
    });
  }

  private serialize(task: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.pending.then(task);

    this.pending = next.then(
      (): void => {},
      (): void => {},
    );

    return next;
  }

  private assertActive(): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoModuleError('ERR_SCREEN_CAPTURE_DESTROYED', 'The Expo ScreenCapture runtime has been destroyed.');
    }
  }

  private warn(action: string, error: Object): void {
    console.warn(`Unable to ${action}: ${String(error)}`);
  }
}
