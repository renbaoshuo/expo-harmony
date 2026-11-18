/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueType } from '@expo-harmony/expo-modules-core';
import { deviceInfo } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import { impactRecipe, notificationRecipe, selectionRecipe } from './HapticsSemantics';
import type { HapticNotification, HapticPresetName, HapticRecipe, HapticUsage } from './HapticsSemantics';

const VIBRATOR_CAPABILITY: string = 'SystemCapability.Sensors.MiscDevice';
const HD_HAPTICS_API: number = 18;
const VIBRATOR_INFO_API: number = 19;
const UNSUPPORTED_CODE: number = 801;
const DEVICE_OPERATION_FAILED: number = 14600101;
const ERROR_DESTROYED: string = 'ERR_HAPTICS_DESTROYED';
const ERROR_INVALID_ARGUMENT: string = 'ERR_HAPTICS_INVALID_ARGUMENT';
const ERROR_VIBRATION: string = 'ERR_HAPTICS_VIBRATION';
const UNKNOWN_VIBRATOR_ERROR: string = 'Unknown HarmonyOS vibrator error.';

// Requests from different React instances address the same local vibrator.
let queue: Promise<void> = Promise.resolve();

const ARGUMENT = new ExpoValueType<string>(
  'haptics argument',
  (value: ESObject, path: string): string => {
    if (typeof value !== 'string') {
      throw new ExpoHapticsError(ERROR_INVALID_ARGUMENT, `${path} expected a haptics string.`);
    }

    return value;
  },
  (value: string): ESObject => value,
);

class ExpoHapticsError extends ExpoModuleError {
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
    this.name = 'ExpoHapticsError';
  }
}

export class ExpoHapticsModule extends ExpoModule {
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    const destroy = (): void => {
      this.destroyed = true;
    };

    return new ExpoModuleDefinition()
      .name('ExpoHaptics')
      .asyncFunction(
        'notificationAsync',
        ExpoFunction.typed1(ARGUMENT, async (type: string): Promise<void> => {
          this.assertActive();

          const recipe = notificationRecipe(type);
          if (recipe === undefined) {
            throw new ExpoHapticsError(ERROR_INVALID_ARGUMENT, `'type' must be one of ['success', 'warning', 'error']. Obtained '${type}'.`);
          }

          await this.enqueue(recipe);
        }),
      )
      .asyncFunction(
        'impactAsync',
        ExpoFunction.typed1(ARGUMENT, async (style: string): Promise<void> => {
          this.assertActive();

          const recipe = impactRecipe(style);
          if (recipe === undefined) {
            throw new ExpoHapticsError(
              ERROR_INVALID_ARGUMENT,
              `'style' must be one of ['light', 'medium', 'heavy', 'rigid', 'soft']. Obtained '${style}'.`,
            );
          }

          await this.enqueue(recipe);
        }),
      )
      .asyncFunction('selectionAsync', async (): Promise<void> => {
        this.assertActive();
        await this.enqueue(selectionRecipe());
      })
      .onPrepareForReload(async (): Promise<void> => destroy())
      .onAbilityDestroy(destroy)
      .onDestroy(destroy);
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoHapticsError(ERROR_DESTROYED, 'The Expo Haptics Harmony module has already been destroyed.');
    }
  }

  private enqueue(recipe: HapticRecipe): Promise<void> {
    const request = queue.then(async (): Promise<void> => {
      if (this.destroyed || !canIUse(VIBRATOR_CAPABILITY)) return;

      try {
        await this.vibrate(recipe);
      } catch (error) {
        const cause = error instanceof ExpoHapticsError ? error.cause ?? error : error as Object;
        if (this.destroyed || isUnavailable(cause)) return;

        throw new ExpoHapticsError(ERROR_VIBRATION, `Unable to trigger HarmonyOS haptic feedback: ${errorMessage(cause)}`, cause);
      }
    });

    queue = request.catch((): void => {});

    return request;
  }

  private async vibrate(recipe: HapticRecipe): Promise<void> {
    const id = recipe.notification === undefined ? undefined : notificationPresetId(recipe.notification);
    if (id !== undefined && await this.tryVibration({ type: 'preset', effectId: id }, recipe.usage)) return;

    if (this.destroyed) return;

    if (recipe.pattern !== undefined && deviceInfo.sdkApiVersion >= HD_HAPTICS_API) {
      let pattern: vibrator.VibratorPattern | undefined;

      try {
        if (vibrator.isHdHapticSupported()) {
          const builder = new vibrator.VibratorPatternBuilder();
          for (const pulse of recipe.pattern) {
            builder.addContinuousEvent(pulse.startMs, pulse.durationMs, { intensity: pulse.intensity });
          }

          pattern = builder.build();
        }
      } catch (error) {
        if (errorCode(error) !== UNSUPPORTED_CODE) {
          throw new ExpoHapticsError(ERROR_VIBRATION, errorMessage(error), error);
        }
      }

      if (pattern !== undefined && await this.tryVibration({ type: 'pattern', pattern }, recipe.usage)) return;
    }

    if (this.destroyed) return;

    const preset = recipe.preset;
    if (await this.tryVibration({
      type: 'preset',
      effectId: presetId(preset.name),
      count: preset.count,
      intensity: preset.intensity,
    }, recipe.usage)) return;

    if (this.destroyed) return;
    await this.tryVibration({ type: 'time', duration: recipe.fallbackMs }, recipe.usage);
  }

  private async tryVibration(effect: vibrator.VibrateEffect, usage: HapticUsage): Promise<boolean> {
    try {
      if (effect.type === 'preset' && !vibrator.isSupportEffectSync(effect.effectId)) return false;

      await vibrator.startVibration(effect, { usage });

      return true;
    } catch (error) {
      if (errorCode(error) === UNSUPPORTED_CODE) return false;

      throw new ExpoHapticsError(ERROR_VIBRATION, errorMessage(error), error);
    }
  }
}

