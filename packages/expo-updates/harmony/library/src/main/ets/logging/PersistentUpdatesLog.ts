/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { PersistentFileLog } from '@expo-harmony/expo-modules-core/Logging';

export const updatesLogCategory = 'dev.expo.updates';
export const logRetention = 86400000;
const imported = '{"expoUpdatesLegacyLogsImported":true}';

export class PersistentUpdatesLog {
  private static readonly prepared = new Set<string>();
  private readonly file: PersistentFileLog;

  constructor(private readonly directory: string) { this.file = new PersistentFileLog(updatesLogCategory, directory); }

  prepare(): Promise<void> {
    if (PersistentUpdatesLog.prepared.has(this.directory)) return Promise.resolve();
    PersistentUpdatesLog.prepared.add(this.directory);
    return this.purge().catch(error => {
      PersistentUpdatesLog.prepared.delete(this.directory);
      throw new Error(`Unable to prepare update logs: ${String(error)}`);
    });
  }

  private retained(line: string): boolean {
    if (line === imported) return true;
    try {
      const entry = JSON.parse(line);
      return entry !== null && typeof entry.timestamp === 'number' && Number.isFinite(entry.timestamp) && entry.timestamp >= Date.now() - logRetention;
    } catch (_) { return false; }
  }

  private purge(): Promise<void> { return this.file.purgeEntriesNotMatchingFilter(line => this.retained(line)); }

  async readEntries(): Promise<string[]> {
    await this.purge();
    return (await this.file.readEntriesAsync()).filter(line => line !== imported);
  }

  clear(): Promise<void> { return this.file.updateEntries(() => [imported]); }

  async migrateLegacy(readEntries: () => Promise<string[] | undefined>): Promise<void> {
    if ((await this.file.readEntriesAsync()).includes(imported)) return;

    let legacy: string[] | undefined;
    try {
      legacy = await readEntries();
    } catch (error) {
      console.warn(`[ExpoUpdates] Unable to read legacy logs; migration will retry: ${String(error)}`);
      return;
    }

    if (legacy === undefined) return;

    const retained = legacy.filter(line => this.retained(line));

    await this.file.updateEntries(current => {
      if (current.includes(imported)) return undefined;

      // Commit the entries and marker together so retries cannot duplicate an interrupted import.
      return [imported, ...retained, ...current.filter(line => this.retained(line))];
    });
  }
}
