import AppMetrics, { type AppStartupTimes, type FrameRateMetrics, type MemoryUsageSnapshot } from 'expo-app-metrics';

import { isRecord } from './assertions';

type HarmonyDiagnostics = {
  getAppStartupTimesAsync(): Promise<AppStartupTimes>;
  getFrameRateMetricsAsync(): Promise<FrameRateMetrics>;
  getMemoryUsageSnapshotAsync(): Promise<MemoryUsageSnapshot>;
  takeMemoryUsageSnapshotAsync(sessionId?: string): Promise<MemoryUsageSnapshot>;
};

export function diagnostics(): HarmonyDiagnostics {
  const native = AppMetrics as unknown as Partial<HarmonyDiagnostics>;
  if (
    typeof native.getAppStartupTimesAsync !== 'function'
    || typeof native.getFrameRateMetricsAsync !== 'function'
    || typeof native.getMemoryUsageSnapshotAsync !== 'function'
    || typeof native.takeMemoryUsageSnapshotAsync !== 'function'
  ) {
    throw new Error('Harmony App Metrics 诊断方法不可用；请检查原生 HAR 注册。');
  }

  return native as HarmonyDiagnostics;
}

function assertNonNegativeNumber(label: string, value: unknown): asserts value is number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw new Error(`${label} 不是有限的非负数：${String(value)}。`);
  }
}

export function assertMemorySnapshot(snapshot: MemoryUsageSnapshot): void {
  for (const key of ['physical', 'available'] as const) {
    assertNonNegativeNumber(`memory.${key}`, snapshot[key]);
    if (!Number.isSafeInteger(snapshot[key])) {
      throw new Error(`memory.${key} 不是安全整数：${String(snapshot[key])}。`);
    }
  }
}

export function assertFrameMetrics(metrics: FrameRateMetrics): void {
  for (const key of [
    'renderedFrames',
    'expectedFrames',
    'droppedFrames',
    'frozenFrames',
    'slowFrames',
    'freezeTime',
    'sessionDuration',
  ] as const) {
    assertNonNegativeNumber(`frames.${key}`, metrics[key]);
  }

  for (const key of [
    'renderedFrames',
    'expectedFrames',
    'droppedFrames',
    'frozenFrames',
    'slowFrames',
  ] as const) {
    if (!Number.isInteger(metrics[key])) {
      throw new Error(`frames.${key} 不是整数：${String(metrics[key])}。`);
    }
  }

  if (metrics.expectedFrames < metrics.renderedFrames) {
    throw new Error('frames.expectedFrames 小于 frames.renderedFrames。');
  }
  if (metrics.droppedFrames !== metrics.expectedFrames - metrics.renderedFrames) {
    throw new Error('frames.droppedFrames 与 expectedFrames - renderedFrames 不一致。');
  }
  if (metrics.frozenFrames > metrics.renderedFrames || metrics.slowFrames > metrics.renderedFrames) {
    throw new Error('frames.frozenFrames 或 frames.slowFrames 超过了 renderedFrames。');
  }
}

export function assertStartupTimes(times: AppStartupTimes): void {
  if (!isRecord(times)) throw new Error('getAppStartupTimesAsync 返回了非对象值。');

  const required = ['timeToFirstRender', 'timeToInteractive'];
  required.forEach((name) => {
    if (!(name in times)) throw new Error(`startup.${name} 未被记录。`);
  });

  if (Object.keys(times).length === 0) throw new Error('getAppStartupTimesAsync 未返回任何启动指标。');

  Object.entries(times).forEach(([name, value]) => {
    assertNonNegativeNumber(`startup.${name}`, value);
  });
}
