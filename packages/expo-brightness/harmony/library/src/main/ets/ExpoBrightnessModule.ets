/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { window } from '@kit.ArkUI';
import { settings } from '@kit.BasicServicesKit';
import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

const FOLLOW_SYSTEM: number = -1;
const SYSTEM_MAX: number = 255;
const CHANGE_EVENT: string = 'Expo.brightnessDidChange';

class BrightnessPermissionResponse {
  status: string = 'granted';
  granted: boolean = true;
  expires: string = 'never';
  canAskAgain: boolean = true;
}

export class ExpoBrightnessModule extends ExpoModule {
  private pending: Promise<void> = Promise.resolve();
  private windowWrite?: Promise<void>;
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoBrightness')
      // SDK 57's addBrightnessListener also registers on platforms that do not emit the event.
      .events([CHANGE_EVENT])
      .asyncFunction('getPermissionsAsync', async (): Promise<BrightnessPermissionResponse> => {
        this.assertActive();
        return new BrightnessPermissionResponse();
      })
      .asyncFunction('requestPermissionsAsync', async (): Promise<BrightnessPermissionResponse> => {
        this.assertActive();
        return new BrightnessPermissionResponse();
      })
      .asyncFunction('getBrightnessAsync', async (): Promise<number> => {
        return this.serialize(async (): Promise<number> => {
          const target: window.Window = await this.context.getReactNativeWindow();
          return this.readBrightness(target);
        });
      })
      .asyncFunction(
        'setBrightnessAsync',
        ExpoFunction.typed1(ExpoValueTypes.number(), async (value: number): Promise<void> => {
          requireBrightness(value);

          await this.serialize(async (): Promise<void> => {
            const target: window.Window = await this.context.getReactNativeWindow();
            this.assertActive();

            const write: Promise<void> = target.setWindowBrightness(value);
            this.windowWrite = write;

            try {
              await write;
            } finally {
              this.windowWrite = undefined;
            }
          });
        }),
      )
      .onPrepareForReload(async (): Promise<void> => {
        this.destroyed = true;
        // Finish any native write already issued to the window before a new runtime uses it.
        await this.windowWrite?.catch((): void => {});
      })
      .onDestroy((): void => {
        this.destroyed = true;
      });
  }

  private async readBrightness(target: window.Window): Promise<number> {
    this.assertActive();

    const initial: number = target.getWindowProperties().brightness;
    if (initial !== FOLLOW_SYSTEM) return requireBrightness(initial);

    const setting: string = await settings.getValue(this.context.uiAbilityContext, settings.display.SCREEN_BRIGHTNESS_STATUS);
    this.assertActive();

    // ArkUI or another caller can change the window while the settings query is pending.
    const latest: number = target.getWindowProperties().brightness;
    if (latest !== FOLLOW_SYSTEM) return requireBrightness(latest);

    if (typeof setting !== 'string' || setting.trim().length === 0) {
      throw new ExpoModuleError('ERR_BRIGHTNESS_SYSTEM', 'HarmonyOS did not return a system brightness value.');
    }

    const level: number = Number(setting);
    if (!/^\d+$/.test(setting.trim()) || level > SYSTEM_MAX) {
      throw new ExpoModuleError('ERR_BRIGHTNESS_SYSTEM', 'HarmonyOS returned an invalid system brightness value.');
    }

    return level / SYSTEM_MAX;
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

function requireBrightness(value: number): number {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new ExpoModuleError('ERR_BRIGHTNESS_VALUE', 'Expected a finite brightness value between 0 and 1.');
  }
  return value;
}
