/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueType } from '@expo-harmony/expo-modules-core';
import { deviceInfo } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import {
  NOTICE_PRESET_API,
  PATTERN_API,
  PRESET_HARD,
  PRESET_NOTICE_FAILURE,
  PRESET_NOTICE_SUCCESS,
  PRESET_NOTICE_WARNING,
  PRESET_SHARP,
  PRESET_SOFT,
  impactRecipe,
  notificationRecipe,
  selectionRecipe,
} from './HapticsSemantics';
import type { HapticPreset, HapticPresetName, HapticRecipe, HapticUsage } from './HapticsSemantics';

const VIBRATOR_CAPABILITY: string = 'SystemCapability.Sensors.MiscDevice';
const UNSUPPORTED_CODE: number = 801;
const ERROR_DESTROYED: string = 'ERR_HAPTICS_DESTROYED';
const ERROR_INVALID_ARGUMENT: string = 'ERR_HAPTICS_INVALID_ARGUMENT';
const ERROR_VIBRATION: string = 'ERR_HAPTICS_VIBRATION';
const UNKNOWN_VIBRATOR_ERROR: string = 'Unknown HarmonyOS vibrator error.';
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
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoHapticsError';
  }
}

export class ExpoHapticsModule extends ExpoModule {
  private destroyed: boolean = false;
  private pending: Promise<void> = Promise.resolve();

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
    // A fallback for an older request must start before the newer request.
    const request = this.pending.then(async (): Promise<void> => {
      if (this.destroyed || !canIUse(VIBRATOR_CAPABILITY)) return;

      await this.vibrate(recipe);
    });

    this.pending = request.catch((): void => {});

    return request;
  }

  private async vibrate(recipe: HapticRecipe): Promise<void> {
    const first: HapticPreset | undefined = recipe.presets[0];
    const notice: boolean = first !== undefined && isNoticePreset(first.name);

    if (notice && (await this.tryPreset(first, recipe.usage))) return;

    if (this.destroyed) return;

    if (recipe.pattern !== undefined && deviceInfo.sdkApiVersion >= PATTERN_API) {
      try {
        if (vibrator.isHdHapticSupported()) {
          const builder = new vibrator.VibratorPatternBuilder();

          for (const pulse of recipe.pattern) {
            builder.addContinuousEvent(pulse.startMs, pulse.durationMs, { intensity: pulse.intensity });
          }

          await vibrator.startVibration({ type: 'pattern', pattern: builder.build() }, { usage: recipe.usage });
          return;
        }
      } catch (error) {
        rejectUnlessUnsupported(error);
      }
    }

    for (let index = notice ? 1 : 0; index < recipe.presets.length; index += 1) {
      if (this.destroyed) return;

      const preset: HapticPreset = recipe.presets[index];

      if (await this.tryPreset(preset, recipe.usage)) return;
    }

    if (this.destroyed) return;

    try {
      await vibrator.startVibration({ type: 'time', duration: recipe.fallbackMs }, { usage: recipe.usage });
    } catch (error) {
      rejectUnlessUnsupported(error);
    }
  }

  private async tryPreset(preset: HapticPreset, usage: HapticUsage): Promise<boolean> {
    if (deviceInfo.sdkApiVersion < preset.minApi) return false;

    const id: string | undefined = presetId(preset.name);

    if (id === undefined) return false;

    try {
      // The asynchronous query can report service failures as unsupported effects.
      if (!vibrator.isSupportEffectSync(id)) return false;

      if (isNoticePreset(preset.name)) {
        await vibrator.startVibration({ type: 'preset', effectId: id, count: preset.count }, { usage });
      } else {
        await vibrator.startVibration({ type: 'preset', effectId: id, count: preset.count, intensity: preset.intensity }, { usage });
      }

      return true;
    } catch (error) {
      rejectUnlessUnsupported(error);
      return false;
    }
  }
}

interface CodedError {
  readonly code?: number;
  readonly message?: string;
}

function rejectUnlessUnsupported(error: Object): void {
  if (!isUnavailable(error)) {
    throw new ExpoHapticsError(ERROR_VIBRATION, `Unable to trigger HarmonyOS haptic feedback: ${errorMessage(error)}`);
  }
}

function isUnavailable(error: Object): boolean {
  if (error === null || typeof error !== 'object') return false;

  try {
    return (error as CodedError).code === UNSUPPORTED_CODE;
  } catch (_) {
    return false;
  }
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

function presetId(name: HapticPresetName): string | undefined {
  switch (name) {
    case PRESET_SOFT:
      return vibrator.HapticFeedback.EFFECT_SOFT;
    case PRESET_HARD:
      return vibrator.HapticFeedback.EFFECT_HARD;
    case PRESET_SHARP:
      return vibrator.HapticFeedback.EFFECT_SHARP;
  }

  if (deviceInfo.sdkApiVersion >= NOTICE_PRESET_API) {
    switch (name) {
      case PRESET_NOTICE_SUCCESS:
        return vibrator.HapticFeedback.EFFECT_NOTICE_SUCCESS;
      case PRESET_NOTICE_WARNING:
        return vibrator.HapticFeedback.EFFECT_NOTICE_WARNING;
      case PRESET_NOTICE_FAILURE:
        return vibrator.HapticFeedback.EFFECT_NOTICE_FAILURE;
    }
  }

  return undefined;
}

function isNoticePreset(name: HapticPresetName): boolean {
  return name === PRESET_NOTICE_SUCCESS || name === PRESET_NOTICE_WARNING || name === PRESET_NOTICE_FAILURE;
}
