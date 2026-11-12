/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction, ExpoModuleContext, ExpoSharedObject, ExpoSharedObjectClassDefinition, ExpoValueType, ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { LogRecord, Metric, SessionWithMetrics } from './AppMetricsModels';
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

  async entry(): Promise<SessionWithMetrics | undefined> {
    return await this.storage.getSession(this.id);
  }

  async addMetric(input: Record<string, ESObject>): Promise<void> {
    const category: ESObject = input['category'];
    const name: ESObject = input['name'];
    const value: ESObject = input['value'];
    const timestamp: ESObject = input['timestamp'] ?? new Date().toISOString();
    const routeName: ESObject = input['routeName'];
    const params: ESObject = input['params'];

    if (typeof category !== 'string' || typeof name !== 'string' || typeof value !== 'number' || !Number.isFinite(value)
      || typeof timestamp !== 'string' || !Number.isFinite(Date.parse(timestamp))
      || (routeName !== null && routeName !== undefined && typeof routeName !== 'string')
      || (params !== null && params !== undefined && (typeof params !== 'object' || Array.isArray(params)))) {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_INVALID_METRIC', 'Session.addMetric expected a timestamp, category, name and finite value.');
    }

    await this.storage.addMetrics(this.id, [new Metric(
      this.storage.createSessionId(), this.id, timestamp, category, name, value,
      typeof routeName === 'string' ? routeName : undefined,
      params === null || params === undefined ? undefined : params as Record<string, ESObject>,
    )]);
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
    .asyncFunction('isActive', ExpoFunction.ownedTyped0(async (session: AppMetricsSession): Promise<boolean> => (await session.entry())?.session.isActive ?? false))
    .asyncFunction('getEndDate', ExpoFunction.ownedTyped0(async (session: AppMetricsSession): Promise<string | null> => (await session.entry())?.session.endTimestamp ?? null))
    .asyncFunction('getMetrics', ExpoFunction.ownedTyped0(async (session: AppMetricsSession): Promise<Metric[]> => (await session.entry())?.metrics ?? []))
    .asyncFunction('getLogs', ExpoFunction.ownedTyped0(async (session: AppMetricsSession): Promise<LogRecord[]> => (await session.entry())?.logs ?? []))
    .asyncFunction('addMetric', ExpoFunction.ownedTyped1(METRICS_RECORD, (session: AppMetricsSession, input: Record<string, ESObject>): Promise<void> => session.addMetric(input)));
}
