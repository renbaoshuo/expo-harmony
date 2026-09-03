import displaySync from '@ohos.graphics.displaySync';
import { UIContext } from '@kit.ArkUI';

import { frameIntervalMilliseconds } from './AppMetricsSemantics';
import { FrameMetricsRecord } from './AppMetricsModels';
import { FrameMetricsAccumulator, FrameMetricsBaseline } from './FrameMetricsAccumulator';

export class FrameMetricsRecorder {
  private readonly getUIContext: () => UIContext | null;
  private readonly warn: (message: string) => void;
  private readonly frames: FrameMetricsAccumulator = new FrameMetricsAccumulator();
  private readonly baseline: FrameMetricsBaseline = new FrameMetricsBaseline();
  private readonly callback: (info: displaySync.IntervalInfo) => void;
  private observer?: displaySync.DisplaySync;
  private uiContext?: UIContext;
  private started: boolean = false;

  constructor(getUIContext: () => UIContext | null, warn: (message: string) => void) {
    this.getUIContext = getUIContext;
    this.warn = warn;
    this.callback = (info: displaySync.IntervalInfo): void => this.processFrame(info);
  }

  start(): boolean {
    if (this.observer !== undefined) return true;

    this.baseline.reset();

    let context: UIContext | null;
    try {
      context = this.getUIContext();
    } catch (error) {
      this.warn(`Unable to obtain the HarmonyOS UI context for frame interval monitoring: ${String(error)}`);

      return false;
    }
    if (context === null) {
      this.warn('Unable to start HarmonyOS frame interval monitoring without an active UI context.');

      return false;
    }

    let observer: displaySync.DisplaySync | undefined;
    try {
      const current = displaySync.create();
      current.on('frame', this.callback);
      observer = current;

      this.observer = observer;
      this.uiContext = context;
      this.frames.begin();
      context.runScopedTask((): void => current.start());
      this.started = true;

      return true;
    } catch (error) {
      this.observer = undefined;
      this.uiContext = undefined;
      this.baseline.reset();
      this.frames.pause();
      cleanupObserver(observer, this.callback, this.warn);
      this.warn(`Unable to start HarmonyOS frame interval monitoring: ${String(error)}`);

      return false;
    }
  }

  stop(): FrameMetricsRecord {
    const result = this.frames.finish();
    this.detachObserver();

    return result;
  }

  pause(): FrameMetricsRecord {
    const result = this.frames.pause();
    this.detachObserver();

    return result;
  }

  hasStarted(): boolean {
    return this.started;
  }

  private detachObserver(): void {
    this.baseline.reset();
    const observer = this.observer;
    const context = this.uiContext;

    this.observer = undefined;
    this.uiContext = undefined;

    if (observer !== undefined) {
      try {
        if (context === undefined) {
          observer.stop();
        } else {
          context.runScopedTask((): void => observer.stop());
        }
      } catch (error) {
        this.warn(`Unable to stop HarmonyOS frame interval monitoring: ${String(error)}`);
      }

      try {
        observer.off('frame', this.callback);
      } catch (error) {
        this.warn(`Unable to remove HarmonyOS frame interval monitoring: ${String(error)}`);
      }
    }
  }

  snapshot(): FrameMetricsRecord {
    return this.frames.snapshot();
  }

  isRunning(): boolean {
    return this.frames.isActive();
  }

  private processFrame(info: displaySync.IntervalInfo): void {
    const sample = this.baseline.sample(this.frames.isActive(), info.timestamp, info.targetTimestamp);
    if (sample === undefined) return;

    const interval = frameIntervalMilliseconds(
      sample.previousTimestampNs,
      sample.previousTargetTimestampNs,
      sample.timestampNs,
      sample.targetTimestampNs,
    );
    if (interval === undefined) return;

    this.frames.addInterval(interval.actualMs, interval.expectedMs);
  }
}

function cleanupObserver(
  observer: displaySync.DisplaySync | undefined,
  callback: (info: displaySync.IntervalInfo) => void,
  warn: (message: string) => void,
): void {
  if (observer === undefined) return;

  try {
    observer.stop();
  } catch (error) {
    warn(`Unable to stop HarmonyOS frame interval monitoring during cleanup: ${String(error)}`);
  } finally {
    try {
      observer.off('frame', callback);
    } catch (error) {
      warn(`Unable to remove HarmonyOS frame interval monitoring during cleanup: ${String(error)}`);
    }
  }
}
