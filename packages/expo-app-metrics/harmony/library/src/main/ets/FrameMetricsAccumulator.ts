/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { FrameMetricsRecord } from './AppMetricsModels.ts';
import { applyFrameInterval } from './AppMetricsSemantics.ts';

export type FrameSample = {
  previousTimestampNs: number;
  previousTargetTimestampNs: number;
  timestampNs: number;
  targetTimestampNs: number;
};

export class FrameMetricsBaseline {
  private lastTimestampNs?: number;
  private lastTargetNs?: number;

  reset(): void {
    this.lastTimestampNs = undefined;
    this.lastTargetNs = undefined;
  }

  sample(timestampNs: number, targetTimestampNs: number): FrameSample | undefined {
    const previousTimestampNs = this.lastTimestampNs;
    const previousTargetTimestampNs = this.lastTargetNs;

    this.lastTimestampNs = timestampNs;
    this.lastTargetNs = targetTimestampNs;

    if (previousTimestampNs === undefined || previousTargetTimestampNs === undefined) return undefined;

    return {
      previousTimestampNs,
      previousTargetTimestampNs,
      timestampNs,
      targetTimestampNs,
    };
  }
}

/**
 * UI-thread-confined frame state. `finish()` makes late DisplaySync callbacks
 * harmless before the observer is detached.
 */
export class FrameMetricsAccumulator {
  private record: FrameMetricsRecord = new FrameMetricsRecord();
  private active: boolean = false;

  begin(): void {
    this.active = true;
  }

  pause(): FrameMetricsRecord {
    this.active = false;
    return this.snapshot();
  }

  isActive(): boolean {
    return this.active;
  }

  addInterval(actualMs: number, expectedMs: number): void {
    if (!this.active) return;

    applyFrameInterval(this.record, actualMs, expectedMs);
  }

  snapshot(): FrameMetricsRecord {
    return copyFrameMetrics(this.record);
  }

  finish(): FrameMetricsRecord {
    this.active = false;

    const result = this.snapshot();

    this.record = new FrameMetricsRecord();

    return result;
  }
}

function copyFrameMetrics(source: FrameMetricsRecord): FrameMetricsRecord {
  const copy = new FrameMetricsRecord();
  copy.sessionDurationMs = source.sessionDurationMs;
  copy.renderedFrames = source.renderedFrames;
  copy.expectedFrames = source.expectedFrames;
  copy.droppedFrames = source.droppedFrames;
  copy.frozenFrames = source.frozenFrames;
  copy.slowFrames = source.slowFrames;
  copy.freezeTimeMs = source.freezeTimeMs;

  return copy;
}
