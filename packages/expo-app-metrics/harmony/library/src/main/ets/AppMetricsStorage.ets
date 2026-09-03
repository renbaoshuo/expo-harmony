import type common from '@ohos.app.ability.common';
import util from '@ohos.util';
import { preferences } from '@kit.ArkData';
import { AppMetadata, Metric, Session, SessionWithMetrics } from './AppMetricsModels';
import { ExpoAppMetricsError } from './ExpoAppMetricsError';
import { retentionCutoffTimestamp } from './AppMetricsSemantics';
import { copyEntry, decodeEntry } from './AppMetricsStorageCodec';

const PREFERENCES_NAME: string = 'dev.expo.app-metrics';
const SESSIONS_KEY: string = 'sessions';
const PENDING_SESSIONS_KEY: string = 'sessions.pending';
const DEFAULT_DEBUG_ENVIRONMENT: string = 'development';
// Preferences values are limited to 16 MiB. The code-unit bound remains below
// that limit even when every UTF-16 code unit expands to four UTF-8 bytes.
const MAX_PREFERENCES_PAYLOAD_CODE_UNITS: number = 3_500_000;

let processStorage: AppMetricsStorage | undefined = undefined;

export function appMetricsStorage(context: common.UIAbilityContext): AppMetricsStorage {
  if (processStorage === undefined) {
    processStorage = new AppMetricsStorage(context, context.applicationInfo.debug);
  }

  return processStorage;
}

export class AppMetricsStorage {
  private readonly store: Promise<preferences.Preferences | null>;
  private readonly ready: Promise<void>;
  private sessions: SessionWithMetrics[] = [];
  private environment?: string;
  private failure?: ExpoAppMetricsError;
  private queue: Promise<void> = Promise.resolve();

