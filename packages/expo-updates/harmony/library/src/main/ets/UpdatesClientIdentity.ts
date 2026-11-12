/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type common from '@ohos.app.ability.common';
import relationalStore from '@ohos.data.relationalStore';
import fs from '@ohos.file.fs';
import { EASClientID } from '@expo-harmony/expo-eas-client/EASClientID';
import { ExpoUpdatesError } from './UpdatesProtocol';
import { isCorrupt } from './db/DatabaseError';

const legacyStoreName = 'expo-updates.db';
const legacyIdentities = new Map<string, string | null>();
const pendingReads = new Map<string, Promise<void>>();

class LegacyIdentityPending extends Error {}

function legacyPath(context: common.ApplicationContext): string {
  return context.databaseDir + '/rdb/' + legacyStoreName;
}

async function readLegacyIdentity(context: common.ApplicationContext): Promise<string | undefined> {
  let database: relationalStore.RdbStore | undefined;
  try {
    if (!fs.accessSync(legacyPath(context))) return undefined;

    database = await relationalStore.getRdbStore(context, {
      name: legacyStoreName, securityLevel: relationalStore.SecurityLevel.S1, isReadOnly: true,
    });
    const tables = await database.querySql("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('json_data','metadata')");
    const names: string[] = [];

    try { while (tables.goToNextRow()) names.push(tables.getString(0)); } finally { tables.close(); }

    const query = names.includes('json_data')
      ? "SELECT value FROM json_data WHERE scope='' AND key='clientId' ORDER BY last_updated DESC,id DESC LIMIT 1"
      : names.includes('metadata') ? "SELECT payload FROM metadata WHERE scope='' AND key='clientId' LIMIT 1" : undefined;
    if (query === undefined) return undefined;

    const rows = await database.querySql(query);

    try {
      if (!rows.goToNextRow()) return undefined;

      const value = JSON.parse(rows.getString(0));
      if (typeof value !== 'string') throw new ExpoUpdatesError('ERR_UPDATES_CLIENT_ID', 'The legacy EAS client ID is invalid.');

      return value;
    } finally { rows.close(); }
  } catch (error) {
    if ((error as { code?: number }).code === 13900002) return undefined;
    if (!isCorrupt(error)) throw new ExpoUpdatesError('ERR_UPDATES_CLIENT_ID', `Unable to migrate the legacy EAS client ID: ${String(error)}`, error as Error);

    console.warn('[ExpoUpdates] The corrupt legacy database cannot supply its EAS client ID.');

    return undefined;
  } finally {
    await database?.close().catch(error => console.warn(`[ExpoUpdates] Unable to close the legacy identity database: ${String(error)}`));
  }
}

EASClientID.registerMigration(context => {
  const path = legacyPath(context);
  if (legacyIdentities.has(path)) return legacyIdentities.get(path) ?? undefined;
  if (!fs.accessSync(path)) return undefined;
  throw new LegacyIdentityPending('Expo Updates is still preparing the legacy EAS client ID.');
});

// Resolve the old Updates database before exposing the synchronous EAS constants.
// The EAS getter preserves the canonical file and Preferences precedence.
export async function prepareClientIdentity(context: common.ApplicationContext, legacyOnly = false): Promise<void> {
  const path = legacyPath(context);
  if (legacyOnly && !fs.accessSync(path)) return;

  const identity = clientIdentity(context);
  try {
    identity.clientID;
    return;
  } catch (error) {
    if (!(error instanceof LegacyIdentityPending)) throw error;
  }

  let pending = pendingReads.get(path);
  if (pending === undefined) {
    pending = readLegacyIdentity(context).then(id => {
      legacyIdentities.set(path, id ?? null);
    }).finally(() => pendingReads.delete(path));
    pendingReads.set(path, pending);
  }
  await pending;
  identity.clientID;
}

export function clientIdentity(context: common.ApplicationContext): EASClientID { return new EASClientID(context); }
