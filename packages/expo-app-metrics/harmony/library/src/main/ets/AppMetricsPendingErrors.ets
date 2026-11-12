/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LogRecord } from './AppMetricsModels';
import { decodeLogRecord } from './AppMetricsStorageCodec';
import { optionalMap } from './AppMetricsLogging';
import { AppMetricsStorage } from './AppMetricsStorage';
import { ExpoAppMetricsError } from './ExpoAppMetricsError';

const PENDING_DIRECTORY: string = 'expo-app-metrics-errors';
// Same crash-loop cap as SDK 57's Android/iOS PendingErrorStore.
const MAX_PENDING_ERRORS: number = 5;

type Warn = (message: string) => void;

function warnSafely(warn: Warn, message: string): void {
  // Diagnostics must never replace the original fatal error, even if a custom logger fails.
  try { warn(message); } catch (_) {}
}

function removePendingFile(path: string, warn: Warn): void {
  try { fs.unlinkSync(path); }
  catch (error) { warnSafely(warn, `Unable to remove pending Expo App Metrics error '${path}': ${String(error)}`); }
}

/** Best-effort synchronous staging; no I/O or serialization error escapes the fatal handler. */
export function persistFatalError(filesDir: string, sessionId: string, log: LogRecord, warn: Warn): void {
  let temporary: string | undefined;

  try {
    const directory = `${filesDir}/${PENDING_DIRECTORY}`;
    if (!fs.accessSync(directory)) fs.mkdirSync(directory);

    log.recordId = util.generateRandomUUID(true);
    // The timestamp prefix sorts events without reading each record.
    const path = `${directory}/${log.timestamp}-${log.recordId}.json`;
    temporary = `${path}.tmp`;
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify({ sessionId, log }));

    const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.NOFOLLOW);
    try {
      const written = fs.writeSync(file.fd, bytes.buffer);
      if (written !== bytes.byteLength) throw new Error('Incomplete write of the pending fatal error.');
      // A fatal JS error can terminate the process as soon as this function returns.
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }

    fs.renameSync(temporary, path);
  } catch (error) {
    warnSafely(warn, `Unable to persist an Expo App Metrics fatal error: ${String(error)}`);
    if (temporary !== undefined) removePendingFile(temporary, warn);
  }
}

export async function recoverFatalErrors(filesDir: string, storage: AppMetricsStorage, warn: Warn): Promise<void> {
  const directory = `${filesDir}/${PENDING_DIRECTORY}`;
  let names: string[];
  try {
    if (!fs.accessSync(directory)) return;
    names = fs.listFileSync(directory).filter((name: string): boolean => !name.includes('/'));
  } catch (error) {
    warnSafely(warn, `Unable to list pending Expo App Metrics errors: ${String(error)}`);
    return;
  }

  names.filter((name: string): boolean => name.endsWith('.tmp')).forEach((name: string): void => {
    removePendingFile(`${directory}/${name}`, warn);
  });
  const files = names.filter((name: string): boolean => name.endsWith('.json')).sort();
  const overflow = Math.max(0, files.length - MAX_PENDING_ERRORS);
  if (overflow > 0) warnSafely(warn, `Dropping ${overflow} pending Expo App Metrics errors past the ${MAX_PENDING_ERRORS}-file cap.`);
  files.slice(0, overflow).forEach((name: string): void => removePendingFile(`${directory}/${name}`, warn));

  for (const name of files.slice(overflow)) {
    const path = `${directory}/${name}`;
    let sessionId: string;
    let log: LogRecord;
    try {
      const pending = optionalMap(JSON.parse(fs.readTextSync(path)) as ESObject);
      const id: ESObject = pending?.['sessionId'];
      const decoded = decodeLogRecord(pending?.['log']);
      if (typeof id !== 'string' || id.length === 0 || decoded === undefined || decoded.name !== 'js.exception' || decoded.severity !== 'fatal') {
        throw new Error('Invalid pending fatal-error record.');
      }
      sessionId = id;
      log = decoded;
    } catch (error) {
      warnSafely(warn, `Discarding invalid Expo App Metrics fatal error '${path}': ${String(error)}`);
      removePendingFile(path, warn);
      continue;
    }

    try {
      // The persisted record already has the global attributes from the failing process.
      await storage.addLogs(sessionId, [log], false);
      removePendingFile(path, warn);
    } catch (failure) {
      warnSafely(warn, `Unable to ingest an Expo App Metrics fatal error: ${String(failure)}`);
      if (failure instanceof ExpoAppMetricsError && (failure.code === 'ERR_APP_METRICS_SESSION_NOT_FOUND'
        || failure.code === 'ERR_APP_METRICS_STORAGE_CAPACITY')) {
        removePendingFile(path, warn);
      }
    }
  }
}
