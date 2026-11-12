/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type common from '@ohos.app.ability.common';
import util from '@ohos.util';
import { preferences } from '@kit.ArkData';
import { CrashReport, copyCrashReport, nativeCrashLog } from './AppMetricsCrashReport';
import { AppMetadata, LogRecord, Metric, Session, SessionWithMetrics } from './AppMetricsModels';
import { ExpoAppMetricsError } from './ExpoAppMetricsError';
import { retentionCutoffTimestamp } from './AppMetricsSemantics';
import { mergeAttributes } from './AppMetricsLogging';
import { copyEntry, copyLogRecord, copyMetric, decodeEntry, decodeStoredMetricsPayload, MetricsStoragePayload } from './AppMetricsStorageCodec';

const PREFERENCES_NAME: string = 'dev.expo.app-metrics';
const SESSIONS_KEY: string = 'sessions';
const PENDING_SESSIONS_KEY: string = 'sessions.pending';
const DEFAULT_DEBUG_ENVIRONMENT: string = 'development';
// Bound UTF-16 code units so encoded JSON stays below the Preferences 16 MiB limit.
const MAX_PREFERENCES_PAYLOAD_CODE_UNITS: number = 3_500_000;

let processStorage: AppMetricsStorage | undefined = undefined;

export function appMetricsStorage(context: common.Context): AppMetricsStorage {
  if (processStorage === undefined) {
    processStorage = new AppMetricsStorage(context, context.applicationInfo.debug);
  }

  return processStorage;
}

export class AppMetricsStorage {
  private readonly store: Promise<preferences.Preferences | null>;
  private readonly ready: Promise<void>;
  private sessions: SessionWithMetrics[] = [];
  private crashReports: CrashReport[] = [];
  private readonly clearedSessions: Set<string> = new Set<string>();
  private environment?: string;
  private failure?: ExpoAppMetricsError;
  private queue: Promise<void> = Promise.resolve();
  private globalAttributes?: Record<string, ESObject>;

