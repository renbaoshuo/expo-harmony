import { RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext, UITurboModuleContext } from '@rnoh/react-native-openharmony';
import { ExpoPlatformServiceError, ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
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
import type { HapticRecipe } from './HapticsSemantics';

const SERVICE_NAME: string = 'ExpoHapticsService';

const UNSUPPORTED_CODE: number = 801;
const DEVICE_FAILED_CODE: number = 14600101;
const NOTICE_SUCCESS_ID: string = 'haptic.notice.success';
const NOTICE_WARNING_ID: string = 'haptic.notice.warning';
const NOTICE_FAILURE_ID: string = 'haptic.notice.fail';
const ERROR_DESTROYED: string = 'ERR_HAPTICS_DESTROYED';
const ERROR_INVALID_ARGUMENT: string = 'ERR_HAPTICS_INVALID_ARGUMENT';
const ERROR_UNKNOWN_METHOD: string = 'ERR_HAPTICS_UNKNOWN_METHOD';
const ERROR_ASYNC_METHOD: string = 'ERR_HAPTICS_ASYNC_METHOD';
const ERROR_VIBRATION: string = 'ERR_HAPTICS_VIBRATION';
const UNKNOWN_VIBRATOR_ERROR: string = 'Unknown HarmonyOS vibrator error.';

const METHOD_NOTIFICATION: string = 'notificationAsync';
const METHOD_IMPACT: string = 'impactAsync';
const METHOD_SELECTION: string = 'selectionAsync';

let registered: boolean = false;

class ExpoHapticsError extends ExpoPlatformServiceError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoHapticsError';
  }
}

class ExpoHapticsService {
  readonly name: string = SERVICE_NAME;
  private destroyed: boolean = false;
  private queue: Promise<void> = Promise.resolve();

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (this.destroyed) {
      throw new ExpoHapticsError(ERROR_DESTROYED, 'The Expo Haptics Harmony service has already been destroyed.');
    }

    if (method === METHOD_NOTIFICATION) {
      const type = requireString(args[0], 'type');
      const recipe = notificationRecipe(type);
      if (recipe === undefined) {
        throw new ExpoHapticsError(ERROR_INVALID_ARGUMENT, `'type' must be one of ['success', 'warning', 'error']. Obtained '${type}'.`);
      }

      await this.serialize((): Promise<void> => this.vibrate(recipe));

      return null;
    }

    if (method === METHOD_IMPACT) {
      const style = requireString(args[0], 'style');
      const recipe = impactRecipe(style);
      if (recipe === undefined) {
        throw new ExpoHapticsError(
          ERROR_INVALID_ARGUMENT,
          `'style' must be one of ['light', 'medium', 'heavy', 'rigid', 'soft']. Obtained '${style}'.`,
        );
      }

      await this.serialize((): Promise<void> => this.vibrate(recipe));

      return null;
    }

    if (method === METHOD_SELECTION) {
      await this.serialize((): Promise<void> => this.vibrate(selectionRecipe()));

      return null;
    }

    throw new ExpoHapticsError(ERROR_UNKNOWN_METHOD, `Unknown Expo Haptics Harmony method '${method}'.`);
  }

  invokeSync(method: string, _: ESObject[]): ESObject {
    throw new ExpoHapticsError(ERROR_ASYNC_METHOD, `Expo Haptics Harmony method '${method}' is asynchronous.`);
  }

  onDestroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
  }

  private async serialize(task: () => Promise<void>): Promise<void> {
    const next = this.queue.catch((): void => {}).then(task);
    this.queue = next;

    await next;
  }

  private async vibrate(recipe: HapticRecipe): Promise<void> {
    if (this.destroyed) return;

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
        if (!isUnavailable(error)) {
          throw new ExpoHapticsError(ERROR_VIBRATION, `Unable to trigger HarmonyOS haptic pattern: ${errorMessage(error)}`);
        }
      }
    }

    for (const preset of recipe.presets) {
      if (this.destroyed) return;

      if (deviceInfo.sdkApiVersion < preset.minApi) continue;

      const id = presetId(preset.name);
      if (!supports(id)) continue;

      if (this.destroyed) return;

      try {
        await vibrator.startVibration(
          {
            type: 'preset',
            effectId: id,
            count: preset.count,
            intensity: preset.intensity,
          },
          { usage: recipe.usage },
        );
        return;
      } catch (error) {
        if (!isUnavailable(error)) {
          throw new ExpoHapticsError(ERROR_VIBRATION, `Unable to trigger HarmonyOS haptic feedback: ${errorMessage(error)}`);
        }
      }
    }

    if (this.destroyed) return;

    try {
      await vibrator.startVibration({ type: 'time', duration: recipe.fallbackMs }, { usage: recipe.usage });
    } catch (error) {
      // Expo haptics are best-effort on platforms without a haptics engine. HarmonyOS
      // reports both an unsupported capability and an unavailable motor through these
      // documented vibrator errors, so match the upstream no-op behavior in that case.
      if (!isUnavailable(error)) {
        throw new ExpoHapticsError(ERROR_VIBRATION, `Unable to trigger HarmonyOS haptic feedback: ${errorMessage(error)}`);
      }
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
    const code = (error as CodedError).code;

    return code === UNSUPPORTED_CODE || code === DEVICE_FAILED_CODE;
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

function presetId(name: string): string {
  switch (name) {
    case PRESET_SOFT:
      return vibrator.HapticFeedback.EFFECT_SOFT;
    case PRESET_HARD:
      return vibrator.HapticFeedback.EFFECT_HARD;
    case PRESET_SHARP:
      return vibrator.HapticFeedback.EFFECT_SHARP;
    case PRESET_NOTICE_SUCCESS:
      return NOTICE_SUCCESS_ID;
    case PRESET_NOTICE_WARNING:
      return NOTICE_WARNING_ID;
    case PRESET_NOTICE_FAILURE:
      return NOTICE_FAILURE_ID;
    default:
      throw new ExpoHapticsError(ERROR_VIBRATION, `Unknown HarmonyOS haptic preset '${name}'.`);
  }
}

function requireString(value: ESObject, name: string): string {
  if (typeof value !== 'string') {
    throw new ExpoHapticsError(ERROR_INVALID_ARGUMENT, `${name} must be a string.`);
  }

  return value;
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (_: UITurboModuleContext) => new ExpoHapticsService(),
  });
  registered = true;
}

export class ExpoHapticsPackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    super(context);
    registerService();
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-haptics';
  }
}
