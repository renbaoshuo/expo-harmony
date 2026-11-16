/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type common from '@ohos.app.ability.common';
import relationalStore from '@ohos.data.relationalStore';
import fs from '@ohos.file.fs';
import { ExpoUpdatesError, Json } from '../UpdatesProtocol';
import { PersistentUpdatesLog, logRetention } from './PersistentUpdatesLog';

export class UpdatesLogReader {
  private readonly persistent: PersistentUpdatesLog;
  private readonly context: common.ApplicationContext;
  constructor(context: common.ApplicationContext) {
    this.context = context;
    this.persistent = new PersistentUpdatesLog(context.filesDir);
  }

  async read(maxAge: number): Promise<Json[]> {
    if (!Number.isFinite(maxAge) || maxAge < 0) throw new ExpoUpdatesError('ERR_UPDATES_LOGS', 'Log age must be nonnegative.');
    const cutoff = Date.now() - Math.min(maxAge, logRetention);
    try {
      await this.persistent.migrateLegacy(() => this.readLegacyEntries());
      return (await this.persistent.readEntries()).map(line => {
        try { return JSON.parse(line) as Json; } catch (_) { return undefined; }
      }).filter((entry): entry is Json => entry !== undefined && entry !== null && typeof entry.timestamp === 'number' && entry.timestamp >= cutoff);
    } catch (error) { throw new ExpoUpdatesError('ERR_UPDATES_READ_LOGS', `Unable to read expo-updates logs: ${String(error)}`, error as Error); }
  }

  private async readLegacyEntries(): Promise<string[] | undefined> {
    const path = `${this.context.databaseDir}/rdb/expo-updates.db`;

    try {
      if (!fs.accessSync(path)) return undefined;
    } catch (_) {
      return undefined;
    }

    const store = await relationalStore.getRdbStore(this.context, {
      name: 'expo-updates.db',
      securityLevel: relationalStore.SecurityLevel.S1,
      isReadOnly: true,
    });

    try {
      const tables = await store.querySql("SELECT 1 FROM sqlite_master WHERE type='table' AND name='logs'");

      try {
        if (!tables.goToNextRow()) return [];
      } finally {
        tables.close();
      }

      const rows = await store.querySql('SELECT payload FROM logs ORDER BY timestamp');

      try {
        const entries: string[] = [];
        while (rows.goToNextRow()) entries.push(rows.getString(0));
        return entries;
      } finally {
        rows.close();
      }
    } finally {
      await store.close().catch(error => console.warn(`[ExpoUpdates] Unable to close the legacy log database: ${String(error)}`));
    }
  }

  async clear(): Promise<void> {
    try { await this.persistent.clear(); }
    catch (error) { throw new ExpoUpdatesError('ERR_UPDATES_READ_LOGS', `Unable to clear expo-updates logs: ${String(error)}`, error as Error); }
  }
}
