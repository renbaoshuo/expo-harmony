import type common from '@ohos.app.ability.common';
import util from '@ohos.util';
import { preferences } from '@kit.ArkData';
import { ExpoPlatformServiceError } from '@expo-harmony/expo-modules-core';

import { DEBUG } from '../../../BuildProfile';
import { AppMetadata, Metric, Session, SessionWithMetrics } from './AppMetricsModels';
import { retentionCutoffTimestamp } from './AppMetricsSemantics';
import { copyEntry, decodeEntry } from './AppMetricsStorageCodec';

const PREFERENCES_NAME: string = 'dev.expo.app-metrics';
const SESSIONS_KEY: string = 'sessions';
const PENDING_SESSIONS_KEY: string = 'sessions.pending';
const ENVIRONMENT_KEY: string = 'environment';
const DEFAULT_DEBUG_ENVIRONMENT: string = 'development';

const storages: WeakMap<common.UIAbilityContext, AppMetricsStorage> = new WeakMap<common.UIAbilityContext, AppMetricsStorage>();

export function appMetricsStorage(context: common.UIAbilityContext): AppMetricsStorage {
  let storage = storages.get(context);
  if (storage === undefined) {
    storage = new AppMetricsStorage(context);
    storages.set(context, storage);
  }

  return storage;
}

export class AppMetricsStorage {
  private readonly store: Promise<preferences.Preferences | null>;
  private readonly ready: Promise<void>;
  private sessions: SessionWithMetrics[] = [];
  private environment?: string;
  private failure?: ExpoPlatformServiceError;
  private queue: Promise<void> = Promise.resolve();

  constructor(context: common.UIAbilityContext) {
    this.store = preferences.getPreferences(context, { name: PREFERENCES_NAME }).catch((error: Object): preferences.Preferences | null => {
      this.failure = new ExpoPlatformServiceError('ERR_APP_METRICS_STORAGE', `Unable to open Expo App Metrics preferences: ${String(error)}`);
      console.warn(this.failure.message);

      return null;
    });

    this.ready = this.load();
  }

  createSessionId(): string {
    return util.generateRandomUUID(true);
  }

  scheduleStartSession(sessionId: string, timestamp: string, metadata: Promise<AppMetadata>): void {
    this.schedule(async (): Promise<void> => {
      if (this.findSession(sessionId) !== undefined) return;

      const info = await metadata;
      const session = new Session(sessionId, timestamp, this.environment, info);

      this.sessions.push(new SessionWithMetrics(session));

      await this.persist();
    });
  }

  scheduleStopSession(sessionId: string): void {
    this.stopSession(sessionId).catch((error: Object): void => {
      console.warn(`Unable to update Expo App Metrics storage: ${String(error)}`);
    });
  }

  async stopSession(sessionId: string): Promise<void> {
    await this.runMutation(async (): Promise<void> => {
      const entry = this.findSession(sessionId);
      if (entry === undefined || !entry.session.isActive) return;

      entry.session.isActive = false;

      await this.persist();
    });
  }

  scheduleStartupSession(sessionId: string, timestamp: string, metrics: Metric[], metadata: Promise<AppMetadata>): Promise<void> {
    return this.runMutation(async (): Promise<void> => {
      let entry = this.findSession(sessionId);
      if (entry === undefined) {
        const info = await metadata;
        const session = new Session(sessionId, timestamp, this.environment, info);
        entry = new SessionWithMetrics(session);

        this.sessions.push(entry);
      }

      const target: SessionWithMetrics = entry;

      target.session.startTimestamp = timestamp;

      const ids = new Set<string>(target.metrics.map((metric: Metric): string => metric.metricId));
      metrics.forEach((metric: Metric): void => {
        if (ids.has(metric.metricId)) return;

        target.metrics.push(metric);
        ids.add(metric.metricId);
      });

      await this.persist();
    });
  }

  async addMetrics(sessionId: string, metrics: Metric[]): Promise<void> {
    await this.runMutation(async (): Promise<void> => {
      const entry = this.findSession(sessionId);
      if (entry === undefined) {
        throw new ExpoPlatformServiceError('ERR_APP_METRICS_SESSION_NOT_FOUND', `No app metrics session exists for '${sessionId}'.`);
      }

      entry.metrics.push(...metrics);

      await this.persist();
    });
  }

  async getAllSessions(): Promise<SessionWithMetrics[]> {
    await this.ready;
    await this.queue;

    this.assertStorageAvailable();

    return this.sessions.map((entry: SessionWithMetrics): SessionWithMetrics => copyEntry(entry));
  }

  async clear(): Promise<void> {
    await this.runMutation(async (): Promise<void> => {
      await this.persistEntries([]);

      this.sessions = [];
      this.failure = undefined;
    }, true);
  }

  private schedule(task: () => Promise<void>): void {
    this.runMutation(task).catch((error: Object): void => {
      console.warn(`Unable to update Expo App Metrics storage: ${String(error)}`);
    });
  }

