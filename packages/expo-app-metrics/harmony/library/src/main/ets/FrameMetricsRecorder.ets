/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { displaySync } from '@kit.ArkGraphics2D';
import { UIContext } from '@kit.ArkUI';

import { frameIntervalMilliseconds } from './AppMetricsSemantics';
import { FrameMetricsRecord } from './AppMetricsModels';
import { FrameMetricsAccumulator, FrameMetricsBaseline } from './FrameMetricsAccumulator';

export class FrameMetricsMonitor {
  private readonly warn: (message: string) => void;
  private readonly baseline = new FrameMetricsBaseline();
  private readonly recorders = new Set<FrameMetricsRecorder>();
  private observer?: displaySync.DisplaySync;
  private callback?: (info: displaySync.IntervalInfo) => void;
  private context: UIContext | null = null;

  constructor(warn: (message: string) => void) {
    this.warn = warn;
  }

  setUIContext(context: UIContext | null): void {
    if (context !== this.context) {
      this.detach();
      this.context = context;
    }

    this.attach();
  }

  start(recorder: FrameMetricsRecorder): void {
    this.recorders.add(recorder);
    this.attach();
    if (this.observer !== undefined) recorder.didStart();
  }

  stop(recorder: FrameMetricsRecorder): void {
    this.recorders.delete(recorder);
    if (this.recorders.size === 0) this.detach();
  }

  private attach(): void {
    const context = this.context;
    if (context === null || this.observer !== undefined || this.recorders.size === 0) return;

    try {
      const observer = displaySync.create();
      const callback = (info: displaySync.IntervalInfo): void => {
        if (observer === this.observer) this.processFrame(info);
      };

      this.observer = observer;
      this.callback = callback;
      observer.on('frame', callback);
      context.runScopedTask((): void => observer.start());
      this.recorders.forEach((recorder: FrameMetricsRecorder): void => recorder.didStart());
    } catch (error) {
      this.detach();
      this.warn(`Unable to start HarmonyOS frame interval monitoring: ${String(error)}`);
    }
  }

  private detach(): void {
    const observer = this.observer;
    const callback = this.callback;
    const context = this.context;

    this.observer = undefined;
    this.callback = undefined;
    this.baseline.reset();
    if (observer === undefined || callback === undefined || context === null) return;

    try {
      context.runScopedTask((): void => observer.stop());
    } catch (error) {
      this.warn(`Unable to stop HarmonyOS frame interval monitoring: ${String(error)}`);
    }

    try {
      observer.off('frame', callback);
    } catch (error) {
      this.warn(`Unable to remove HarmonyOS frame interval monitoring: ${String(error)}`);
    }
  }

  private processFrame(info: displaySync.IntervalInfo): void {
    const sample = this.baseline.sample(info.timestamp, info.targetTimestamp);
    if (sample === undefined) return;

    const interval = frameIntervalMilliseconds(
      sample.previousTimestampNs, sample.previousTargetTimestampNs, sample.timestampNs, sample.targetTimestampNs,
    );
    if (interval === undefined) return;

    this.recorders.forEach((recorder: FrameMetricsRecorder): void => {
      recorder.addInterval(interval.actualMs, interval.expectedMs);
    });
  }
}

export class FrameMetricsRecorder {
  private readonly monitor: FrameMetricsMonitor;
  private readonly frames = new FrameMetricsAccumulator();
  private started = false;

  constructor(monitor: FrameMetricsMonitor) {
    this.monitor = monitor;
  }

  start(): boolean {
    this.frames.begin();
    this.monitor.start(this);
    return this.started;
  }

  pause(): FrameMetricsRecord {
    this.monitor.stop(this);
    return this.frames.pause();
  }

  stop(): FrameMetricsRecord {
    this.monitor.stop(this);
    const result = this.frames.finish();
    this.started = false;

    return result;
  }

  addInterval(actualMs: number, expectedMs: number): void {
    this.frames.addInterval(actualMs, expectedMs);
  }

  didStart(): void { this.started = true; }
  hasStarted(): boolean { return this.started; }
  isRunning(): boolean { return this.frames.isActive(); }
  snapshot(): FrameMetricsRecord { return this.frames.snapshot(); }
}
