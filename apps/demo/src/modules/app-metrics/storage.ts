import AppMetrics, { type Metric } from 'expo-app-metrics';

import { json } from '../../format';
import { isRecord } from './assertions';

export async function storedEntries(): Promise<Metric[]> {
  const entries: unknown = await AppMetrics.getStoredEntries();
  if (!Array.isArray(entries)) {
    throw new Error('getStoredEntries 在 HarmonyOS 上返回了非数组值。');
  }

  return entries.map((entry, index) => {
    if (
      !isRecord(entry)
      || typeof entry.sessionId !== 'string'
      || entry.sessionId.length === 0
      || typeof entry.timestamp !== 'string'
      || !Number.isFinite(Date.parse(entry.timestamp))
      || typeof entry.category !== 'string'
      || typeof entry.name !== 'string'
      || typeof entry.value !== 'number'
      || !Number.isFinite(entry.value)
    ) {
      throw new Error(`getStoredEntries 在索引 ${index} 处返回了无效指标。`);
    }

    return entry as unknown as Metric;
  });
}

export async function readAppMetricsStorage(): Promise<string> {
  const entries = await storedEntries();

  return json({ metrics: entries, storedMetricCount: entries.length });
}

export async function clearAppMetricsStorage(): Promise<string> {
  await AppMetrics.clearStoredEntries();

  const entries = await storedEntries();
  if (entries.length !== 0) throw new Error('clearStoredEntries() 之后仍有指标残留。');

  return 'clearStoredEntries() 已完成，getStoredEntries() 返回了空数组。';
}