  private runMutation(task: () => Promise<void>, recover: boolean = false): Promise<void> {
    const next = this.queue
      .catch((): void => {})
      .then(async (): Promise<void> => {
        await this.ready;
        if (!recover) this.assertStorageAvailable();

        const snapshot = this.sessions.map((entry: SessionWithMetrics): SessionWithMetrics => copyEntry(entry));
        try {
          await task();
        } catch (error) {
          this.sessions = snapshot;

          if (error instanceof ExpoPlatformServiceError) {
            if (error.code === 'ERR_APP_METRICS_STORAGE') {
              this.failure = new ExpoPlatformServiceError(error.code, error.message);
            }

            throw new ExpoPlatformServiceError(error.code, error.message);
          }
          const message = `Unable to update Expo App Metrics preferences: ${String(error)}`;

          this.failure = new ExpoPlatformServiceError('ERR_APP_METRICS_STORAGE', message);

          throw new ExpoPlatformServiceError('ERR_APP_METRICS_STORAGE', message);
        }
      });

    this.queue = next.catch((): void => {});

    return next;
  }

  private findSession(sessionId: string): SessionWithMetrics | undefined {
    return this.sessions.find((entry: SessionWithMetrics): boolean => entry.session.id === sessionId);
  }

  private assertStorageAvailable(): void {
    if (this.failure !== undefined) {
      throw new ExpoPlatformServiceError(this.failure.code, this.failure.message);
    }
  }

  private async load(): Promise<void> {
    const store = await this.store;
    this.environment = DEBUG ? DEFAULT_DEBUG_ENVIRONMENT : undefined;
    if (store === null) return;

    try {
      const environment = await store.get(ENVIRONMENT_KEY, '');
      if (typeof environment === 'string' && environment.length > 0) this.environment = environment;

      const primary = await store.get(SESSIONS_KEY, '');
      const pending = await store.get(PENDING_SESSIONS_KEY, '');
      if (typeof primary !== 'string' || typeof pending !== 'string') {
        this.failure = new ExpoPlatformServiceError(
          'ERR_APP_METRICS_STORAGE',
          'Unable to decode Expo App Metrics preferences: Stored sessions are not a JSON string.',
        );
        console.warn(this.failure.message);

        return;
      }
      const recovering = pending.length > 0;
      const raw = recovering ? pending : primary;
      if (raw.length === 0) return;

      const decoded: ESObject = JSON.parse(raw);
      if (!Array.isArray(decoded)) {
        this.failure = new ExpoPlatformServiceError(
          'ERR_APP_METRICS_STORAGE',
          'Unable to decode Expo App Metrics preferences: Stored sessions are not a JSON array.',
        );
        console.warn(this.failure.message);

        return;
      }

      const sessions: SessionWithMetrics[] = [];
      const sessionIds = new Set<string>();
      const metricIds = new Set<string>();
      let changed = recovering;
      (decoded as ESObject[]).forEach((value: ESObject): void => {
        const result = decodeEntry(value);
        if (result === undefined) {
          changed = true;

          return;
        }

        const entry = result.entry;
        if (result.discardedInvalidMetric) changed = true;
        if (sessionIds.has(entry.session.id)) {
          changed = true;

          return;
        }

        const started = Date.parse(entry.session.startTimestamp);
        if (!Number.isFinite(started)) {
          changed = true;

          return;
        }

        sessionIds.add(entry.session.id);

        const metrics = entry.metrics.filter((metric: Metric): boolean => {
          const timestamp = Date.parse(metric.timestamp);
          if (!Number.isFinite(timestamp)) {
            changed = true;

            return false;
          }
          if (metricIds.has(metric.metricId)) {
            changed = true;

            return false;
          }

          metricIds.add(metric.metricId);

          return true;
        });
        if (metrics.length !== entry.metrics.length) {
          entry.metrics = metrics;
          changed = true;
        }

        if (entry.session.isActive) {
          entry.session.isActive = false;
          changed = true;
        }
        sessions.push(entry);
      });

      this.sessions = sessions;

      if (changed) await this.persist();
    } catch (error) {
      this.failure =
        error instanceof ExpoPlatformServiceError
          ? new ExpoPlatformServiceError(error.code, error.message)
          : new ExpoPlatformServiceError('ERR_APP_METRICS_STORAGE', `Unable to read Expo App Metrics preferences: ${String(error)}`);
      console.warn(this.failure.message);
    }
  }

  private async persist(): Promise<void> {
    const cutoff = retentionCutoffTimestamp(Date.now());
    const sessions = this.sessions.map((entry: SessionWithMetrics): SessionWithMetrics => {
      const copy = copyEntry(entry);

      copy.metrics = copy.metrics.filter((metric: Metric): boolean => Date.parse(metric.timestamp) >= cutoff);

      return copy;
    });

    await this.persistEntries(sessions);
  }

  private async persistEntries(sessions: SessionWithMetrics[]): Promise<void> {
    const store = await this.store;
    if (store === null) {
      throw new ExpoPlatformServiceError(
        this.failure?.code ?? 'ERR_APP_METRICS_STORAGE',
        this.failure?.message ?? 'Unable to open Expo App Metrics preferences: Preferences are unavailable.',
      );
    }

    try {
      const payload = JSON.stringify(sessions);

      await store.put(PENDING_SESSIONS_KEY, payload);
      await store.flush();

      await store.put(SESSIONS_KEY, payload);
      await store.flush();
    } catch (error) {
      throw new ExpoPlatformServiceError('ERR_APP_METRICS_STORAGE', `Unable to persist Expo App Metrics sessions: ${String(error)}`);
    }

    try {
      await store.delete(PENDING_SESSIONS_KEY);
      await store.flush();
    } catch (error) {
      console.warn(`Unable to remove the committed Expo App Metrics recovery record: ${String(error)}`);
    }
  }
}
