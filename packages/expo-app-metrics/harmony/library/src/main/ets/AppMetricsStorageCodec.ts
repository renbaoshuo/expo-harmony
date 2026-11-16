/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { LogRecord, Metric, Session, SessionWithMetrics } from './AppMetricsModels.ts';
import { CrashReport, decodeCrashReport } from './AppMetricsCrashReport.ts';

const OPTIONAL_SESSION_FIELDS: string[] = [
  'type',
  'endTimestamp',
  'environment',
  'appName',
  'appIdentifier',
  'appVersion',
  'appBuildNumber',
  'appUpdateId',
  'appUpdateRuntimeVersion',
  'appEasBuildId',
  'deviceOs',
  'deviceOsVersion',
  'deviceModel',
  'deviceName',
  'expoSdkVersion',
  'reactNativeVersion',
  'clientVersion',
  'languageTag',
];

export function decodeSession(value: ESObject): Session | undefined {
  const input = asRecord(value);
  if (input === undefined) return undefined;

  const id = requiredNonEmptyString(input['id']);
  const timestamp = requiredNonEmptyString(input['startTimestamp']);
  const active: ESObject = input['isActive'] as ESObject;
  if (
    id === undefined
    || timestamp === undefined
    || typeof active !== 'boolean'
    || OPTIONAL_SESSION_FIELDS.some((field: string): boolean => !isOptionalString(input[field]))
  ) {
    return undefined;
  }

  const session = new Session(id, timestamp, optionalString(input['environment']));
  session.isActive = active;
  session.type = optionalString(input['type']) ?? 'unknown';
  session.endTimestamp = optionalString(input['endTimestamp']);
  session.appName = optionalString(input['appName']);
  session.appIdentifier = optionalString(input['appIdentifier']);
  session.appVersion = optionalString(input['appVersion']);
  session.appBuildNumber = optionalString(input['appBuildNumber']);
  session.appUpdateId = optionalString(input['appUpdateId']);
  session.appUpdateRuntimeVersion = optionalString(input['appUpdateRuntimeVersion']);
  session.appUpdateRequestHeaders = decodeRequestHeaders(input['appUpdateRequestHeaders']);
  session.appEasBuildId = optionalString(input['appEasBuildId']);
  session.deviceOs = optionalString(input['deviceOs']);
  session.deviceOsVersion = optionalString(input['deviceOsVersion']);
  session.deviceModel = optionalString(input['deviceModel']);
  session.deviceName = optionalString(input['deviceName']);
  session.expoSdkVersion = optionalString(input['expoSdkVersion']);
  session.reactNativeVersion = optionalString(input['reactNativeVersion']);
  session.clientVersion = optionalString(input['clientVersion']);
  session.languageTag = optionalString(input['languageTag']);

  return session;
}

export function decodeEntry(value: ESObject): SessionWithMetrics | undefined {
  const input = asRecord(value);
  if (input === undefined) return undefined;

  const session = decodeSession(input['session']);
  const metrics: ESObject = input['metrics'];
  if (session === undefined || !Array.isArray(metrics)) return undefined;

  const entry = new SessionWithMetrics(session);
  for (const value of metrics as ESObject[]) {
    const metric = decodeMetric(value);
    if (metric?.sessionId === session.id) entry.metrics.push(metric);
  }

  const logs: ESObject = input['logs'];
  if (Array.isArray(logs)) {
    for (const value of logs as ESObject[]) {
      const log = decodeLogRecord(value);
      if (log !== undefined) entry.logs.push(log);
    }
  }

  return entry;
}

function decodeRequestHeaders(value: ESObject): Record<string, string> | undefined {
  const input = asRecord(value);
  if (input === undefined || Object.keys(input).some((key: string): boolean => typeof input[key] !== 'string')) return undefined;
  return JSON.parse(JSON.stringify(input)) as Record<string, string>;
}

export function copyMetric(item: Metric): Metric {
  const metric = new Metric(item.metricId, item.sessionId, item.timestamp, item.category, item.name,
    item.value, item.routeName, copyParams(item.params));
  metric.updateId = item.updateId;
  return metric;
}

