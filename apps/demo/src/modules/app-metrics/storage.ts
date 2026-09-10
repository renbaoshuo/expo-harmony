import AppMetrics, { type Metric } from 'expo-app-metrics';

import { json } from '../../format';
import { isRecord } from './assertions';

export type StoredEntry = {
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

export async function storedEntries(): Promise<StoredEntry[]> {
  return readStoredEntries(await AppMetrics.getStoredEntries());
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
