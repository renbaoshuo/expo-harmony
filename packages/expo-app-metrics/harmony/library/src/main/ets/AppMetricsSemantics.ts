import type { FrameMetricsRecord } from './AppMetricsModels';

export const SLOW_FRAME_THRESHOLD_MS: number = 17;
export const FROZEN_FRAME_THRESHOLD_MS: number = 700;
export const FRAME_DURATION_TOLERANCE_MS: number = 1;
export const METRICS_RETENTION_DAYS: number = 7;
const BYTES_PER_KILOBYTE: bigint = 1024n;
const MAX_SAFE_INTEGER_BYTES: bigint = BigInt(Number.MAX_SAFE_INTEGER);

export class AppMetricsServiceLifecycle {
  private active: boolean = true;

  isActive(): boolean {
    return this.active;
  }

  beginShutdown(): boolean {
    if (!this.active) return false;
    this.active = false;
    return true;
  }
}

export function elapsedSeconds(startMs: number, endMs: number): number | undefined {
  const duration = endMs - startMs;

  return Number.isFinite(duration) && duration >= 0 ? duration / 1000 : undefined;
}

export function processUptimeMilliseconds(seconds: number): number | undefined {
  if (!Number.isFinite(seconds) || seconds < 0) return undefined;

  const ms = seconds * 1000;

  return Number.isFinite(ms) ? ms : undefined;
}

export function processAgeMilliseconds(
  systemUptimeMs: number,
  processStartRealtimeMs: number
): number | undefined {
  if (
    !Number.isFinite(systemUptimeMs)
    || !Number.isFinite(processStartRealtimeMs)
    || systemUptimeMs < 0
    || processStartRealtimeMs < 0
    || processStartRealtimeMs > systemUptimeMs
  ) {
    return undefined;
  }

  return systemUptimeMs - processStartRealtimeMs;
}

export function processStartTimestampMs(nowMs: number, ageMs: number): number | undefined {
  if (
    !Number.isFinite(nowMs)
    || !Number.isFinite(ageMs)
    || ageMs < 0
    || ageMs > nowMs
  ) {
    return undefined;
  }

  return nowMs - ageMs;
}

export function frameIntervalMilliseconds(
  previousTimestampNs: number,
  previousTargetTimestampNs: number,
  timestampNs: number,
  targetTimestampNs: number
): { actualMs: number; expectedMs: number } | undefined {
  if (
    !Number.isFinite(previousTimestampNs)
    || !Number.isFinite(previousTargetTimestampNs)
    || !Number.isFinite(timestampNs)
    || !Number.isFinite(targetTimestampNs)
  ) {
    return undefined;
  }

  let actualMs = (timestampNs - previousTimestampNs) / 1_000_000;
  const previousExpectedMs = (previousTargetTimestampNs - previousTimestampNs) / 1_000_000;
  const expectedMs = (targetTimestampNs - previousTargetTimestampNs) / 1_000_000;
  if (
    !Number.isFinite(actualMs)
    || !Number.isFinite(expectedMs)
    || !Number.isFinite(previousExpectedMs)
    || actualMs < 0
    || previousExpectedMs <= 0
    || expectedMs <= 0
  ) {
    return undefined;
  }

  if (
    Math.abs(previousExpectedMs - expectedMs) <= FRAME_DURATION_TOLERANCE_MS
    && actualMs < expectedMs * 2 + FRAME_DURATION_TOLERANCE_MS
  ) {
    actualMs = expectedMs;
  }

  return { actualMs, expectedMs };
}

export function shouldRecordBundleLoad(
  interrupted: boolean,
  interactive: boolean,
  recorded: boolean,
  duration: number | undefined
): boolean {
  return !interrupted
    && !interactive
    && !recorded
    && duration !== undefined
    && Number.isFinite(duration)
    && duration > 0;
}

export function applyFrameInterval(
  record: FrameMetricsRecord,
  actualMs: number,
  expectedMs: number
): void {
  if (
    !Number.isFinite(actualMs)
    || !Number.isFinite(expectedMs)
    || actualMs < 0
    || expectedMs <= 0
  ) {
    return;
  }

  const delayed = actualMs > expectedMs + FRAME_DURATION_TOLERANCE_MS;
  const expectedFrames = delayed ? Math.max(1, Math.round(actualMs / expectedMs)) : 1;

  record.renderedFrames += 1;
  record.expectedFrames += expectedFrames;
  record.droppedFrames += expectedFrames - 1;
  record.sessionDurationMs += actualMs;

  if (actualMs >= FROZEN_FRAME_THRESHOLD_MS) record.frozenFrames += 1;
  if (actualMs >= SLOW_FRAME_THRESHOLD_MS) record.slowFrames += 1;
  record.freezeTimeMs += Math.max(0, actualMs - expectedMs);
}

export function frameRateMetricParams(record: FrameMetricsRecord): Record<string, number> {
  if (record.expectedFrames === 0) return {};

  return {
    'frameRate.slowFrames': record.slowFrames,
    'frameRate.frozenFrames': record.frozenFrames,
    'frameRate.totalDelay': record.freezeTimeMs / 1000,
  };
}

export function retentionCutoffTimestamp(nowMs: number): number {
  return nowMs - METRICS_RETENTION_DAYS * 24 * 60 * 60 * 1000;
}

export function kilobytesToBytes(value: bigint): number {
  if (value < 0n) {
    throw new RangeError('Harmony returned a memory value outside the JavaScript safe integer range.');
  }

  const bytes = value * BYTES_PER_KILOBYTE;
  if (bytes > MAX_SAFE_INTEGER_BYTES) {
    throw new RangeError('Harmony returned a memory value outside the JavaScript safe integer range.');
  }

  return Number(bytes);
}

export function remainingKilobytes(used: bigint, total: bigint): bigint {
  return used >= total ? 0n : total - used;
}
