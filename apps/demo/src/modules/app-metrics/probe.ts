import AppMetrics from 'expo-app-metrics';

import { json } from '../../format';
import { expectErrorCode, isRecord } from './assertions';
import { assertFrameMetrics, assertMemorySnapshot, assertStartupTimes, diagnostics } from './diagnostics';
import { storedEntries } from './storage';

const PROBE_CATEGORY = 'expo-app-metrics-demo';

const PROBE_METRIC = 'custom-session-round-trip';

const PROBE_ROUTE = 'appMetrics';

const PROBE_SOURCE = 'harmony-demo';

const MEMORY_CATEGORY = 'memory';

const PHYSICAL_MEMORY_METRIC = 'physical';

const AVAILABLE_MEMORY_METRIC = 'available';

export async function runAppMetricsMatrix(): Promise<string> {
  await AppMetrics.clearStoredEntries();

  const sessionId = AppMetrics.startSession();
  await AppMetrics.addCustomMetricToSession(sessionId, {
    category: PROBE_CATEGORY,
    name: PROBE_METRIC,
    params: { source: PROBE_SOURCE },
    routeName: PROBE_ROUTE,
    value: 1.25,
  });
  AppMetrics.stopSession(sessionId);

  AppMetrics.markFirstRender();
  AppMetrics.markInteractive({
    params: { source: PROBE_SOURCE },
    routeName: PROBE_ROUTE,
  });

  const entries = await storedEntries();
  const metric = entries.find(item => item.sessionId === sessionId && item.name === PROBE_METRIC);
  if (
    metric === undefined
    || metric.sessionId !== sessionId
    || metric.value !== 1.25
    || metric.routeName !== PROBE_ROUTE
    || !Number.isFinite(Date.parse(metric.timestamp))
  ) {
    throw new Error('持久化的自定义指标未保留其数值或路由名。');
  }
  if (!isRecord(metric.params) || metric.params.source !== PROBE_SOURCE) {
    throw new Error('持久化的自定义指标未保留其 JSON 参数。');
  }

  const native = diagnostics();
  const [startup, memory, frames, storedMemory] = await Promise.all([
    native.getAppStartupTimesAsync(),
    native.getMemoryUsageSnapshotAsync(),
    native.getFrameRateMetricsAsync(),
    native.takeMemoryUsageSnapshotAsync(sessionId),
  ]);
  assertStartupTimes(startup);
  assertMemorySnapshot(memory);
  assertMemorySnapshot(storedMemory);
  assertFrameMetrics(frames);

  const persistedEntries = await storedEntries();
  const persistedMemory = persistedEntries.filter(
    metric => metric.sessionId === sessionId
      && metric.category === MEMORY_CATEGORY
      && (metric.name === PHYSICAL_MEMORY_METRIC || metric.name === AVAILABLE_MEMORY_METRIC)
  );
  if (
    persistedMemory.length !== 2
    || !persistedMemory.some(metric => metric.name === PHYSICAL_MEMORY_METRIC && metric.value === storedMemory.physical)
    || !persistedMemory.some(
      metric => metric.name === AVAILABLE_MEMORY_METRIC && metric.value === storedMemory.available
    )
  ) {
    throw new Error('takeMemoryUsageSnapshotAsync() 未在目标会话中持久化两条内存指标。');
  }

  const invalidSession = await expectErrorCode(
    'addCustomMetricToSession(空会话 ID)',
    'ERR_APP_METRICS_INVALID_SESSION',
    () => AppMetrics.addCustomMetricToSession('', {
      category: PROBE_CATEGORY,
      name: 'invalid-session',
      value: 0,
    })
  );

  return json({
    customMetric: {
      name: metric.name,
      params: metric.params,
      routeName: metric.routeName,
      value: metric.value,
    },
    frameMetrics: frames,
    invalidSession,
    memoryBytes: memory,
    sessionId,
    startupTimesSeconds: startup,
    storedMemoryBytes: storedMemory,
    storedMetricCount: persistedEntries.length,
  });
}

export function markAppMetricsFirstRender(): string {
  AppMetrics.markFirstRender();

  return 'markFirstRender() 已完成；该原生事件每次应用启动最多记录一次。';
}

export function markAppMetricsInteractive(): string {
  AppMetrics.markInteractive({
    params: { source: PROBE_SOURCE },
    routeName: PROBE_ROUTE,
  });

  return 'markInteractive() 已完成；官方封装内部也会尝试调用 markFirstRender()。';
}
