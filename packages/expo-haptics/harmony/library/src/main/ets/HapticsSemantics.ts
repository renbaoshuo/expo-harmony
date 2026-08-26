export const NOTIFICATION_SUCCESS: string = 'success';
export const NOTIFICATION_WARNING: string = 'warning';
export const NOTIFICATION_ERROR: string = 'error';

export const IMPACT_LIGHT: string = 'light';
export const IMPACT_MEDIUM: string = 'medium';
export const IMPACT_HEAVY: string = 'heavy';
export const IMPACT_SOFT: string = 'soft';
export const IMPACT_RIGID: string = 'rigid';

export const PRESET_NOTICE_SUCCESS: string = 'noticeSuccess';
export const PRESET_NOTICE_WARNING: string = 'noticeWarning';
export const PRESET_NOTICE_FAILURE: string = 'noticeFailure';
export const PRESET_SOFT: string = 'soft';
export const PRESET_HARD: string = 'hard';
export const PRESET_SHARP: string = 'sharp';

export const COMMON_PRESET_API: number = 12;
export const NOTICE_PRESET_API: number = 18;
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
  readonly name: string;
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
