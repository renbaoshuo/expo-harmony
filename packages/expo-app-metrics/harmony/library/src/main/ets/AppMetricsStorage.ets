/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { preferences, relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { CrashReport, decodeCrashReport, nativeCrashLog } from './AppMetricsCrashReport';
import { AppMetadata, LogRecord, Metric, Session, SessionWithMetrics } from './AppMetricsModels';
import { ExpoAppMetricsError } from './ExpoAppMetricsError';
import { retentionCutoffTimestamp } from './AppMetricsSemantics';
import { mergeAttributes } from './AppMetricsLogging';
import { copyLogRecord, copyMetric, decodeEntry, decodeLogRecord, decodeMetric, decodeSession,
  decodeStoredMetricsPayload, MetricsStoragePayload } from './AppMetricsStorageCodec';

const LEGACY_PREFERENCES = 'dev.expo.app-metrics';
const LEGACY_SESSIONS = 'sessions';
const LEGACY_PENDING_SESSIONS = 'sessions.pending';
// API 13 ResultSet limits each row to 2 MiB, but legacy payloads can be larger.
const PAYLOAD_CHUNK_SIZE = 1024 * 1024;

type MetricsTable = 'sessions' | 'metrics' | 'logs' | 'crash_reports';

const SCHEMA: string[] = [
  'CREATE TABLE IF NOT EXISTS metrics_state (key TEXT PRIMARY KEY)',
  'CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, started INTEGER NOT NULL, active INTEGER NOT NULL, payload BLOB NOT NULL)',
  'CREATE INDEX IF NOT EXISTS sessions_retention ON sessions(active, started)',
  'CREATE TABLE IF NOT EXISTS metrics (id TEXT NOT NULL UNIQUE, session_id TEXT NOT NULL, payload BLOB NOT NULL)',
  'CREATE INDEX IF NOT EXISTS metrics_session ON metrics(session_id)',
  'CREATE TABLE IF NOT EXISTS logs (id TEXT NOT NULL, session_id TEXT NOT NULL, time INTEGER NOT NULL, payload BLOB NOT NULL, UNIQUE(session_id, id))',
  'CREATE INDEX IF NOT EXISTS logs_retention ON logs(time)',
  'CREATE TABLE IF NOT EXISTS crash_reports (id TEXT PRIMARY KEY, session_id TEXT UNIQUE, ingested INTEGER NOT NULL, payload BLOB NOT NULL)',
  'CREATE INDEX IF NOT EXISTS crashes_retention ON crash_reports(session_id, ingested)',
];

let processStorage: AppMetricsStorage | undefined;

export function appMetricsStorage(context: common.Context): AppMetricsStorage {
  if (processStorage === undefined) processStorage = new AppMetricsStorage(context);
  return processStorage;
}

export class AppMetricsStorage {
  private readonly store: Promise<relationalStore.RdbStore | undefined>;
  private readonly clearedSessions: Set<string> = new Set<string>();
  private readonly environment?: string;
  private failure?: ExpoAppMetricsError;
  private queue: Promise<void> = Promise.resolve();
  private globalAttributes?: Record<string, ESObject>;

  constructor(context: common.Context) {
    this.environment = context.applicationInfo.debug ? 'development' : undefined;

    this.store = this.open(context).catch((error: Object): undefined => {
      this.failure = new ExpoAppMetricsStorageError(error);
      console.warn(this.failure.message);
      return undefined;
    });
  }

  createSessionId(): string {
    return util.generateRandomUUID(true);
  }

  scheduleStartSession(id: string, timestamp: string, metadata: Promise<AppMetadata>, type: string = 'custom'): void {
    this.schedule(this.run(async (store: relationalStore.RdbStore): Promise<void> => {
      const session = new Session(id, timestamp, this.environment, await metadata);
      session.type = type;

      await store.executeSql(
        'INSERT OR IGNORE INTO sessions (id, started, active, payload) VALUES (?, ?, 1, ?)',
        [id, Date.parse(timestamp), encodePayload(session)],
      );
    }));
  }

  scheduleStopSession(id: string): void {
    this.schedule(this.stopSession(id));
  }

  stopSession(id: string): Promise<void> {
    return this.run(async (store: relationalStore.RdbStore): Promise<void> => {
      const session = await readSession(store, id);
      if (session === undefined || !session.isActive) return;

      session.isActive = false;
      session.endTimestamp = new Date().toISOString();

      await this.transaction(store, async (): Promise<void> => {
        await putSession(store, session);
        await prune(store);
      });
    });
  }

  scheduleStartupSession(id: string, timestamp: string, metrics: Metric[], metadata: Promise<AppMetadata>): Promise<void> {
    return this.run(async (store: relationalStore.RdbStore): Promise<void> => {
      if (this.clearedSessions.has(id)) {
        throw new ExpoAppMetricsError('ERR_APP_METRICS_SESSION_NOT_FOUND', `No app metrics session exists for '${id}'.`);
      }

      const saved = await readSession(store, id);
      const session = saved ?? new Session(id, timestamp, this.environment, await metadata);
      session.type = 'main';

      await this.transaction(store, async (): Promise<void> => {
        if (saved === undefined || saved.startTimestamp !== timestamp) {
          session.startTimestamp = timestamp;
          await putSession(store, session);
        }

        for (const metric of metrics) await putMetric(store, metric);
      });
    });
  }

  addMetrics(id: string, metrics: Metric[]): Promise<void> {
    const entries = metrics.map((metric: Metric): Metric => this.metricWithGlobals(metric));

    return this.run(async (store: relationalStore.RdbStore): Promise<void> => {
      await requireSession(store, id);

      await this.transaction(store, async (): Promise<void> => {
        for (const metric of entries) await putMetric(store, metric);
      });
    });
  }

  getSessionRecord(id: string): Promise<Session | undefined> {
    return this.run((store: relationalStore.RdbStore): Promise<Session | undefined> => readSession(store, id));
  }

  getMetrics(id?: string): Promise<Metric[]> {
    return this.run((store: relationalStore.RdbStore): Promise<Metric[]> => readMetrics(store, id));
  }

  getLogs(id: string): Promise<LogRecord[]> {
    return this.run(async (store: relationalStore.RdbStore): Promise<LogRecord[]> => {
      return query(store, 'logs', 'WHERE session_id = ? ORDER BY rowid', [id], decodeLogRecord);
    });
  }

  getInactiveSessions(): Promise<SessionWithMetrics[]> {
    return this.run(async (store: relationalStore.RdbStore): Promise<SessionWithMetrics[]> => {
      const sessions = await query(store, 'sessions', 'WHERE active = 0 ORDER BY started DESC', [], decodeSession);
      const entries = new Map<string, SessionWithMetrics>();
      sessions.forEach((session: Session): void => { entries.set(session.id, new SessionWithMetrics(session)); });
      if (entries.size === 0) return [];

      const inactive = 'SELECT id FROM sessions WHERE active = 0';
      const metrics = await query(store, 'metrics', `WHERE session_id IN (${inactive}) ORDER BY rowid`, [], decodeMetric);
      metrics.forEach((metric: Metric): void => { entries.get(metric.sessionId)?.metrics.push(metric); });
      await query(store, 'logs', `WHERE session_id IN (${inactive}) ORDER BY rowid`, [], (value: ESObject, owner?: string): undefined => {
        const log = decodeLogRecord(value);
        if (log !== undefined && owner !== undefined) entries.get(owner)?.logs.push(log);
        return undefined;
      });
      const reports = await query(store, 'crash_reports', `WHERE session_id IN (${inactive})`, [], decodeCrashReport);
      reports.forEach((report: CrashReport): void => {
        if (report.sessionId === null) return;
        const entry = entries.get(report.sessionId);
        if (entry !== undefined) entry.crashReport = report;
      });

      return Array.from(entries.values());
    });
  }

  patchUpdatesMetadata(metadata: AppMetadata): Promise<void> {
    return this.run(async (store: relationalStore.RdbStore): Promise<void> => {
      const sessions = await query(store, 'sessions', 'WHERE active = 1', [], decodeSession);

      await this.transaction(store, async (): Promise<void> => {
        for (const session of sessions) {
          if (session.appUpdateId !== undefined
            || (metadata.appUpdateId === undefined && session.appUpdateRuntimeVersion === metadata.appUpdateRuntimeVersion)) continue;
          session.appUpdateId = metadata.appUpdateId;
          session.appUpdateRuntimeVersion = metadata.appUpdateRuntimeVersion;
          session.appUpdateRequestHeaders = metadata.appUpdateRequestHeaders;
          await putSession(store, session);
        }
      });
    });
  }

  clear(): Promise<void> {
    return this.run(async (store: relationalStore.RdbStore): Promise<void> => {
      const sessions = await query(store, 'sessions', 'WHERE active = 1', [], decodeSession);

      await this.transaction(store, async (): Promise<void> => {
        await store.executeSql('DELETE FROM crash_reports');
        await store.executeSql('DELETE FROM logs');
        await store.executeSql('DELETE FROM metrics');
        await store.executeSql('DELETE FROM sessions');
      });

      sessions.forEach((session: Session): void => { this.clearedSessions.add(session.id); });
    });
  }

  setGlobalAttributes(attributes?: Record<string, ESObject>): void {
    this.globalAttributes = attributes;
  }

  mergeGlobals(attributes?: Record<string, ESObject>): Record<string, ESObject> | undefined {
    if (this.globalAttributes === undefined && attributes === undefined) return undefined;
    return mergeAttributes(this.globalAttributes, attributes);
  }

  addLogs(id: string, logs: LogRecord[], mergeGlobals: boolean = true): Promise<void> {
    const entries = logs.map((log: LogRecord): LogRecord => {
      const entry = copyLogRecord(log);
      if (mergeGlobals) entry.attributes = this.mergeGlobals(entry.attributes);
      return entry;
    });

    return this.run(async (store: relationalStore.RdbStore): Promise<void> => {
      await requireSession(store, id);

      await this.transaction(store, async (): Promise<void> => {
        for (const entry of entries) await putLog(store, id, entry, this.createSessionId());
        await store.executeSql('DELETE FROM logs WHERE time < ?', [retentionCutoffTimestamp(Date.now())]);
      });
    });
  }

  getAllCrashReports(): Promise<CrashReport[]> {
    return this.run((store: relationalStore.RdbStore): Promise<CrashReport[]> =>
      query(store, 'crash_reports', 'ORDER BY ingested DESC', [], decodeCrashReport));
  }

  addCrashReport(report: CrashReport, requestedSessionId?: string): Promise<void> {
    return this.run(async (store: relationalStore.RdbStore): Promise<void> => {
      const duplicate = await query(store, 'crash_reports', 'WHERE id = ? OR session_id = ?',
        [report.eventId, requestedSessionId ?? null], decodeCrashReport);
      if (duplicate.some((existing: CrashReport): boolean => existing.eventId === report.eventId)) return;

      // A timestamp cannot establish which session owned the fault.
      const session = requestedSessionId === undefined || duplicate.length > 0 ? undefined : await readSession(store, requestedSessionId);
      report.sessionId = session?.id ?? null;

      await this.transaction(store, async (): Promise<void> => {
        if (session !== undefined) {
          session.isActive = false;
          session.endTimestamp = report.timestampBegin;
          await putSession(store, session);
          const log = nativeCrashLog(report);
          log.attributes = this.mergeGlobals(log.attributes);
          await putLog(store, session.id, log, this.createSessionId());
        }
        await putCrashReport(store, report);
        await prune(store);
      });
    });
  }

  metricWithGlobals(metric: Metric): Metric {
    const copy = copyMetric(metric);
    copy.params = this.mergeGlobals(copy.params);

    return copy;
  }

  private schedule(work: Promise<void>): void {
    work.catch((error: Object): void => console.warn(`Unable to update Expo App Metrics storage: ${String(error)}`));
  }

  private run<T>(work: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    const result = this.queue.then(async (): Promise<T> => {
      const store = await this.store;
      if (store === undefined) throw new ExpoAppMetricsStorageError(this.failure);

      try {
        return await work(store);
      } catch (error) {
        throw new ExpoAppMetricsStorageError(error);
      }
    });

    this.queue = result.then((): void => {}, (): void => {});
    return result;
  }

  private async transaction(store: relationalStore.RdbStore, work: () => Promise<void>): Promise<void> {
    let committed = false;
    store.beginTransaction();

    try {
      await work();
      store.commit();
      committed = true;
    } finally {
      if (!committed) {
        try {
          store.rollBack();
        } catch (error) {
          console.warn(`Unable to roll back Expo App Metrics transaction: ${String(error)}`);
        }
      }
    }
  }

  private async open(context: common.Context): Promise<relationalStore.RdbStore> {
    const store = await relationalStore.getRdbStore(context, {
      name: 'expo-app-metrics.db',
      securityLevel: relationalStore.SecurityLevel.S1,
    });
    for (const statement of SCHEMA) await store.executeSql(statement);

    await this.migratePreferences(store, context);
    await this.transaction(store, async (): Promise<void> => {
      const sessions = await query(store, 'sessions', 'WHERE active = 1', [], decodeSession);
      for (const session of sessions) {
        // No shutdown callback ran in the previous process, so its end time is unknown.
        session.isActive = false;
        await putSession(store, session);
      }
      await prune(store);
    });

    return store;
  }

  private async migratePreferences(store: relationalStore.RdbStore, context: common.Context): Promise<void> {
    const marker = await store.querySql("SELECT 1 FROM metrics_state WHERE key = 'preferences_migrated'");
    const migrated = marker.goToFirstRow();
    marker.close();
    if (migrated) return;

    const legacy = await preferences.getPreferences(context, { name: LEGACY_PREFERENCES });
    const pending = await legacy.get(LEGACY_PENDING_SESSIONS, '');
    const primary = await legacy.get(LEGACY_SESSIONS, '');
    const payload = legacyPayload(pending) ?? legacyPayload(primary);

    await this.transaction(store, async (): Promise<void> => {
      const ids = new Set<string>();
      const sessions: ESObject[] = payload?.sessions ?? [];
      for (let index = 0; index < sessions.length; index += 1) {
        const entry = decodeEntry(sessions[index]);
        if (entry === undefined || !Number.isFinite(Date.parse(entry.session.startTimestamp)) || ids.has(entry.session.id)) continue;
        ids.add(entry.session.id);
        await putSession(store, entry.session);
        for (const metric of entry.metrics) {
          if (Number.isFinite(Date.parse(metric.timestamp))) await putMetric(store, metric);
        }
        for (const log of entry.logs) await putLog(store, entry.session.id, log, this.createSessionId());
      }

      for (const report of payload?.crashReports ?? []) {
        if (report.sessionId !== null && !ids.has(report.sessionId)) report.sessionId = null;
        await putCrashReport(store, report);
      }
      await store.executeSql("INSERT INTO metrics_state (key) VALUES ('preferences_migrated')");
    });

    try {
      await legacy.delete(LEGACY_SESSIONS);
      await legacy.delete(LEGACY_PENDING_SESSIONS);
      await legacy.flush();
    } catch (error) {
      console.warn(`Unable to delete migrated Expo App Metrics preferences: ${String(error)}`);
    }
  }
}

function legacyPayload(input: preferences.ValueType): MetricsStoragePayload | undefined {
  if (typeof input !== 'string' || input.length === 0) return undefined;
  try {
    const payload = decodeStoredMetricsPayload(JSON.parse(input) as ESObject);
    if (payload !== undefined) return payload;
  } catch (_) {}
  console.warn('Ignoring an invalid legacy Expo App Metrics record.');
  return undefined;
}

class ExpoAppMetricsStorageError extends ExpoAppMetricsError {
  constructor(error: Object | undefined) {
    let code: string;
    let message: string;
    if (error instanceof ExpoAppMetricsError) {
      code = error.code;
      message = error.message;
    } else if ((error as BusinessError | undefined)?.code === 14800031) {
      code = 'ERR_APP_METRICS_STORAGE_CAPACITY';
      message = 'An Expo App Metrics record exceeds the database value size limit.';
    } else {
      code = 'ERR_APP_METRICS_STORAGE';
      message = `Unable to access the Expo App Metrics database: ${String(error)}`;
    }

    super(code, message);
  }
}

class StoredPayload {
  readonly rowId: number;
  readonly size: number;
  readonly firstChunk: Uint8Array;
  readonly owner?: string;

  constructor(rowId: number, size: number, firstChunk: Uint8Array, owner?: string) {
    this.rowId = rowId;
    this.size = size;
    this.firstChunk = firstChunk;
    this.owner = owner;
  }
}

function encodePayload(value: Object): Uint8Array {
  return new util.TextEncoder().encodeInto(JSON.stringify(value));
}

async function query<T>(
  store: relationalStore.RdbStore,
  table: MetricsTable,
  clauses: string,
  args: relationalStore.ValueType[],
  decode: (input: ESObject, owner?: string) => T | undefined,
): Promise<T[]> {
  const owner = table === 'logs' ? ', session_id' : '';
  const rows = await store.querySql(
    `SELECT rowid, length(payload), substr(payload, 1, ?)${owner} FROM ${table} ${clauses}`,
    [PAYLOAD_CHUNK_SIZE, ...args],
  );
  const payloads: StoredPayload[] = [];
  try {
    while (rows.goToNextRow()) {
      payloads.push(new StoredPayload(rows.getLong(0), rows.getLong(1), rows.getBlob(2),
        table === 'logs' ? rows.getString(3) : undefined));
    }
  } finally {
    rows.close();
  }

  const decoder = new util.TextDecoder('utf-8', { fatal: true });
  const result: T[] = [];
  for (const payload of payloads) {
    let bytes = payload.firstChunk;
    if (payload.size > bytes.byteLength) {
      bytes = await readLargePayload(store, table, payload);
    }

    const value = decode(JSON.parse(decoder.decodeToString(bytes)) as ESObject, payload.owner);
    if (value !== undefined) result.push(value);
  }

  return result;
}

async function readLargePayload(store: relationalStore.RdbStore, table: MetricsTable, payload: StoredPayload): Promise<Uint8Array> {
  const bytes = new Uint8Array(payload.size);
  bytes.set(payload.firstChunk);

  for (let offset = payload.firstChunk.byteLength; offset < bytes.byteLength;) {
    const rows = await store.querySql(`SELECT substr(payload, ?, ?) FROM ${table} WHERE rowid = ?`,
      [offset + 1, PAYLOAD_CHUNK_SIZE, payload.rowId]);
    try {
      if (!rows.goToNextRow()) throw new Error('An Expo App Metrics record disappeared during a read.');

      const chunk = rows.getBlob(0);
      if (chunk.byteLength === 0) throw new Error('An Expo App Metrics record ended before its declared length.');

      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    } finally {
      rows.close();
    }
  }

  return bytes;
}

async function readSession(store: relationalStore.RdbStore, id: string): Promise<Session | undefined> {
  return (await query(store, 'sessions', 'WHERE id = ?', [id], decodeSession))[0];
}

async function requireSession(store: relationalStore.RdbStore, id: string): Promise<void> {
  if (await readSession(store, id) === undefined) {
    throw new ExpoAppMetricsError('ERR_APP_METRICS_SESSION_NOT_FOUND', `No app metrics session exists for '${id}'.`);
  }
}

function readMetrics(store: relationalStore.RdbStore, id?: string): Promise<Metric[]> {
  if (id === undefined) return query(store, 'metrics', 'ORDER BY rowid', [], decodeMetric);
  return query(store, 'metrics', 'WHERE session_id = ? ORDER BY rowid', [id], decodeMetric);
}

function putSession(store: relationalStore.RdbStore, session: Session): Promise<void> {
  return store.executeSql('INSERT OR REPLACE INTO sessions (id, started, active, payload) VALUES (?, ?, ?, ?)',
    [session.id, Date.parse(session.startTimestamp), session.isActive ? 1 : 0, encodePayload(session)]);
}

function putMetric(store: relationalStore.RdbStore, metric: Metric): Promise<void> {
  return store.executeSql('INSERT OR IGNORE INTO metrics (id, session_id, payload) VALUES (?, ?, ?)',
    [metric.metricId, metric.sessionId, encodePayload(metric)]);
}

function putLog(store: relationalStore.RdbStore, sessionId: string, log: LogRecord, fallbackId: string): Promise<void> {
  return store.executeSql('INSERT OR IGNORE INTO logs (id, session_id, time, payload) VALUES (?, ?, ?, ?)',
    [log.recordId ?? fallbackId, sessionId, Date.parse(log.timestamp), encodePayload(log)]);
}

function putCrashReport(store: relationalStore.RdbStore, report: CrashReport): Promise<void> {
  return store.executeSql('INSERT OR IGNORE INTO crash_reports (id, session_id, ingested, payload) VALUES (?, ?, ?, ?)',
    [report.eventId, report.sessionId, Date.parse(report.ingestedAt), encodePayload(report)]);
}

async function prune(store: relationalStore.RdbStore): Promise<void> {
  const cutoff = retentionCutoffTimestamp(Date.now());
  const expired = 'SELECT id FROM sessions WHERE active = 0 AND started < ?';

  await store.executeSql(`DELETE FROM logs WHERE time < ? OR session_id IN (${expired})`, [cutoff, cutoff]);
  await store.executeSql(`DELETE FROM crash_reports WHERE (session_id IS NULL AND ingested < ?) OR session_id IN (${expired})`, [cutoff, cutoff]);
  await store.executeSql(`DELETE FROM metrics WHERE session_id IN (${expired})`, [cutoff]);
  await store.executeSql('DELETE FROM sessions WHERE active = 0 AND started < ?', [cutoff]);
}
