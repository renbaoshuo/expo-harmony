/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  APP_STARTUP_CATEGORY,
  AppMetadata,
  BUNDLE_LOAD_METRIC,
  FIRST_RENDER_METRIC,
  FrameMetricsRecord,
  INTERACTIVE_METRIC,
  Metric,
} from './AppMetricsModels.ts';
import {
  elapsedSeconds,
  frameRateMetricParams,
  processStartTimestampMs,
  shouldRecordBundleLoad,
} from './AppMetricsSemantics.ts';
import { mergeAttributes } from './AppMetricsLogging.ts';

export interface StartupMetricsStorage {
  createSessionId(): string;
  scheduleStartupSession(
    sessionId: string,
    timestamp: string,
    metrics: Metric[],
    metadata: Promise<AppMetadata>
  ): Promise<void>;
}
export interface StartupFrameRecorder {
  start(): boolean;
  stop(): FrameMetricsRecord;
  pause(): FrameMetricsRecord;
  snapshot(): FrameMetricsRecord;
  isRunning(): boolean;
}

export interface StartupMetricAttributes {
  routeName?: string;
  params?: Record<string, ESObject>;
}

export class ProcessClock {
  private readonly now: () => number;
  private timestamp: string;
  private revision: number = 0;
  private precise: boolean = false;

  constructor(now: () => number, ageMs: number | undefined) {
    this.now = now;

    const nowMs = this.now();

    this.timestamp = new Date(nowMs).toISOString();
    this.refineAt(nowMs, ageMs);
  }

  refine(ageMs: number | undefined): boolean {
    if (this.precise || ageMs === undefined) return false;

    return this.refineAt(this.now(), ageMs);
  }

  getTimestamp(): string {
    return this.timestamp;
  }

  getRevision(): number {
    return this.revision;
  }

  private refineAt(nowMs: number, ageMs: number | undefined): boolean {
    if (ageMs === undefined) return false;

    const startMs = processStartTimestampMs(nowMs, ageMs);
    if (startMs === undefined) return false;

    this.timestamp = new Date(startMs).toISOString();
    this.revision += 1;
    this.precise = true;

    return true;
  }
}

export interface StartupCoordinatorOptions {
  storage: StartupMetricsStorage;
  frameRecorder: StartupFrameRecorder;
  processClock: ProcessClock;
  metadata: () => Promise<AppMetadata>;
  now: () => number | undefined;
  warn: (message: string) => void;
}

export class StartupCoordinator {
  readonly appSessionId: string;
  private readonly storage: StartupMetricsStorage;
  private readonly frameRecorder: StartupFrameRecorder;
  private readonly processClock: ProcessClock;
  private readonly metadata: Promise<AppMetadata>;
  private readonly now: () => number | undefined;
  private readonly warn: (message: string) => void;
  private readonly metrics: Metric[] = [];
  private readonly clients: Set<number> = new Set<number>();
  private readonly foregroundClients: Set<number> = new Set<number>();
  private nextClientId: number = 1;
  private launchMs?: number;
  private launchTimestamp?: number;
  private finalFrames: FrameMetricsRecord = new FrameMetricsRecord();
  private bundleRecorded: boolean = false;
  private renderRecorded: boolean = false;
  private interactiveRecorded: boolean = false;
  private foregroundSeen: boolean = false;
  private interrupted: boolean = false;
  private shutdown: boolean = false;
  private scheduledCount: number = -1;
  private scheduledClockRevision: number = -1;

  constructor(options: StartupCoordinatorOptions) {
    this.storage = options.storage;
    this.frameRecorder = options.frameRecorder;
    this.processClock = options.processClock;
    this.metadata = options.metadata();
    this.now = options.now;
    this.warn = options.warn;
    this.appSessionId = this.storage.createSessionId();
    // SDK 57 creates the per-launch main session eagerly, even without a TTI mark.
    this.saveStartupMetricsIfNeeded();
  }

  getAppSessionStartTimestamp(): string {
    return this.processClock.getTimestamp();
  }

  retain(): number {
    const id = this.nextClientId;

    this.nextClientId += 1;
    this.clients.add(id);

    return id;
  }

  release(id: number): boolean {
    if (!this.clients.delete(id)) return false;

    this.foregroundClients.delete(id);
    if (this.clients.size > 0) return false;

    return this.finish();
  }

  isShutdown(): boolean {
    return this.shutdown;
  }

  onForeground(id: number): void {
    if (this.shutdown || !this.clients.has(id)) return;

    this.foregroundClients.add(id);
    if (this.foregroundSeen) return;

    this.recordForeground(this.now());
  }

  private recordForeground(ageMs: number | undefined): void {
    if (ageMs === undefined) return;

    const timestampChanged = this.processClock.refine(ageMs);

    this.foregroundSeen = true;
    this.launchMs = ageMs;
    this.launchTimestamp = Date.now();
    this.ensureFrameRecorderStarted();
    if (timestampChanged) this.saveStartupMetricsIfNeeded();
  }