  constructor(context: common.UIAbilityContext, debug: boolean) {
    this.environment = debug ? DEFAULT_DEBUG_ENVIRONMENT : undefined;
    let store: Promise<preferences.Preferences | null>;
    try {
      store = preferences.getPreferences(context, { name: PREFERENCES_NAME });
    } catch (error) {
      this.failure = new ExpoAppMetricsError('ERR_APP_METRICS_STORAGE', `Unable to open Expo App Metrics preferences: ${String(error)}`);
      console.warn(this.failure.message);
      store = Promise.resolve(null);
    }
    this.store = store.catch((error: Object): preferences.Preferences | null => {
      this.failure = new ExpoAppMetricsError('ERR_APP_METRICS_STORAGE', `Unable to open Expo App Metrics preferences: ${String(error)}`);
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
        throw new ExpoAppMetricsError('ERR_APP_METRICS_SESSION_NOT_FOUND', `No app metrics session exists for '${sessionId}'.`);
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
      const active = this.sessions
        .filter((entry: SessionWithMetrics): boolean => entry.session.isActive)
        .map((entry: SessionWithMetrics): SessionWithMetrics => {
          const copy = copyEntry(entry);
          copy.metrics = [];
          return copy;
        });
      await this.persistEntries(active);

      this.sessions = active;
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

          if (error instanceof ExpoAppMetricsError) {
            throw new ExpoAppMetricsError(error.code, error.message);
          }
          const message = `Unable to update Expo App Metrics preferences: ${String(error)}`;

          throw new ExpoAppMetricsError('ERR_APP_METRICS_STORAGE', message);
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
      throw new ExpoAppMetricsError(this.failure.code, this.failure.message);
    }
  }

  private async load(): Promise<void> {
    const store = await this.store;
    if (store === null) return;

    try {
      const primary = await store.get(SESSIONS_KEY, '');
      const pending = await store.get(PENDING_SESSIONS_KEY, '');
      if (typeof primary !== 'string' || typeof pending !== 'string') {
        this.failure = new ExpoAppMetricsError(
          'ERR_APP_METRICS_STORAGE',
          'Unable to decode Expo App Metrics preferences: Stored sessions are not a JSON string.',
        );
        console.warn(this.failure.message);

        return;
      }
      let recovering = pending.length > 0;
      let raw = recovering ? pending : primary;
      if (raw.length === 0) return;

      let decoded: ESObject;
      try {
        decoded = JSON.parse(raw) as ESObject;
      } catch (error) {
        if (!recovering || primary.length === 0) {
          throw new ExpoAppMetricsError('ERR_APP_METRICS_STORAGE', `Unable to decode Expo App Metrics preferences: ${String(error)}`);
        }

        console.warn(`Ignoring an invalid Expo App Metrics recovery record: ${String(error)}`);
        raw = primary;
        recovering = false;
        decoded = JSON.parse(raw) as ESObject;
        try {
          await store.delete(PENDING_SESSIONS_KEY);
          await store.flush();
        } catch (cleanupError) {
          console.warn(`Unable to remove an invalid Expo App Metrics recovery record: ${String(cleanupError)}`);
        }
      }
      if (!Array.isArray(decoded) && recovering && primary.length > 0) {
        console.warn('Ignoring an invalid Expo App Metrics recovery record: Stored sessions are not a JSON array.');
        recovering = false;
        decoded = JSON.parse(primary) as ESObject;
        try {
          await store.delete(PENDING_SESSIONS_KEY);
          await store.flush();
        } catch (cleanupError) {
          console.warn(`Unable to remove an invalid Expo App Metrics recovery record: ${String(cleanupError)}`);
        }
      }
      if (!Array.isArray(decoded)) {
        this.failure = new ExpoAppMetricsError(
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
        error instanceof ExpoAppMetricsError
          ? new ExpoAppMetricsError(error.code, error.message)
          : new ExpoAppMetricsError('ERR_APP_METRICS_STORAGE', `Unable to read Expo App Metrics preferences: ${String(error)}`);
      console.warn(this.failure.message);
    }
  }

  private async persist(): Promise<void> {
    const cutoff = retentionCutoffTimestamp(Date.now());
    const sessions = this.sessions
      .map((entry: SessionWithMetrics): SessionWithMetrics => {
        const copy = copyEntry(entry);
        copy.metrics = copy.metrics.filter((metric: Metric): boolean => Date.parse(metric.timestamp) >= cutoff);
        return copy;
      })
      .filter((entry: SessionWithMetrics): boolean => entry.session.isActive || entry.metrics.length > 0);

    let payload = JSON.stringify(sessions);
    while (payload.length > MAX_PREFERENCES_PAYLOAD_CODE_UNITS) {
      const removable = sessions.findIndex((entry: SessionWithMetrics): boolean => !entry.session.isActive);
      if (removable < 0) {
        throw new ExpoAppMetricsError(
          'ERR_APP_METRICS_STORAGE_CAPACITY',
          'Active Expo App Metrics sessions exceed the safe Harmony Preferences capacity.',
        );
      }

      sessions.splice(removable, 1);
      payload = JSON.stringify(sessions);
    }

    await this.persistEntries(sessions, payload);
    this.sessions = sessions;
  }

  private async persistEntries(sessions: SessionWithMetrics[], encoded?: string): Promise<void> {
    const store = await this.store;
    if (store === null) {
      throw new ExpoAppMetricsError(
        this.failure?.code ?? 'ERR_APP_METRICS_STORAGE',
        this.failure?.message ?? 'Unable to open Expo App Metrics preferences: Preferences are unavailable.',
      );
    }

    try {
      const payload = encoded ?? JSON.stringify(sessions);

      await store.put(PENDING_SESSIONS_KEY, payload);
      await store.flush();

      await store.put(SESSIONS_KEY, payload);
      await store.flush();
    } catch (error) {
      throw new ExpoAppMetricsError('ERR_APP_METRICS_STORAGE', `Unable to persist Expo App Metrics sessions: ${String(error)}`);
    }

    try {
      await store.delete(PENDING_SESSIONS_KEY);
      await store.flush();
    } catch (error) {
      console.warn(`Unable to remove the committed Expo App Metrics recovery record: ${String(error)}`);
    }
  }
}
