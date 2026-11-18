/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { display, window } from '@kit.ArkUI';
import { deviceInfo, settings } from '@kit.BasicServicesKit';
import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

const FOLLOW_SYSTEM: number = -1;
const SYSTEM_MAX: number = 255;
const CHANGE_EVENT: string = 'Expo.brightnessDidChange';
const WINDOW_CAPABILITY = 'SystemCapability.WindowManager.WindowManager.Core';
const SETTINGS_CAPABILITY = 'SystemCapability.Applications.Settings.Core';
const DISPLAY_CAPABILITY = 'SystemCapability.Window.SessionManager';
const SHARED_BRIGHTNESS_API = 14;
const BRIGHTNESS_OBSERVATION_API = 22;

enum BrightnessMode {
  UNKNOWN = 0,
  AUTOMATIC = 1,
  MANUAL = 2,
}

class BrightnessEvent {
  readonly brightness: number;

  constructor(brightness: number) {
    this.brightness = brightness;
  }
}

class BrightnessPermissionResponse {
  status: string = 'granted';
  granted: boolean = true;
  expires: string = 'never';
  canAskAgain: boolean = true;
}

export class ExpoBrightnessModule extends ExpoModule {
  private pending: Promise<void> = Promise.resolve();
  private windowWrite?: Promise<void>;
  private observer?: (id: number, info: display.BrightnessInfo) => void;
  private sampleBrightness?: (emit: boolean) => void;
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoBrightness')
      .events([CHANGE_EVENT])
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => this.isWindowBrightnessAvailable())
      .asyncFunction('getPermissionsAsync', async (): Promise<BrightnessPermissionResponse> => {
        this.assertActive();
        return new BrightnessPermissionResponse();
      })
      .asyncFunction('requestPermissionsAsync', async (): Promise<BrightnessPermissionResponse> => {
        this.assertActive();
        return new BrightnessPermissionResponse();
      })
      .asyncFunction('getBrightnessAsync', async (): Promise<number> => this.getBrightness())
      .asyncFunction(
        'setBrightnessAsync',
        ExpoFunction.typed1(ExpoValueTypes.number(), async (value: number): Promise<void> => {
          await this.writeBrightness(requireBrightness(value));
        }),
      )
      .asyncFunction('getSystemBrightnessAsync', async (): Promise<number> => this.readSystemBrightness())
      .asyncFunction('getSystemBrightnessModeAsync', async (): Promise<number> => this.readSystemBrightnessMode())
      .asyncFunction('restoreSystemBrightnessAsync', async (): Promise<void> => {
        await this.writeBrightness(FOLLOW_SYSTEM);
      })
      .asyncFunction('isUsingSystemBrightnessAsync', async (): Promise<boolean> => {
        return this.serialize(async (): Promise<boolean> => {
          const win = this.getWindow();

          return usesSharedBrightness() || win.getWindowProperties().brightness === FOLLOW_SYSTEM;
        });
      })
      .onStartObserving(CHANGE_EVENT, (): void => this.startObserving())
      .onStopObserving(CHANGE_EVENT, (): void => this.stopObserving())
      .onPrepareForReload(async (): Promise<void> => {
        this.destroyed = true;
        this.stopObserving();

        // The next runtime can reuse the window as soon as reload preparation finishes.
        await this.windowWrite?.catch((): void => {});
      })
      .onDestroy((): void => {
        this.destroyed = true;
        this.stopObserving();
      });
  }

  private isWindowBrightnessAvailable(): boolean {
    return !this.destroyed && !this.context.isHeadless && canIUse(WINDOW_CAPABILITY);
  }

  private getWindow(): window.Window {
    this.assertActive();
    if (!this.isWindowBrightnessAvailable()) {
      throw new ExpoModuleError('ERR_BRIGHTNESS_UNAVAILABLE', 'Window brightness is unavailable in this runtime.');
    }

    // The brightness API is owned by the main window even when React renders in a subwindow.
    try {
      return this.context.uiAbilityContext.windowStage.getMainWindowSync();
    } catch (error) {
      throw new ExpoModuleError('ERR_BRIGHTNESS_UNAVAILABLE', 'The main window is unavailable.', error as Error);
    }
  }

  private getBrightness(): Promise<number> {
    return this.serialize(async (): Promise<number> => this.readBrightness(this.getWindow()));
  }

  private writeBrightness(value: number): Promise<void> {
    return this.serialize(async (): Promise<void> => {
      const win = this.getWindow();

      // PC and 2-in-1 devices with shared brightness have no window override to restore.
      if (value === FOLLOW_SYSTEM && usesSharedBrightness()) return;

      const write = win.setWindowBrightness(value);
      this.windowWrite = write;

      try {
        await write;

        this.sampleBrightness?.(true);
      } finally {
        this.windowWrite = undefined;
      }
    });
  }

  private async readBrightness(win: window.Window): Promise<number> {
    this.assertActive();

    const shared = usesSharedBrightness();
    const initial = shared ? FOLLOW_SYSTEM : win.getWindowProperties().brightness;
    if (initial !== FOLLOW_SYSTEM) return requireBrightness(initial);

    const current = readDisplayBrightness();
    if (current !== undefined) return current;

    const system = await this.readSystemBrightness();

    // Another owner can change the window while the settings query is pending.
    const latest = shared ? FOLLOW_SYSTEM : win.getWindowProperties().brightness;
    return latest === FOLLOW_SYSTEM ? system : requireBrightness(latest);
  }

  private async readSystemBrightness(): Promise<number> {
    this.assertActive();
    if (!canIUse(SETTINGS_CAPABILITY)) {
      throw new ExpoModuleError('ERR_BRIGHTNESS_SYSTEM', 'System brightness settings are unavailable.');
    }

    let setting: string;
    try {
      setting = await settings.getValue(this.context.uiAbilityContext, settings.display.SCREEN_BRIGHTNESS_STATUS, settings.domainName.DEVICE_SHARED);
    } catch (error) {
      this.assertActive();
      throw new ExpoModuleError('ERR_BRIGHTNESS_SYSTEM', 'Unable to read the HarmonyOS system brightness.', error as Error);
    }

    this.assertActive();

    const value = typeof setting === 'string' ? setting.trim() : '';
    const level = Number(value);
    if (!/^\d+$/.test(value) || level > SYSTEM_MAX) {
      throw new ExpoModuleError('ERR_BRIGHTNESS_SYSTEM', 'HarmonyOS returned an invalid system brightness value.');
    }

    return level / SYSTEM_MAX;
  }

  private async readSystemBrightnessMode(): Promise<BrightnessMode> {
    this.assertActive();
    if (!canIUse(SETTINGS_CAPABILITY)) return BrightnessMode.UNKNOWN;

    let setting: string;
    try {
      setting = await settings.getValue(this.context.uiAbilityContext, settings.display.AUTO_SCREEN_BRIGHTNESS, settings.domainName.DEVICE_SHARED);
    } catch (_) {
      this.assertActive();
      return BrightnessMode.UNKNOWN;
    }

    this.assertActive();

    const value = typeof setting === 'string' ? setting.trim() : '';
    if (value === String(settings.display.AUTO_SCREEN_BRIGHTNESS_MODE)) return BrightnessMode.AUTOMATIC;
    if (value === String(settings.display.MANUAL_SCREEN_BRIGHTNESS_MODE)) return BrightnessMode.MANUAL;

    return BrightnessMode.UNKNOWN;
  }

  private startObserving(): void {
    if (!this.isWindowBrightnessAvailable() || this.sampleBrightness !== undefined) return;

    let previous: number | undefined;
    let sampling = false;
    let notify = false;

    const sample = (emit: boolean): void => {
      notify = notify || emit;
      if (sampling) return;

      sampling = true;
      const emitting = notify;
      notify = false;

      this.getBrightness().then((brightness: number): void => {
        if (this.sampleBrightness !== sample || brightness === previous) return;

        previous = brightness;
        if (emitting || notify) this.sendEvent(CHANGE_EVENT, new BrightnessEvent(brightness));
      }).catch((): void => {}).finally((): void => {
        sampling = false;
        if (notify && this.sampleBrightness === sample) sample(true);
      });
    };

    this.sampleBrightness = sample;
    sample(false);

    if (deviceInfo.sdkApiVersion < BRIGHTNESS_OBSERVATION_API || !canIUse(DISPLAY_CAPABILITY)) return;

    const observer = (id: number, _info: display.BrightnessInfo): void => {
      if (this.observer !== observer) return;

      try {
        if (id === display.getDefaultDisplaySync().id) sample(true);
      } catch (_) {}
    };

    try {
      display.on('brightnessInfoChange', observer);
      this.observer = observer;
    } catch (_) {
      // A device can expose DisplayManager without supporting brightness observations.
    }
  }

  private stopObserving(): void {
    this.sampleBrightness = undefined;

    const observer = this.observer;
    this.observer = undefined;
    if (observer === undefined || deviceInfo.sdkApiVersion < BRIGHTNESS_OBSERVATION_API) return;

    try {
      display.off('brightnessInfoChange', observer);
    } catch (_) {}
  }

  private serialize<T>(task: () => Promise<T>): Promise<T> {
    const next: Promise<T> = this.pending.then(async (): Promise<T> => {
      this.assertActive();
      return task();
    });

    this.pending = next.then(
      (): void => {},
      (): void => {},
    );

    return next;
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoModuleError('ERR_BRIGHTNESS_DESTROYED', 'The Expo Brightness runtime has already been destroyed.');
    }
  }
}

function readDisplayBrightness(): number | undefined {
  if (!canIUse(DISPLAY_CAPABILITY) || typeof deviceInfo.apiAvailable !== 'function') return undefined;
  if (!deviceInfo.apiAvailable('26.0.0')) return undefined;

  try {
    const value = display.getBrightnessInfo(display.getDefaultDisplaySync().id).brightnessPosition;
    if (value !== undefined && Number.isFinite(value) && value >= 0 && value <= 1) return value;
  } catch (_) {}

  return undefined;
}

function usesSharedBrightness(): boolean {
  return deviceInfo.sdkApiVersion >= SHARED_BRIGHTNESS_API && deviceInfo.deviceType === '2in1';
}

function requireBrightness(value: number): number {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new ExpoModuleError('ERR_BRIGHTNESS_VALUE', 'Expected a finite brightness value between 0 and 1.');
  }
  return value;
}
