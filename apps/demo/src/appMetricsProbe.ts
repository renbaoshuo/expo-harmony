import AppMetrics, {
  type AppStartupTimes,
  type FrameRateMetrics,
  type MemoryUsageSnapshot,
  type Metric,
} from 'expo-app-metrics';

const PROBE_CATEGORY = 'expo-app-metrics-demo';
const PROBE_METRIC = 'custom-session-round-trip';
const PROBE_ROUTE = 'appMetrics';
const PROBE_SOURCE = 'harmony-demo';
const MEMORY_CATEGORY = 'memory';
const PHYSICAL_MEMORY_METRIC = 'physical';
const AVAILABLE_MEMORY_METRIC = 'available';
const POLL_INTERVAL_MS = 25;
const POLL_TIMEOUT_MS = 5_000;

type StoredEntry = {
  metrics: StoredMetric[];
  session: {
    id: string;
    isActive: boolean;
    startTimestamp: string;
  };
};

type StoredMetric = Metric & {
  metricId: string;
};

type HarmonyDiagnostics = {
  getAppStartupTimesAsync(): Promise<AppStartupTimes>;
  getFrameRateMetricsAsync(): Promise<FrameRateMetrics>;
  getMemoryUsageSnapshotAsync(): Promise<MemoryUsageSnapshot>;
  takeMemoryUsageSnapshotAsync(sessionId?: string): Promise<MemoryUsageSnapshot>;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function errorCode(error: unknown): string | undefined {
  if (!isRecord(error)) return undefined;

  return typeof error.code === 'string' ? error.code : undefined;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (isRecord(error) && typeof error.message === 'string') return error.message;

  return String(error);
}

function json(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

function readStoredEntries(value: unknown): StoredEntry[] {
  if (!Array.isArray(value)) {
    throw new Error('getStoredEntries 在 HarmonyOS 上返回了非数组值。');
  }

  const ids = new Set<string>();
  const sessionIds = new Set<string>();

  const entries = value.map((raw, index) => {
    if (!isRecord(raw) || !isRecord(raw.session) || !Array.isArray(raw.metrics)) {
      throw new Error(`getStoredEntries 在索引 ${index} 处返回了无效的会话条目。`);
    }

    const session = raw.session;
    if (
      typeof session.id !== 'string'
      || session.id.length === 0
      || typeof session.isActive !== 'boolean'
      || typeof session.startTimestamp !== 'string'
      || !Number.isFinite(Date.parse(session.startTimestamp))
    ) {
      throw new Error(`getStoredEntries 在索引 ${index} 处返回了无效的会话元数据。`);
    }
    if (sessionIds.has(session.id)) {
      throw new Error(`getStoredEntries 返回了重复的会话 ID '${session.id}'。`);
    }

    sessionIds.add(session.id);

    const metrics = raw.metrics.map((candidate, metricIndex) => {
      if (
        !isRecord(candidate)
        || typeof candidate.metricId !== 'string'
        || candidate.metricId.length === 0
        || typeof candidate.sessionId !== 'string'
        || candidate.sessionId !== session.id
        || typeof candidate.timestamp !== 'string'
        || !Number.isFinite(Date.parse(candidate.timestamp))
        || typeof candidate.category !== 'string'
        || typeof candidate.name !== 'string'
        || typeof candidate.value !== 'number'
        || !Number.isFinite(candidate.value)
      ) {
        throw new Error(`getStoredEntries 在 ${index}:${metricIndex} 处返回了无效指标。`);
      }
      if (ids.has(candidate.metricId)) {
        throw new Error(`getStoredEntries 返回了重复的指标 ID '${candidate.metricId}'。`);
      }

      ids.add(candidate.metricId);

      return candidate as unknown as StoredMetric;
    });

    return {
      metrics,
      session: {
        id: session.id,
        isActive: session.isActive,
        startTimestamp: session.startTimestamp,
      },
    };
  });

  return entries;
}

async function storedEntries(): Promise<StoredEntry[]> {
  return readStoredEntries(await AppMetrics.getStoredEntries());
}

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

function diagnostics(): HarmonyDiagnostics {
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

function assertMemorySnapshot(snapshot: MemoryUsageSnapshot): void {
  for (const key of ['physical', 'available'] as const) {
    assertNonNegativeNumber(`memory.${key}`, snapshot[key]);
    if (!Number.isSafeInteger(snapshot[key])) {
      throw new Error(`memory.${key} 不是安全整数：${String(snapshot[key])}。`);
    }
  }
}

function assertFrameMetrics(metrics: FrameRateMetrics): void {
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

function assertStartupTimes(times: AppStartupTimes): void {
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

async function expectErrorCode(
  label: string,
  expectedCode: string,
  operation: () => Promise<unknown>
): Promise<{ code: string; label: string }> {
  try {
    await operation();
  } catch (error) {
    const code = errorCode(error);
    if (code !== expectedCode) {
      throw new Error(`${label} 以 ${code ?? errorMessage(error)} 拒绝，而非 ${expectedCode}。`);
    }

    return { code, label };
  }

  throw new Error(`${label} 不应成功返回。`);
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

export async function readAppMetricsStorage(): Promise<string> {
  const entries = await storedEntries();

  return json({
    sessions: entries.map(entry => ({
      id: entry.session.id,
      isActive: entry.session.isActive,
      metricNames: entry.metrics.map(metric => metric.name),
    })),
    storedSessionCount: entries.length,
  });
}

export async function clearAppMetricsStorage(): Promise<string> {
  await AppMetrics.clearStoredEntries();
  const entries = await storedEntries();

  if (entries.length !== 0) throw new Error('clearStoredEntries() 之后仍有会话残留。');

  return 'clearStoredEntries() 已完成，getStoredEntries() 返回了空数组。';
}