interface CodedError {
  readonly code?: number;
  readonly message?: string;
}

function errorCode(error: Object): number | undefined {
  try {
    return (error as CodedError)?.code;
  } catch (_) {
    return undefined;
  }
}

function isUnavailable(error: Object): boolean {
  const code = errorCode(error);
  if (code === UNSUPPORTED_CODE) return true;

  if (code === DEVICE_OPERATION_FAILED && deviceInfo.sdkApiVersion >= VIBRATOR_INFO_API) {
    try {
      return !vibrator.getVibratorInfoSync().some((info: vibrator.VibratorInfo): boolean => info.isLocalVibrator);
    } catch (_) {
      return false;
    }
  }

  return false;
}

function errorMessage(error: Object): string {
  try {
    const value = error as CodedError;
    const code = value.code;
    const message = value.message;

    if (code !== undefined && typeof message === 'string' && message.length > 0) {
      return `HarmonyOS ${code}: ${message}`;
    }
    if (code !== undefined) return `HarmonyOS ${code}`;
    if (typeof message === 'string' && message.length > 0) return message;

    const text = String(error);

    return text.length > 0 ? text : UNKNOWN_VIBRATOR_ERROR;
  } catch (_) {
    return UNKNOWN_VIBRATOR_ERROR;
  }
}

function presetId(name: HapticPresetName): string {
  switch (name) {
    case 'soft':
      return vibrator.HapticFeedback.EFFECT_SOFT;
    case 'hard':
      return vibrator.HapticFeedback.EFFECT_HARD;
    case 'sharp':
      return vibrator.HapticFeedback.EFFECT_SHARP;
  }
}

function notificationPresetId(notification: HapticNotification): string | undefined {
  if (deviceInfo.sdkApiVersion >= HD_HAPTICS_API) {
    switch (notification) {
      case 'success':
        return vibrator.HapticFeedback.EFFECT_NOTICE_SUCCESS;
      case 'warning':
        return vibrator.HapticFeedback.EFFECT_NOTICE_WARNING;
      case 'error':
        return vibrator.HapticFeedback.EFFECT_NOTICE_FAILURE;
    }
  }

  return undefined;
}
