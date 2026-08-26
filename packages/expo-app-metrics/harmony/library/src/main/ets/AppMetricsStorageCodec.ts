import { Metric, Session, SessionWithMetrics } from './AppMetricsModels.ts';

const OPTIONAL_SESSION_FIELDS: string[] = [
  'environment',
  'appName',
  'appIdentifier',
  'appVersion',
  'appBuildNumber',
  'appUpdateId',
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
  session.appName = optionalString(sessionInput['appName']);
  session.appIdentifier = optionalString(sessionInput['appIdentifier']);
  session.appVersion = optionalString(sessionInput['appVersion']);
  session.appBuildNumber = optionalString(sessionInput['appBuildNumber']);
  session.appUpdateId = optionalString(sessionInput['appUpdateId']);
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

  return new DecodedEntryResult(new SessionWithMetrics(session, metrics), discarded);
}

export function copyEntry(entry: SessionWithMetrics): SessionWithMetrics {
  const source = entry.session;
  const session = new Session(source.id, source.startTimestamp, source.environment);
  session.isActive = source.isActive;
  session.appName = source.appName;
  session.appIdentifier = source.appIdentifier;
  session.appVersion = source.appVersion;
  session.appBuildNumber = source.appBuildNumber;
  session.appUpdateId = source.appUpdateId;
  session.appEasBuildId = source.appEasBuildId;
  session.deviceOs = source.deviceOs;
  session.deviceOsVersion = source.deviceOsVersion;
  session.deviceModel = source.deviceModel;
  session.deviceName = source.deviceName;
  session.expoSdkVersion = source.expoSdkVersion;
  session.reactNativeVersion = source.reactNativeVersion;
  session.clientVersion = source.clientVersion;
  session.languageTag = source.languageTag;

  const metrics = entry.metrics.map((item: Metric): Metric => {
    const metric = new Metric(
      item.metricId,
      item.sessionId,
      item.timestamp,
      item.category,
      item.name,
      item.value,
      item.routeName,
      copyParams(item.params)
    );
    metric.updateId = item.updateId;

    return metric;
  });

  return new SessionWithMetrics(session, metrics);
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