  onBackground(id: number): void {
    if (this.shutdown || !this.clients.has(id)) return;

    this.foregroundClients.delete(id);
    if (this.foregroundClients.size > 0) return;

    this.saveStartupMetricsIfNeeded();
    if (this.interactiveRecorded || this.interrupted) return;

    this.interrupted = true;
    this.finalFrames = this.frameRecorder.stop();
  }

  onUIContextUnavailable(): void {
    this.frameRecorder.pause();
  }

  onUIContextAvailable(): void {
    if (
      this.shutdown
      || !this.foregroundSeen
      || this.foregroundClients.size === 0
    ) {
      return;
    }
    this.ensureFrameRecorderStarted();
  }

  markFirstRender(): void {
    if (this.interrupted || this.interactiveRecorded || this.renderRecorded) return;

    this.ensureFrameRecorderStarted();

    const launchMs = this.launchMs;
    if (launchMs === undefined) return;

    const nowMs = this.now();
    if (nowMs === undefined) return;

    const value = elapsedSeconds(launchMs, nowMs);
    if (value === undefined) return;

    this.renderRecorded = true;
    this.addStartupMetric(FIRST_RENDER_METRIC, value);
  }

  markInteractive(
    attributes: StartupMetricAttributes,
    readSystemParams?: (start: number, end: number) => Record<string, ESObject>,
  ): void {
    if (this.interrupted || this.interactiveRecorded) return;

    this.ensureFrameRecorderStarted();

    const launchMs = this.launchMs;
    const launchTimestamp = this.launchTimestamp;
    if (launchMs === undefined || launchTimestamp === undefined) return;

    const nowMs = this.now();
    if (nowMs === undefined) return;

    const value = elapsedSeconds(launchMs, nowMs);
    if (value === undefined) return;

    const markedAt = Date.now();

    this.interactiveRecorded = true;
    this.finalFrames = this.frameRecorder.stop();

    const frames = frameRateMetricParams(this.finalFrames);
    const system = readSystemParams?.(launchTimestamp, markedAt);
    const params = mergeAttributes(mergeAttributes(attributes.params, system), frames);

    this.addStartupMetric(INTERACTIVE_METRIC, value, attributes.routeName, Object.keys(params).length > 0 ? params : undefined);
  }

  getAppStartupTimes(): Record<string, number> {
    const times: Record<string, number> = {};

    this.metrics.forEach((metric: Metric): void => {
      times[metric.name] = metric.value;
    });

    return times;
  }

  currentFrameMetrics(): FrameMetricsRecord {
    return this.interactiveRecorded || this.interrupted
      ? this.finalFrames
      : this.frameRecorder.snapshot();
  }

  recordBundleLoad(duration?: number): void {
    if (!shouldRecordBundleLoad(
      this.interrupted,
      this.interactiveRecorded,
      this.bundleRecorded,
      duration
    )) {
      return;
    }

    this.bundleRecorded = true;
    this.addStartupMetric(BUNDLE_LOAD_METRIC, duration as number);
  }

  private finish(): boolean {
    if (this.shutdown) return false;

    this.shutdown = true;
    this.foregroundClients.clear();
    if (!this.interactiveRecorded && !this.interrupted) {
      this.interrupted = true;
      this.finalFrames = this.frameRecorder.stop();
    }
    this.saveStartupMetricsIfNeeded();

    return true;
  }

  private ensureFrameRecorderStarted(): void {
    if (!this.interrupted && !this.interactiveRecorded && !this.frameRecorder.isRunning()) {
      this.frameRecorder.start();
    }
  }

  private addStartupMetric(
    name: string,
    value: number,
    routeName?: string,
    params?: Record<string, ESObject>
  ): void {
    if (!Number.isFinite(value) || value < 0) return;

    this.metrics.push(new Metric(
      this.storage.createSessionId(),
      this.appSessionId,
      new Date().toISOString(),
      APP_STARTUP_CATEGORY,
      name,
      value,
      routeName,
      params
    ));
    this.saveStartupMetricsIfNeeded();
  }

  private saveStartupMetricsIfNeeded(): void {
    const count = this.metrics.length;
    const revision = this.processClock.getRevision();
    if (this.scheduledCount === count && this.scheduledClockRevision === revision) return;
    this.scheduledCount = count;
    this.scheduledClockRevision = revision;

    // Storage serializes transactions. Enqueue here so callers reading the
    // session immediately after a mark also wait for that mark to be stored.
    this.storage.scheduleStartupSession(
      this.appSessionId,
      this.processClock.getTimestamp(),
      this.metrics.slice(),
      this.metadata
    ).catch((error: unknown): void => {
      if (this.scheduledCount === count && this.scheduledClockRevision === revision) {
        this.scheduledCount = -1;
        this.scheduledClockRevision = -1;
      }
      this.warn(`Unable to save Expo App Metrics startup data: ${String(error)}`);
    });
  }
}
