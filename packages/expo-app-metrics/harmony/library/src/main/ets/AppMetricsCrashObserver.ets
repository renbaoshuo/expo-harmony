/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { LogRecord } from './AppMetricsModels';
import { crashFromSystemEvent } from './AppMetricsCrashReport';
import { optionalMap, optionalText } from './AppMetricsLogging';
import { AppMetricsStorage } from './AppMetricsStorage';
import { ExpoAppMetricsError } from './ExpoAppMetricsError';

// Huawei permits 32-character custom parameter names, merged into the event's params.
const SESSION_PARAMETER: string = 'expo_app_metrics_session_id';
// PendingErrorStore's five-record crash-loop policy, applied to Harmony native faults.
// This disk staging budget is independent of the lower serialized-store safety limit.
const MAX_PENDING_FAULTS: number = 5;
const MAX_PENDING_FAULT_BYTES: number = 16 * 1024 * 1024;

class StagedFaultFile {
  readonly path: string;
  readonly size: number;
  readonly modified: number;

  constructor(path: string, size: number, modified: number) {
    this.path = path;
    this.size = size;
    this.modified = modified;
  }
}

/** A process-owned observer survives RN reloads and receives prior-run events on launch. */
export class AppMetricsCrashObserver {
  private readonly storage: AppMetricsStorage;
  private readonly warn: (message: string) => void;
  private watcher?: hiAppEvent.Watcher;
  private readonly pendingDirectory: string;
  private stagingBudgetBlocked: boolean = false;

