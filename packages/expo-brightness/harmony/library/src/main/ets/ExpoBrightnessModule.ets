import { window } from '@kit.ArkUI';
import { settings } from '@kit.BasicServicesKit';
import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

const FOLLOW_SYSTEM_BRIGHTNESS: number = -1;
const SYSTEM_BRIGHTNESS_MAX: number = 255;
const BRIGHTNESS_CHANGE_EVENT: string = 'Expo.brightnessDidChange';

class BrightnessPermissionResponse {
  status: string = 'granted';
  granted: boolean = true;
  expires: string = 'never';
  canAskAgain: boolean = true;
}

export class ExpoBrightnessModule extends ExpoModule {
  private pending: Promise<void> = Promise.resolve();
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return (
      new ExpoModuleDefinition()
        .name('ExpoBrightness')
        .events([BRIGHTNESS_CHANGE_EVENT])
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
            const win: window.Window = await this.context.getReactNativeWindow();
            this.assertActive();

            const value: number = win.getWindowProperties().brightness;
            if (value === FOLLOW_SYSTEM_BRIGHTNESS) {
              return this.readSystemBrightness();
            }

            return requireBrightness(value);
          });
        })
        .asyncFunction(
          'setBrightnessAsync',
          ExpoFunction.typed1(ExpoValueTypes.number(), async (value: number): Promise<void> => {
            requireBrightness(value);

            await this.serialize(async (): Promise<void> => {
              const win: window.Window = await this.context.getReactNativeWindow();
              this.assertActive();

              await win.setWindowBrightness(value);
            });
          }),
        )
        .onPrepareForReload(async (): Promise<void> => {
          this.destroyed = true;
        })
        .onDestroy((): void => {
          this.destroyed = true;
        })
    );
  }

  private async readSystemBrightness(): Promise<number> {
    const value: string = await settings.getValue(this.context.uiAbilityContext, settings.display.SCREEN_BRIGHTNESS_STATUS);
    this.assertActive();

    if (typeof value !== 'string' || value.trim().length === 0) {
      throw new ExpoModuleError('ERR_BRIGHTNESS_SYSTEM', 'HarmonyOS did not return a system brightness value.');
    }

    const level: number = Number(value);
    if (!Number.isFinite(level) || level < 0 || level > SYSTEM_BRIGHTNESS_MAX) {
      throw new ExpoModuleError('ERR_BRIGHTNESS_SYSTEM', 'HarmonyOS returned an invalid system brightness value.');
    }

    return level / SYSTEM_BRIGHTNESS_MAX;
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