export function decodeMetric(value: ESObject): Metric | undefined {
  const input = asRecord(value);
  if (input === undefined) return undefined;

  const metricId = requiredNonEmptyString(input['metricId']);
  const timestamp = requiredNonEmptyString(input['timestamp']);
  const category = requiredString(input['category']);
  const name = requiredString(input['name']);
  const sessionId = requiredNonEmptyString(input['sessionId']);
  const amount: ESObject = input['value'] as ESObject;
  const params: ESObject = input['params'] as ESObject;
  if (
    metricId === undefined
    || timestamp === undefined
    || category === undefined
    || name === undefined
    || sessionId === undefined
    || typeof amount !== 'number'
    || !Number.isFinite(amount)
    || !isOptionalString(input['routeName'])
    || !isOptionalString(input['updateId'])
    || !isOptionalRecord(params)
  ) {
    return undefined;
  }

  const metric = new Metric(
    metricId,
    sessionId,
    timestamp,
    category,
    name,
    amount,
    optionalString(input['routeName']),
    optionalRecord(input['params'])
  );
  metric.updateId = optionalString(input['updateId']);

  return metric;
}

function copyParams(value: Record<string, ESObject> | undefined): Record<string, ESObject> | undefined {
  if (value === undefined) return undefined;

  const copy: ESObject = JSON.parse(JSON.stringify(value));

  return copy as Record<string, ESObject>;
}

function asRecord(value: ESObject): Record<string, ESObject> | undefined {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return undefined;
  return value as Record<string, ESObject>;
}

function optionalRecord(value: ESObject): Record<string, ESObject> | undefined {
  return asRecord(value);
}

function isOptionalRecord(value: ESObject): boolean {
  return value === undefined || value === null || asRecord(value) !== undefined;
}

function requiredNonEmptyString(value: ESObject): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function requiredString(value: ESObject): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

function optionalString(value: ESObject): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

function isOptionalString(value: ESObject): boolean {
  return value === undefined || value === null || typeof value === 'string';
}

export function copyLogRecord(source: LogRecord): LogRecord {
  const copy = new LogRecord(source.timestamp, source.name, source.severity, source.body, copyParams(source.attributes));
  copy.recordId = source.recordId;
  copy.droppedAttributesCount = source.droppedAttributesCount;
  return copy;
}

export function decodeLogRecord(value: ESObject): LogRecord | undefined {
  const input = asRecord(value);
  if (input === undefined) return undefined;

  const timestamp = requiredNonEmptyString(input['timestamp']);
  const name = requiredNonEmptyString(input['name']);
  const severity = requiredNonEmptyString(input['severity']);
  if (timestamp === undefined || !Number.isFinite(Date.parse(timestamp)) || name === undefined || severity === undefined
    || !['trace', 'debug', 'info', 'warn', 'error', 'fatal'].includes(severity)
    || !isOptionalString(input['body']) || !isOptionalRecord(input['attributes'])) return undefined;

  const log = new LogRecord(timestamp, name, severity, optionalString(input['body']), optionalRecord(input['attributes']));
  log.recordId = optionalString(input['recordId']);
  const count: ESObject = input['droppedAttributesCount'] as ESObject;
  if (typeof count === 'number' && Number.isSafeInteger(count) && count >= 0) log.droppedAttributesCount = count;

  return log;
}

export class MetricsStoragePayload {
  sessions: ESObject[];
  crashReports: CrashReport[];
  constructor(sessions: ESObject[], crashReports: CrashReport[]) {
    this.sessions = sessions;
    this.crashReports = crashReports;
  }
}

export function decodeStoredMetricsPayload(value: ESObject): MetricsStoragePayload | undefined {
  // Upgrade the SDK 55 sessions-only record in place without discarding history.
  if (Array.isArray(value)) return new MetricsStoragePayload(value as ESObject[], []);
  const input = asRecord(value);
  if (input === undefined || !Array.isArray(input['sessions']) || !Array.isArray(input['crashReports'])) return undefined;

  const reports: CrashReport[] = [];
  (input['crashReports'] as ESObject[]).forEach((raw: ESObject): void => {
    const report = decodeCrashReport(raw);
    if (report !== undefined && !reports.some((stored: CrashReport): boolean => stored.eventId === report.eventId)) reports.push(report);
  });

  return new MetricsStoragePayload(input['sessions'] as ESObject[], reports);
}