  constructor(storage: AppMetricsStorage, sessionId: string, warn: (message: string) => void, filesDir: string) {
    this.storage = storage;
    this.warn = warn;
    this.pendingDirectory = `${filesDir}/expo-app-metrics-faults`;
    this.recover();
    if (!canIUse('SystemCapability.HiviewDFX.HiAppEvent')) return;
    try {
      const parameters: Record<string, hiAppEvent.ParamType> = {};
      parameters[SESSION_PARAMETER] = sessionId;
      Promise.all([
        hiAppEvent.setEventParam(parameters, hiAppEvent.domain.OS, hiAppEvent.event.APP_CRASH),
        hiAppEvent.setEventParam(parameters, hiAppEvent.domain.OS, hiAppEvent.event.APP_FREEZE),
      ]).catch((error: Object): void => warn(`Unable to associate HiAppEvent faults with Expo App Metrics: ${String(error)}`));
    } catch (error) { warn(`Unable to configure HiAppEvent session attribution: ${String(error)}`); }
    const watcher: hiAppEvent.Watcher = {
      name: 'ExpoAppMetricsFaults',
      appEventFilters: [{ domain: hiAppEvent.domain.OS, names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE] }],
      onReceive: (_domain: string, groups: hiAppEvent.AppEventGroup[]): void => {
        groups.forEach((group: hiAppEvent.AppEventGroup): void => {
          group.appEventInfos.forEach((event: hiAppEvent.AppEventInfo): void => {
            // HiAppEvent acknowledges its callback synchronously. Stage the event durably
            // before returning so an RN reload or process death cannot lose an async write.
            try { this.deliver(event, this.stage(event)); }
            catch (error) { warn(`Unable to stage a HiAppEvent fault: ${String(error)}`); }
          });
        });
      },
    };
    try {
      hiAppEvent.addWatcher(watcher);
      this.watcher = watcher;
    } catch (error) { warn(`Unable to subscribe to HiAppEvent faults: ${String(error)}`); }
  }

  private stage(event: hiAppEvent.AppEventInfo): string {
    if (!fs.accessSync(this.pendingDirectory)) fs.mkdirSync(this.pendingDirectory);
    // Only repair an earlier failed post-commit budget cleanup before accepting more data.
    // A normal new write must not evict valid pending diagnostics before it commits.
    if (this.stagingBudgetBlocked) {
      this.boundedFiles();
      this.stagingBudgetBlocked = false;
    } else {
      this.cleanupTemporaryFiles();
    }
    const serialized = JSON.stringify(event);
    if (serialized.length > MAX_PENDING_FAULT_BYTES) throw new Error('HiAppEvent fault exceeds the 16 MiB native diagnostic staging budget.');

    const payload = new util.TextEncoder().encodeInto(serialized);
    if (payload.byteLength > MAX_PENDING_FAULT_BYTES) throw new Error('HiAppEvent fault exceeds the 16 MiB native diagnostic staging budget.');
    const path = `${this.pendingDirectory}/${Date.now()}-${util.generateRandomUUID(true)}.json`;
    const temporary = `${path}.tmp`;
    try {
      const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.NOFOLLOW);
      try {
        const written = fs.writeSync(file.fd, payload.buffer);
        if (written !== payload.byteLength) throw new Error('Incomplete write of the staged HiAppEvent fault.');
        fs.fsyncSync(file.fd);
      } finally { fs.closeSync(file); }
      fs.renameSync(temporary, path);
    } catch (error) {
      this.removeStagedFile(temporary);
      throw error as Error;
    }
    // Commit first: a failed write never sacrifices an older pending diagnostic.
    try {
      this.boundedFiles();
    } catch (error) {
      // Keep the committed record if reclamation fails after deleting some old files.
      // Refuse further writes until the queue can be brought back within its budget.
      this.stagingBudgetBlocked = true;
      this.warn(`HiAppEvent fault '${path}' was committed, but staging budget cleanup failed; further staging is blocked until cleanup succeeds: ${String(error)}`);
    }

    return path;
  }

  private removeStagedFile(path: string): boolean {
    try {
      if (fs.accessSync(path)) fs.unlinkSync(path);
      return true;
    } catch (error) {
      this.warn(`Unable to remove staged HiAppEvent file '${path}': ${String(error)}`);
      return false;
    }
  }

  private cleanupTemporaryFiles(): void {
    for (const name of fs.listFileSync(this.pendingDirectory)) {
      if (!name.includes('/') && name.endsWith('.tmp') && !this.removeStagedFile(`${this.pendingDirectory}/${name}`)) {
        throw new Error('Cannot reclaim interrupted native diagnostic writes.');
      }
    }
  }

  private boundedFiles(): StagedFaultFile[] {
    this.cleanupTemporaryFiles();
    const files: StagedFaultFile[] = [];

    for (const name of fs.listFileSync(this.pendingDirectory)) {
      if (name.includes('/')) continue;
      const path = `${this.pendingDirectory}/${name}`;
      if (name.endsWith('.json')) {
        const stat = fs.statSync(path);
        if (stat.size > MAX_PENDING_FAULT_BYTES) {
          fs.unlinkSync(path);
          this.warn(`Dropping oversized staged HiAppEvent fault '${path}' past the 16 MiB native diagnostic budget.`);
        } else {
          files.push(new StagedFaultFile(path, stat.size, stat.mtime));
        }
      }
    }
    // Filesystem mtime records actual staging time; the millisecond filename prefix breaks ties.
    files.sort((left: StagedFaultFile, right: StagedFaultFile): number => left.modified - right.modified || left.path.localeCompare(right.path));
    let bytes = files.reduce((sum: number, file: StagedFaultFile): number => sum + file.size, 0);

    while (files.length > MAX_PENDING_FAULTS || bytes > MAX_PENDING_FAULT_BYTES) {
      const removed = files.shift();
      if (removed === undefined) throw new Error('HiAppEvent fault cannot fit the native diagnostic staging budget.');
      fs.unlinkSync(removed.path);
      bytes -= removed.size;
      this.warn(`Dropping oldest staged HiAppEvent fault '${removed.path}' to keep at most ${MAX_PENDING_FAULTS} pending faults and 16 MiB of native diagnostic data.`);
    }

    return files;
  }

  private deliver(event: hiAppEvent.AppEventInfo, path: string): void {
    this.receive(event).then((): void => {
      // A later event may have reclaimed this pending file while ingestion was queued.
      try { if (fs.accessSync(path)) fs.unlinkSync(path); }
      catch (error) { this.warn(`Unable to remove ingested HiAppEvent fault '${path}': ${String(error)}`); }
    }, (error: Object): void => {
      if (error instanceof ExpoAppMetricsError && error.code === 'ERR_APP_METRICS_STORAGE_CAPACITY') {
        this.warn(`Dropping staged HiAppEvent fault '${path}' after a permanent metrics-storage capacity failure: ${error.message}`);
        this.removeStagedFile(path);
      } else {
        // Transient storage I/O failures retain the record in the bounded retry queue.
        this.warn(`Unable to save a HiAppEvent fault: ${String(error)}`);
      }
    });
  }

  private recover(): void {
    let files: StagedFaultFile[];
    try {
      if (!fs.accessSync(this.pendingDirectory)) return;
      files = this.boundedFiles();
    } catch (error) {
      this.stagingBudgetBlocked = true;
      this.warn(`Unable to prepare pending HiAppEvent faults for recovery: ${String(error)}`);
      return;
    }
    for (const file of files) {
      const path = file.path;
      try {
        const raw = optionalMap(JSON.parse(fs.readTextSync(path)) as ESObject);
        if (raw === undefined || typeof raw['domain'] !== 'string' || typeof raw['name'] !== 'string'
          || typeof raw['eventType'] !== 'number' || optionalMap(raw['params']) === undefined) {
          throw new Error('Invalid staged HiAppEvent record.');
        }

        const event: hiAppEvent.AppEventInfo = {
          domain: raw['domain'] as string, name: raw['name'] as string,
          eventType: raw['eventType'] as hiAppEvent.EventType, params: raw['params'] as Object,
        };
        this.deliver(event, path);
      } catch (error) {
        this.warn(`Discarding invalid staged HiAppEvent fault '${path}': ${String(error)}`);
        try { fs.unlinkSync(path); } catch (cleanup) { this.warn(`Unable to remove '${path}': ${String(cleanup)}`); }
      }
    }
  }

  private async receive(event: hiAppEvent.AppEventInfo): Promise<void> {
    if (event.domain !== hiAppEvent.domain.OS) return;

    const params = optionalMap(event.params as ESObject);
    if (params === undefined) { this.warn('HiAppEvent returned a fault without valid parameters.'); return; }
    const sessionId = optionalText(params[SESSION_PARAMETER]);
    if (event.name === hiAppEvent.event.APP_CRASH) {
      const report = crashFromSystemEvent(event.name, params);
      if (report === undefined) {
        this.warn('HiAppEvent returned a crash without a valid event timestamp or app version.');
        return;
      }
      await this.storage.addCrashReport(report, sessionId);
    } else if (event.name === hiAppEvent.event.APP_FREEZE && sessionId !== undefined) {
      // A freeze can recover: report it as an error, never fabricate a fatal crash.
      const time: ESObject = params['time'];
      if (typeof time !== 'number' || !Number.isFinite(time) || !Number.isFinite(new Date(time).getTime())) return;
      if (await this.storage.getSession(sessionId) === undefined) return;

      const exception = optionalMap(params['exception']);
      const log = new LogRecord(
        new Date(time).toISOString(), 'app.freeze', 'error', optionalText(exception?.['message']),
        { 'expo.error.source': 'nativeFreeze', 'expo.error.is_fatal': false },
      );
      log.recordId = `${event.name}:${time}:${String(params['pid'])}:${optionalText(params['uuid']) ?? ''}`;
      await this.storage.addLogs(sessionId, [log]);
    }
  }
}
