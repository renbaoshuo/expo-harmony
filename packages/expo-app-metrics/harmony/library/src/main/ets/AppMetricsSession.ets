/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction, ExpoModuleContext, ExpoSharedObject, ExpoSharedObjectClassDefinition, ExpoValueType, ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { LogRecord, Metric, Session } from './AppMetricsModels';
import { AppMetricsStorage } from './AppMetricsStorage';
import { ExpoAppMetricsError } from './ExpoAppMetricsError';

export const METRICS_RECORD = new ExpoValueType<Record<string, ESObject>>(
  'metrics record',
  (value: ESObject, _path: string): Record<string, ESObject> => {
    if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', 'Expected a metrics record object.');
    }
    return value as Record<string, ESObject>;
  },
  (value: Record<string, ESObject>, _path: string): ESObject => value,
);

export class AppMetricsSession extends ExpoSharedObject {
  readonly id: string;
  readonly type: string;
  readonly startDate: string;
  private readonly storage: AppMetricsStorage;
  private readonly onRelease: (session: AppMetricsSession) => void;

  constructor(context: ExpoModuleContext, storage: AppMetricsStorage, id: string, type: string, startDate: string, onRelease: (session: AppMetricsSession) => void) {
    super(context);
    this.storage = storage;
    this.onRelease = onRelease;
    this.id = id;
    this.type = type;
    this.startDate = startDate;
  }

  override sharedObjectWillRelease(): void { this.onRelease(this); }

  session(): Promise<Session | undefined> {
    return this.storage.getSessionRecord(this.id);
  }

  metrics(): Promise<Metric[]> { return this.storage.getMetrics(this.id); }
  logs(): Promise<LogRecord[]> { return this.storage.getLogs(this.id); }

  async addMetric(input: Record<string, ESObject>): Promise<void> {
    await this.storage.addMetrics(this.id, [createSessionMetric(this.storage, this.id, input)]);
  }
}

export function createSessionMetric(storage: AppMetricsStorage, sessionId: string, input: Record<string, ESObject>): Metric {
  const category: ESObject = input['category'];
  const name: ESObject = input['name'];
  const value: ESObject = input['value'];
  const timestamp: ESObject = input['timestamp'] ?? new Date().toISOString();
  if (typeof category !== 'string' || typeof name !== 'string' || typeof value !== 'number' || !Number.isFinite(value)
    || typeof timestamp !== 'string' || !Number.isFinite(Date.parse(timestamp))) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_METRIC', 'Expected a timestamp, category, name and finite metric value.');
  }

  const route = optionalMetricString(input['routeName'], 'routeName');
  const params = optionalMetricParams(input['params']);
  const metric = new Metric(storage.createSessionId(), sessionId, timestamp, category, name, value, route, params);
  metric.updateId = optionalMetricString(input['updateId'], 'updateId');

  return metric;
}

export function optionalMetricString(value: ESObject, field: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', `Expected '${field}' to be a string when provided.`);
  }
  return value;
}

export function optionalMetricParams(value: ESObject): Record<string, ESObject> | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', "Expected 'params' to be an object.");
  }

  try {
    return JSON.parse(JSON.stringify(value)) as Record<string, ESObject>;
  } catch (error) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_ARGUMENT', `Expected JSON-serializable metric parameters: ${String(error)}`);
  }
}

export function appMetricsSessionClass(): ExpoSharedObjectClassDefinition<AppMetricsSession> {
  return new ExpoSharedObjectClassDefinition<AppMetricsSession>('Session')
    .construct(ExpoFunction.ownedTyped0((_context: ExpoModuleContext): AppMetricsSession => {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_SESSION_CONSTRUCTOR', 'Sessions are managed natively; use getMainSession or getForegroundSession.');
    }))
    .property('id', ExpoValueTypes.string(), (session: AppMetricsSession): string => session.id)
    .property('type', ExpoValueTypes.string(), (session: AppMetricsSession): string => session.type)
    .property('startDate', ExpoValueTypes.string(), (session: AppMetricsSession): string => session.startDate)
    .asyncFunction('isActive', ExpoFunction.ownedTyped0(async (session: AppMetricsSession): Promise<boolean> => (await session.session())?.isActive ?? false))
    .asyncFunction('getEndDate', ExpoFunction.ownedTyped0(async (session: AppMetricsSession): Promise<string | null> => (await session.session())?.endTimestamp ?? null))
    .asyncFunction('getMetrics', ExpoFunction.ownedTyped0((session: AppMetricsSession): Promise<Metric[]> => session.metrics()))
    .asyncFunction('getLogs', ExpoFunction.ownedTyped0((session: AppMetricsSession): Promise<LogRecord[]> => session.logs()))
    .asyncFunction('addMetric', ExpoFunction.ownedTyped1(METRICS_RECORD, (session: AppMetricsSession, input: Record<string, ESObject>): Promise<void> => session.addMetric(input)));
}
