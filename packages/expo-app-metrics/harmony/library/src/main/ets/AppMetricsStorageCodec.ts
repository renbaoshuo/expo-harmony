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

export class DecodedEntryResult {
  entry: SessionWithMetrics;
  discardedInvalidMetric: boolean;

  constructor(entry: SessionWithMetrics, discardedInvalidMetric: boolean) {
    this.entry = entry;
    this.discardedInvalidMetric = discardedInvalidMetric;
  }
}

export function decodeEntry(value: ESObject): DecodedEntryResult | undefined {
  const input = asRecord(value);
  if (input === undefined) return undefined;

  const sessionInput = asRecord(input['session']);
  const metricsInput: ESObject = input['metrics'] as ESObject;
  if (sessionInput === undefined || !Array.isArray(metricsInput)) return undefined;

  const id = requiredNonEmptyString(sessionInput['id']);
  const timestamp = requiredNonEmptyString(sessionInput['startTimestamp']);
  const active: ESObject = sessionInput['isActive'] as ESObject;
  if (
    id === undefined
    || timestamp === undefined
    || typeof active !== 'boolean'
    || OPTIONAL_SESSION_FIELDS.some((field: string): boolean => !isOptionalString(sessionInput[field]))
  ) {
    return undefined;
  }

  const session = new Session(id, timestamp, optionalString(sessionInput['environment']));
  session.isActive = active;
  session.type = optionalString(sessionInput['type']) ?? 'unknown';
  session.endTimestamp = optionalString(sessionInput['endTimestamp']);
  session.appName = optionalString(sessionInput['appName']);
  session.appIdentifier = optionalString(sessionInput['appIdentifier']);
  session.appVersion = optionalString(sessionInput['appVersion']);
  session.appBuildNumber = optionalString(sessionInput['appBuildNumber']);
  session.appUpdateId = optionalString(sessionInput['appUpdateId']);
  session.appUpdateRuntimeVersion = optionalString(sessionInput['appUpdateRuntimeVersion']);
  session.appUpdateRequestHeaders = decodeRequestHeaders(sessionInput['appUpdateRequestHeaders']);
  session.appEasBuildId = optionalString(sessionInput['appEasBuildId']);
  session.deviceOs = optionalString(sessionInput['deviceOs']);
  session.deviceOsVersion = optionalString(sessionInput['deviceOsVersion']);
  session.deviceModel = optionalString(sessionInput['deviceModel']);
  session.deviceName = optionalString(sessionInput['deviceName']);
  session.expoSdkVersion = optionalString(sessionInput['expoSdkVersion']);
  session.reactNativeVersion = optionalString(sessionInput['reactNativeVersion']);
  session.clientVersion = optionalString(sessionInput['clientVersion']);
  session.languageTag = optionalString(sessionInput['languageTag']);

  const metrics: Metric[] = [];
  const metricIds = new Set<string>();
  let discarded = false;
  (metricsInput as ESObject[]).forEach((value: ESObject): void => {
    const metric = decodeMetric(value, id);
    if (metric === undefined || metricIds.has(metric.metricId)) {
      discarded = true;

      return;
    }

    metricIds.add(metric.metricId);
    metrics.push(metric);
  });

  const entry = new SessionWithMetrics(session, metrics);
  const logsInput: ESObject = input['logs'] as ESObject;
  if (Array.isArray(logsInput)) {
    (logsInput as ESObject[]).forEach((raw: ESObject): void => {
      const log = decodeLogRecord(raw);
      if (log !== undefined) entry.logs.push(log);
      else discarded = true;
    });
  }

  return new DecodedEntryResult(entry, discarded);
}

export function copyEntry(entry: SessionWithMetrics): SessionWithMetrics {
  const source = entry.session;
  const session = new Session(source.id, source.startTimestamp, source.environment);
  session.isActive = source.isActive;
  session.type = source.type;
  session.endTimestamp = source.endTimestamp;
  session.appName = source.appName;
  session.appIdentifier = source.appIdentifier;
  session.appVersion = source.appVersion;
  session.appBuildNumber = source.appBuildNumber;
  session.appUpdateId = source.appUpdateId;
  session.appUpdateRuntimeVersion = source.appUpdateRuntimeVersion;
  session.appUpdateRequestHeaders = decodeRequestHeaders(source.appUpdateRequestHeaders);
  session.appEasBuildId = source.appEasBuildId;
  session.deviceOs = source.deviceOs;
  session.deviceOsVersion = source.deviceOsVersion;
  session.deviceModel = source.deviceModel;
  session.deviceName = source.deviceName;
  session.expoSdkVersion = source.expoSdkVersion;
  session.reactNativeVersion = source.reactNativeVersion;
  session.clientVersion = source.clientVersion;
  session.languageTag = source.languageTag;

  const copy = new SessionWithMetrics(session, entry.metrics.map(copyMetric));
  copy.logs = entry.logs.map((log: LogRecord): LogRecord => copyLogRecord(log));

  return copy;
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

function decodeMetric(value: ESObject, sessionId: string): Metric | undefined {
  const input = asRecord(value);
  if (input === undefined) return undefined;

  const metricId = requiredNonEmptyString(input['metricId']);
  const timestamp = requiredNonEmptyString(input['timestamp']);
  const category = requiredString(input['category']);
  const name = requiredString(input['name']);
  const ownerId = requiredNonEmptyString(input['sessionId']);
  const amount: ESObject = input['value'] as ESObject;
  const params: ESObject = input['params'] as ESObject;
  if (
    metricId === undefined
    || timestamp === undefined
    || category === undefined
    || name === undefined
    || ownerId !== sessionId
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
