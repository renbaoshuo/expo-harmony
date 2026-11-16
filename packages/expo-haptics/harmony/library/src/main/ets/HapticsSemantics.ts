/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export type HapticNotification = 'success' | 'warning' | 'error';
export type HapticPresetName = 'soft' | 'hard' | 'sharp';

const ANDROID_MAX_AMPLITUDE: number = 255;
const HARMONY_MAX_INTENSITY: number = 100;

function notificationIntensity(amplitude: number): number {
  return Math.round(amplitude * HARMONY_MAX_INTENSITY / ANDROID_MAX_AMPLITUDE);
}

export type HapticUsage = 'notification' | 'physicalFeedback' | 'touch';

export interface HapticPulse {
  readonly durationMs: number;
  readonly intensity: number;
  readonly startMs: number;
}

export interface HapticPreset {
  readonly count: number;
  readonly intensity: number;
  readonly name: HapticPresetName;
}

export interface HapticRecipe {
  readonly fallbackMs: number;
  readonly notification?: HapticNotification;
  readonly pattern?: readonly HapticPulse[];
  readonly preset: HapticPreset;
  readonly usage: HapticUsage;
}

export function notificationRecipe(type: string): HapticRecipe | undefined {
  // Patterns retain SDK 57 HapticsNotificationType's timings, pauses and relative amplitudes.
  switch (type) {
    case 'success':
      return {
        fallbackMs: 80,
        notification: type,
        pattern: [
          { durationMs: 40, intensity: notificationIntensity(50), startMs: 0 },
          { durationMs: 40, intensity: notificationIntensity(60), startMs: 140 },
        ],
        preset: { count: 2, intensity: 50, name: 'soft' },
        usage: 'notification',
      };
    case 'warning':
      return {
        fallbackMs: 100,
        notification: type,
        pattern: [
          { durationMs: 40, intensity: notificationIntensity(40), startMs: 0 },
          { durationMs: 60, intensity: notificationIntensity(60), startMs: 160 },
        ],
        preset: { count: 2, intensity: 60, name: 'sharp' },
        usage: 'notification',
      };
    case 'error':
      return {
        fallbackMs: 150,
        notification: type,
        pattern: [
          { durationMs: 60, intensity: notificationIntensity(50), startMs: 0 },
          { durationMs: 40, intensity: notificationIntensity(40), startMs: 160 },
          { durationMs: 50, intensity: notificationIntensity(50), startMs: 280 },
        ],
        preset: { count: 3, intensity: 70, name: 'hard' },
        usage: 'notification',
      };
    default:
      return undefined;
  }
}

export function impactRecipe(style: string): HapticRecipe | undefined {
  // Timed fallbacks retain SDK 57 HapticsImpactType's oldSDKPattern durations.
  switch (style) {
    case 'light':
      return {
        fallbackMs: 20,
        preset: { count: 1, intensity: 25, name: 'soft' },
        usage: 'physicalFeedback',
      };
    case 'soft':
      return {
        fallbackMs: 20,
        preset: { count: 1, intensity: 30, name: 'soft' },
        usage: 'physicalFeedback',
      };
    case 'medium':
      return {
        fallbackMs: 43,
        preset: { count: 1, intensity: 50, name: 'hard' },
        usage: 'physicalFeedback',
      };
    case 'heavy':
      return {
        fallbackMs: 61,
        preset: { count: 1, intensity: 70, name: 'hard' },
        usage: 'physicalFeedback',
      };
    case 'rigid':
      return {
        fallbackMs: 43,
        preset: { count: 1, intensity: 50, name: 'sharp' },
        usage: 'physicalFeedback',
      };
    default:
      return undefined;
  }
}

export function selectionRecipe(): HapticRecipe {
  return {
    fallbackMs: 70,
    preset: { count: 1, intensity: 30, name: 'soft' },
    usage: 'touch',
  };
}
