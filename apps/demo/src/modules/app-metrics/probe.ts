import AppMetrics from 'expo-app-metrics';

import { json } from '../../format';
import { expectErrorCode, isRecord } from './assertions';
import { assertFrameMetrics, assertMemorySnapshot, assertStartupTimes, diagnostics } from './diagnostics';
import { storedEntries, type StoredEntry } from './storage';

const PROBE_CATEGORY = 'expo-app-metrics-demo';

const PROBE_METRIC = 'custom-session-round-trip';

const PROBE_ROUTE = 'appMetrics';

const PROBE_SOURCE = 'harmony-demo';

const MEMORY_CATEGORY = 'memory';

const PHYSICAL_MEMORY_METRIC = 'physical';

const AVAILABLE_MEMORY_METRIC = 'available';

const POLL_INTERVAL_MS = 25;

const POLL_TIMEOUT_MS = 5_000;

async function waitForProbeMetric(sessionId: string): Promise<StoredEntry[]> {
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  let entries = await storedEntries();

  while (Date.now() < deadline) {
    const session = entries.find(entry => entry.session.id === sessionId);
    if (
      session !== undefined
      && !session.session.isActive
      && session.metrics.some(metric => metric.name === PROBE_METRIC)
    ) {
      return entries;
    }

    await new Promise<void>(resolve => setTimeout(resolve, POLL_INTERVAL_MS));
    entries = await storedEntries();
  }

  throw new Error(`在 ${POLL_TIMEOUT_MS}ms 内未观测到持久化的检测指标。`);
}

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

  const entries = await waitForProbeMetric(sessionId);
  const session = entries.find(entry => entry.session.id === sessionId);
  if (session === undefined) throw new Error('新创建的指标会话未被持久化。');
  if (session.session.isActive) throw new Error('stopSession() 之后会话仍处于活跃状态。');

  const metric = session.metrics.find(item => item.name === PROBE_METRIC);
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
  const persistedSession = persistedEntries.find(entry => entry.session.id === sessionId);
  if (persistedSession === undefined) throw new Error('内存快照会话未被持久化。');

  const persistedMemory = persistedSession.metrics.filter(
    metric => metric.category === MEMORY_CATEGORY
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
    session: {
      id: sessionId,
      isActive: session.session.isActive,
      startTimestamp: session.session.startTimestamp,
    },
    startupTimesSeconds: startup,
    storedMemoryBytes: storedMemory,
    storedSessionCount: persistedEntries.length,
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