  constructor(context: common.Context, debug: boolean) {
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

  scheduleStartSession(sessionId: string, timestamp: string, metadata: Promise<AppMetadata>, type: string = 'custom'): void {
    this.schedule(async (): Promise<void> => {
      if (this.findSession(sessionId) !== undefined) return;

      const info = await metadata;
      const session = new Session(sessionId, timestamp, this.environment, info);
      session.type = type;

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
      entry.session.endTimestamp = new Date().toISOString();

      await this.persist();
    });
  }

  scheduleStartupSession(sessionId: string, timestamp: string, metrics: Metric[], metadata: Promise<AppMetadata>): Promise<void> {
    return this.runMutation(async (): Promise<void> => {
      if (this.clearedSessions.has(sessionId)) throw new ExpoAppMetricsError('ERR_APP_METRICS_SESSION_NOT_FOUND', 'This session was cleared.');

      let entry = this.findSession(sessionId);
      if (entry === undefined) {
        const info = await metadata;
        const session = new Session(sessionId, timestamp, this.environment, info);

        session.type = 'main';
        entry = new SessionWithMetrics(session);

        this.sessions.push(entry);
      }

      const target: SessionWithMetrics = entry;

      target.session.startTimestamp = timestamp;

      const ids = new Set<string>(target.metrics.map((metric: Metric): string => metric.metricId));

      metrics.forEach((metric: Metric): void => {
        if (ids.has(metric.metricId)) return;

        const copy = copyMetric(metric);
        copy.params = this.mergeGlobals(copy.params);
        target.metrics.push(copy);
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

      metrics.forEach((metric: Metric): void => {
        const copy = copyMetric(metric);
        copy.params = this.mergeGlobals(copy.params);
        entry.metrics.push(copy);
      });

      await this.persist();
    });
  }

  async getAllSessions(): Promise<SessionWithMetrics[]> {
    await this.ready;
    await this.queue;

    this.assertStorageAvailable();

    return this.sessions.map((entry: SessionWithMetrics): SessionWithMetrics => {
      const copy = copyEntry(entry);
      const report = this.crashReports.find((report: CrashReport): boolean => report.sessionId === entry.session.id);
      if (report !== undefined) copy.crashReport = copyCrashReport(report);
      return copy;
    });
  }

  async getSession(id: string): Promise<SessionWithMetrics | undefined> {
    await this.ready;
    await this.queue;
    this.assertStorageAvailable();

    const entry = this.findSession(id);

    return entry === undefined ? undefined : copyEntry(entry);
  }

  async patchUpdatesMetadata(metadata: AppMetadata): Promise<void> {
    await this.runMutation(async (): Promise<void> => {
      let changed = false;
      this.sessions.forEach((entry: SessionWithMetrics): void => {
        const session = entry.session;
        if (!session.isActive || session.appUpdateId !== undefined
          || (metadata.appUpdateId === undefined && session.appUpdateRuntimeVersion === metadata.appUpdateRuntimeVersion)) return;
        session.appUpdateId = metadata.appUpdateId;
        session.appUpdateRuntimeVersion = metadata.appUpdateRuntimeVersion;
        session.appUpdateRequestHeaders = metadata.appUpdateRequestHeaders;
        changed = true;
      });
      if (changed) await this.persist();
    });
  }

  async clear(): Promise<void> {
    await this.runMutation(async (): Promise<void> => {
      const ids = this.sessions.map((entry: SessionWithMetrics): string => entry.session.id);
      this.crashReports = [];
      await this.persistEntries([]);
      ids.forEach((id: string): void => { this.clearedSessions.add(id); });
      this.sessions = [];
      this.failure = undefined;
    }, true);
  }

  setGlobalAttributes(attributes?: Record<string, ESObject>): void {
    this.globalAttributes = attributes;
  }

  mergeGlobals(attributes?: Record<string, ESObject>): Record<string, ESObject> | undefined {
    if (this.globalAttributes === undefined && attributes === undefined) return undefined;
    return JSON.parse(JSON.stringify(mergeAttributes(this.globalAttributes, attributes))) as Record<string, ESObject>;
  }

  async addLogs(sessionId: string, logs: LogRecord[], mergeGlobalAttributes: boolean = true): Promise<void> {
    await this.runMutation(async (): Promise<void> => {
      const entry = this.findSession(sessionId);
      if (entry === undefined) throw new ExpoAppMetricsError('ERR_APP_METRICS_SESSION_NOT_FOUND', 'The owning metrics session no longer exists.');

      logs.forEach((log: LogRecord): void => {
        if (log.recordId !== undefined && entry.logs.some((stored: LogRecord): boolean => stored.recordId === log.recordId)) return;
        const copy = copyLogRecord(log);
        if (mergeGlobalAttributes) copy.attributes = this.mergeGlobals(copy.attributes);
        entry.logs.push(copy);
      });

      await this.persist();
    });
  }

  async getAllCrashReports(): Promise<CrashReport[]> {
    await this.ready;
    await this.queue;
    this.assertStorageAvailable();

    return this.crashReports.slice().sort((a: CrashReport, b: CrashReport): number => Date.parse(b.ingestedAt) - Date.parse(a.ingestedAt))
      .map((report: CrashReport): CrashReport => copyCrashReport(report));
  }

  async addCrashReport(report: CrashReport, requestedSessionId?: string): Promise<void> {
    await this.runMutation(async (): Promise<void> => {
      if (this.crashReports.some((stored: CrashReport): boolean => stored.eventId === report.eventId)) return;

      const attributed = requestedSessionId !== undefined
        && this.crashReports.some((stored: CrashReport): boolean => stored.sessionId === requestedSessionId);
      const entry = requestedSessionId === undefined || attributed ? undefined : this.findSession(requestedSessionId);
      // Only a system-stamped session ID is trusted; timestamps are not enough to guess attribution.
      report.sessionId = entry?.session.id ?? null;
      if (entry !== undefined) {
        entry.session.isActive = false;
        entry.session.endTimestamp = report.timestampBegin;
        const log = nativeCrashLog(report);
        log.attributes = this.mergeGlobals(log.attributes);
        entry.logs.push(log);
      }
      this.crashReports.push(copyCrashReport(report));

      await this.persist();
    });
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

        const crashSnapshot = this.crashReports.map((report: CrashReport): CrashReport => copyCrashReport(report));
        const snapshot = this.sessions.map((entry: SessionWithMetrics): SessionWithMetrics => copyEntry(entry));

        try {
          await task();
        } catch (error) {
          this.sessions = snapshot;
          this.crashReports = crashSnapshot;

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
      const raw = recovering ? pending : primary;
      if (raw.length === 0) return;

      let decoded: MetricsStoragePayload | undefined;
      try { decoded = decodeStoredMetricsPayload(JSON.parse(raw) as ESObject); } catch (_) {}
      if (decoded === undefined && recovering && primary.length > 0) {
        console.warn('Ignoring an invalid Expo App Metrics recovery record.');
        recovering = false;
        decoded = decodeStoredMetricsPayload(JSON.parse(primary) as ESObject);
        try {
          await store.delete(PENDING_SESSIONS_KEY);
          await store.flush();
        } catch (error) {
          console.warn(`Unable to remove an invalid Expo App Metrics recovery record: ${String(error)}`);
        }
      }
      if (decoded === undefined) throw new Error('Stored metrics are not a valid sessions payload.');
      this.crashReports = decoded.crashReports;

      const sessions: SessionWithMetrics[] = [];
      const sessionIds = new Set<string>();
      const metricIds = new Set<string>();
      let changed = recovering;

      decoded.sessions.forEach((value: ESObject): void => {
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
          // The process died without a final callback; do not invent its end time.
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

        copy.logs = copy.logs.filter((log: LogRecord): boolean => Date.parse(log.timestamp) >= cutoff);

        return copy;
      })
      .filter((entry: SessionWithMetrics): boolean => entry.session.isActive || Date.parse(entry.session.startTimestamp) >= cutoff);

    const ids = new Set<string>(sessions.map((entry: SessionWithMetrics): string => entry.session.id));
    // Match SDK 57's crash-report FK lifecycle: an attributed report lives exactly
    // as long as its owning session; an orphan is retained from ingestion, not crash time.
    this.crashReports = this.crashReports.filter((report: CrashReport): boolean => report.sessionId === null
      ? Date.parse(report.ingestedAt) >= cutoff : ids.has(report.sessionId));

    let payload = this.encodePayload(sessions);

    while (payload.length > MAX_PREFERENCES_PAYLOAD_CODE_UNITS) {
      let removable = -1;
      sessions.forEach((entry: SessionWithMetrics, index: number): void => {
        if (!entry.session.isActive && (removable < 0
          || Date.parse(entry.session.startTimestamp) < Date.parse(sessions[removable].session.startTimestamp))) removable = index;
      });
      if (removable < 0) {
        // Associated reports are never evicted independently of their sessions.
        // Once only active sessions remain, reclaim the oldest ingested orphan.
        let orphanIndex = -1;
        this.crashReports.forEach((report: CrashReport, index: number): void => {
          if (report.sessionId === null && (orphanIndex < 0
            || Date.parse(report.ingestedAt) < Date.parse(this.crashReports[orphanIndex].ingestedAt))) orphanIndex = index;
        });
        if (orphanIndex < 0) {
          throw new ExpoAppMetricsError(
            'ERR_APP_METRICS_STORAGE_CAPACITY',
            'Active Expo App Metrics sessions exceed the safe Harmony Preferences capacity.',
          );
        }
        this.crashReports.splice(orphanIndex, 1);
        payload = this.encodePayload(sessions);
        continue;
      }

      const removed = sessions.splice(removable, 1)[0];
      this.crashReports = this.crashReports.filter((report: CrashReport): boolean => report.sessionId !== removed.session.id);
      payload = this.encodePayload(sessions);
    }

    await this.persistEntries(sessions, payload);
    this.sessions = sessions;
  }

  private encodePayload(sessions: SessionWithMetrics[]): string {
    return JSON.stringify({ sessions, crashReports: this.crashReports });
  }

  private async persistEntries(sessions: SessionWithMetrics[], encoded?: string): Promise<void> {
    const store = await this.store;
    if (store === null) {
      throw new ExpoAppMetricsError(
        this.failure?.code ?? 'ERR_APP_METRICS_STORAGE',
        this.failure?.message ?? 'Unable to open Expo App Metrics preferences: Preferences are unavailable.',
      );
    }

    const payload = encoded ?? this.encodePayload(sessions);
    const previous = await store.get(PENDING_SESSIONS_KEY, '');
    try {
      await store.put(PENDING_SESSIONS_KEY, payload);
      await store.flush();
    } catch (error) {
      try {
        if (previous === '') await store.delete(PENDING_SESSIONS_KEY);
        else await store.put(PENDING_SESSIONS_KEY, previous);
        await store.flush();
      } catch (rollbackError) {
        console.warn(`Unable to restore the Expo App Metrics recovery record: ${String(rollbackError)}`);
      }
      throw new ExpoAppMetricsError('ERR_APP_METRICS_STORAGE', `Unable to persist Expo App Metrics sessions: ${String(error)}`);
    }

    // Recovery treats the flushed pending record as authoritative. A later
    // promotion failure cannot turn a durable write into a rejected mutation.
    try {
      await store.put(SESSIONS_KEY, payload);
      await store.flush();
    } catch (error) {
      console.warn(`Unable to promote the committed Expo App Metrics recovery record: ${String(error)}`);
      return;
    }

    try {
      await store.delete(PENDING_SESSIONS_KEY);
      await store.flush();
    } catch (error) {
      console.warn(`Unable to remove the committed Expo App Metrics recovery record: ${String(error)}`);
    }
  }
}
