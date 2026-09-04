const NOTIFICATION_SUCCESS: string = 'success';
const NOTIFICATION_WARNING: string = 'warning';
const NOTIFICATION_ERROR: string = 'error';

const IMPACT_LIGHT: string = 'light';
const IMPACT_MEDIUM: string = 'medium';
const IMPACT_HEAVY: string = 'heavy';
const IMPACT_SOFT: string = 'soft';
const IMPACT_RIGID: string = 'rigid';

export type HapticPresetName =
  | 'noticeSuccess'
  | 'noticeWarning'
  | 'noticeFailure'
  | 'soft'
  | 'hard'
  | 'sharp';

export const PRESET_NOTICE_SUCCESS: HapticPresetName = 'noticeSuccess';
export const PRESET_NOTICE_WARNING: HapticPresetName = 'noticeWarning';
export const PRESET_NOTICE_FAILURE: HapticPresetName = 'noticeFailure';
export const PRESET_SOFT: HapticPresetName = 'soft';
export const PRESET_HARD: HapticPresetName = 'hard';
export const PRESET_SHARP: HapticPresetName = 'sharp';

const COMMON_PRESET_API: number = 12;
const NOTICE_PRESET_API: number = 18;
export const PATTERN_API: number = 18;

export type HapticUsage = 'notification' | 'physicalFeedback' | 'touch';

export interface HapticPulse {
  readonly durationMs: number;
  readonly intensity: number;
  readonly startMs: number;
}

export interface HapticPreset {
  readonly count: number;
  readonly intensity: number;
  readonly minApi: number;
  readonly name: HapticPresetName;
}

export interface HapticRecipe {
  readonly fallbackMs: number;
  readonly pattern?: readonly HapticPulse[];
  readonly presets: readonly HapticPreset[];
  readonly usage: HapticUsage;
}

export function notificationRecipe(type: string): HapticRecipe | undefined {
  switch (type) {
    case NOTIFICATION_SUCCESS:
      return {
        fallbackMs: 80,
        pattern: [
          { durationMs: 40, intensity: 50, startMs: 0 },
          { durationMs: 40, intensity: 60, startMs: 140 },
        ],
        presets: [
          { count: 1, intensity: 50, minApi: NOTICE_PRESET_API, name: PRESET_NOTICE_SUCCESS },
          { count: 2, intensity: 50, minApi: COMMON_PRESET_API, name: PRESET_SOFT },
        ],
        usage: 'notification',
      };
    case NOTIFICATION_WARNING:
      return {
        fallbackMs: 100,
        pattern: [
          { durationMs: 40, intensity: 40, startMs: 0 },
          { durationMs: 60, intensity: 60, startMs: 160 },
        ],
        presets: [
          { count: 1, intensity: 60, minApi: NOTICE_PRESET_API, name: PRESET_NOTICE_WARNING },
          { count: 2, intensity: 60, minApi: COMMON_PRESET_API, name: PRESET_SHARP },
        ],
        usage: 'notification',
      };
    case NOTIFICATION_ERROR:
      return {
        fallbackMs: 150,
        pattern: [
          { durationMs: 60, intensity: 50, startMs: 0 },
          { durationMs: 40, intensity: 40, startMs: 160 },
          { durationMs: 50, intensity: 50, startMs: 280 },
        ],
        presets: [
          { count: 1, intensity: 70, minApi: NOTICE_PRESET_API, name: PRESET_NOTICE_FAILURE },
          { count: 3, intensity: 70, minApi: COMMON_PRESET_API, name: PRESET_HARD },
        ],
        usage: 'notification',
      };
    default:
      return undefined;
  }
}

export function impactRecipe(style: string): HapticRecipe | undefined {
  switch (style) {
    case IMPACT_LIGHT:
      return {
        fallbackMs: 20,
        pattern: [{ durationMs: 20, intensity: 20, startMs: 0 }],
        presets: [{ count: 1, intensity: 25, minApi: COMMON_PRESET_API, name: PRESET_SOFT }],
        usage: 'physicalFeedback',
      };
    case IMPACT_SOFT:
      return {
        fallbackMs: 20,
        presets: [{ count: 1, intensity: 30, minApi: COMMON_PRESET_API, name: PRESET_SOFT }],
        usage: 'physicalFeedback',
      };
    case IMPACT_MEDIUM:
      return {
        fallbackMs: 43,
        presets: [{ count: 1, intensity: 50, minApi: COMMON_PRESET_API, name: PRESET_HARD }],
        usage: 'physicalFeedback',
      };
    case IMPACT_HEAVY:
      return {
        fallbackMs: 61,
        presets: [{ count: 1, intensity: 70, minApi: COMMON_PRESET_API, name: PRESET_HARD }],
        usage: 'physicalFeedback',
      };
    case IMPACT_RIGID:
      return {
        fallbackMs: 43,
        presets: [{ count: 1, intensity: 50, minApi: COMMON_PRESET_API, name: PRESET_SHARP }],
        usage: 'physicalFeedback',
      };
    default:
      return undefined;
  }
}

export function selectionRecipe(): HapticRecipe {
  return {
    fallbackMs: 70,
    presets: [{ count: 1, intensity: 30, minApi: COMMON_PRESET_API, name: PRESET_SOFT }],
    usage: 'touch',
  };
}
