import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueType } from '@expo-harmony/expo-modules-core';
import { deviceInfo } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import {
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
import type { HapticPreset, HapticPresetName, HapticPulse, HapticRecipe, HapticUsage } from './HapticsSemantics';

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

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
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

          await this.vibrate(recipe);
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

          await this.vibrate(recipe);
        }),
      )
      .asyncFunction('selectionAsync', async (): Promise<void> => {
        this.assertActive();
        await this.vibrate(selectionRecipe());
      })
      .onDestroy((): void => {
        this.destroyed = true;
      });
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoHapticsError(ERROR_DESTROYED, 'The Expo Haptics Harmony module has already been destroyed.');
    }
  }

  private async vibrate(recipe: HapticRecipe): Promise<void> {
    this.assertActive();

    const first: HapticPreset | undefined = recipe.presets[0];
    const notice: boolean = first !== undefined && isNoticePreset(first.name);
    if (notice && (await this.tryPreset(first))) return;

    if (recipe.pattern !== undefined && deviceInfo.sdkApiVersion >= PATTERN_API) {
      try {
        const builder = new vibrator.VibratorPatternBuilder();
        for (const pulse of recipe.pattern) {
          builder.addContinuousEvent(pulse.startMs, pulse.durationMs, { intensity: pulse.intensity });
        }
        const pattern = builder.build();

        if (this.destroyed) return;

        await vibrator.startVibration({ type: 'pattern', pattern }, { usage: recipe.usage });
        return;
      } catch (error) {
        if (!isUnavailable(error)) this.warnFallback('pattern', error);
      }
    }

    for (let index = notice ? 1 : 0; index < recipe.presets.length; index += 1) {
      if (this.destroyed) return;

      const preset: HapticPreset = recipe.presets[index];
      if (await this.tryPreset(preset, recipe.usage)) return;
    }

    if (this.destroyed) return;

    if (recipe.pattern !== undefined && recipe.pattern.length > 1) {
      try {
        await this.playPulses(recipe.pattern, recipe.usage);
        return;
      } catch (error) {
        if (!isUnavailable(error)) this.warnFallback('pulse timeline', error);
      }
    }

    try {
      await vibrator.startVibration({ type: 'time', duration: recipe.fallbackMs }, { usage: recipe.usage });
    } catch (error) {
      if (isUnavailable(error)) return;

      throw new ExpoHapticsError(ERROR_VIBRATION, `Unable to trigger HarmonyOS haptic feedback: ${errorMessage(error)}`);
    }
  }

  private async tryPreset(preset: HapticPreset, usage: HapticUsage = 'notification'): Promise<boolean> {
    if (deviceInfo.sdkApiVersion < preset.minApi) return false;

    const id: string = presetId(preset.name);
    if (!supports(id) || this.destroyed) return false;

    try {
      if (isNoticePreset(preset.name)) {
        await vibrator.startVibration({ type: 'preset', effectId: id, count: preset.count }, { usage });
      } else {
        await vibrator.startVibration({ type: 'preset', effectId: id, count: preset.count, intensity: preset.intensity }, { usage });
      }

      return true;
    } catch (error) {
      if (!isUnavailable(error)) this.warnFallback(`preset '${id}'`, error);

      return false;
    }
  }

  private async playPulses(pulses: readonly HapticPulse[], usage: HapticUsage): Promise<void> {
    let elapsed: number = 0;
    for (const pulse of pulses) {
      this.assertActive();

      const wait: number = Math.max(0, pulse.startMs - elapsed);
      if (wait > 0) await delay(wait);

      this.assertActive();
      await vibrator.startVibration({ type: 'time', duration: pulse.durationMs }, { usage });
      elapsed = pulse.startMs;
    }
  }

  private warnFallback(stage: string, error: Object): void {
    if (!this.destroyed) {
      this.context.logger.warn(`HarmonyOS haptics ${stage} failed; trying a fallback: ${errorMessage(error)}`);
    }
  }
}

function supports(id: string): boolean {
  try {
    return vibrator.isSupportEffectSync(id);
  } catch (error) {
    if (isUnavailable(error)) return false;

    throw new ExpoHapticsError(ERROR_VIBRATION, `Unable to query HarmonyOS haptic preset '${id}': ${errorMessage(error)}`);
  }
}

interface CodedError {
  readonly code?: number;
  readonly message?: string;
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

function presetId(name: HapticPresetName): string {
  switch (name) {
    case PRESET_SOFT:
      return vibrator.HapticFeedback.EFFECT_SOFT;
    case PRESET_HARD:
      return vibrator.HapticFeedback.EFFECT_HARD;
    case PRESET_SHARP:
      return vibrator.HapticFeedback.EFFECT_SHARP;
    case PRESET_NOTICE_SUCCESS:
      return vibrator.HapticFeedback.EFFECT_NOTICE_SUCCESS;
    case PRESET_NOTICE_WARNING:
      return vibrator.HapticFeedback.EFFECT_NOTICE_WARNING;
    case PRESET_NOTICE_FAILURE:
      return vibrator.HapticFeedback.EFFECT_NOTICE_FAILURE;
    default:
      throw new ExpoHapticsError(ERROR_VIBRATION, `Unknown HarmonyOS haptic preset '${name}'.`);
  }
}

function isNoticePreset(name: HapticPresetName): boolean {
  return name === PRESET_NOTICE_SUCCESS || name === PRESET_NOTICE_WARNING || name === PRESET_NOTICE_FAILURE;
}

function delay(duration: number): Promise<void> {
  return new Promise((resolve: () => void): void => {
    setTimeout(resolve, duration);
  });
}
