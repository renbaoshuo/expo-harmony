/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

/// <reference path="./UpdatesNative.d.ts" />

import relationalStore from '@ohos.data.relationalStore';
import { isCorrupt } from './db/DatabaseError';
import type common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import crypto from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { ExpoUpdatesManifest } from '@expo-harmony/expo-manifests';
import { linkAsset } from 'libexpo_updates.so';
import { DomAsset, ExpoUpdatesError, Json, UpdateAsset, UpdateRecord, parseDomAssetLayout, parseRemoteAssets } from './UpdatesProtocol';
import { assertIntegrity, migrate, DATABASE_VERSION } from './db/DatabaseSchema';
import { AssetsDao, UpdatesDao, JSONDataDao } from './db/Daos';
import { DatabaseHolder } from './db/DatabaseHolder';
import { DatabaseIntegrityCheck } from './db/DatabaseIntegrityCheck';
import { Reaper } from './db/Reaper';
import { UpdatesLogger } from './logging/UpdatesLogger';
import { assetFileUrl, domBundleDirectory, isAssetPath, isUpdateId } from './UpdatesAssetPaths';

export function encode(value: string): Uint8Array { return new util.TextEncoder().encode(value); }
export function decode(value: Uint8Array): string { return new util.TextDecoder('utf-8', { fatal: true }).decodeToString(value); }
export function base64(value: Uint8Array): string { return new util.Base64Helper().encodeToStringSync(value); }
export function digest(value: Uint8Array): string {
  const hash = crypto.createMd('SHA256');
  hash.updateSync({ data: value });
  return base64(hash.digestSync().data).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function exists(path: string): boolean {
  try { return fs.accessSync(path); } catch (_) { return false; }
}

export function write(file: fs.File, bytes: ArrayBuffer): void {
  let offset = 0;
  while (offset < bytes.byteLength) {
    const count = fs.writeSync(file.fd, bytes.slice(offset));
    if (count <= 0) throw new ExpoUpdatesError('ERR_UPDATES_ASSET', 'Asset write made no progress.');
    offset += count;
  }
}

export function hashFile(path: string): string {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const hash = crypto.createMd('SHA256');
    const buffer = new ArrayBuffer(65536);
    let count: number;
    while ((count = fs.readSync(file.fd, buffer)) > 0) hash.updateSync({ data: new Uint8Array(buffer, 0, count) });

    return base64(hash.digestSync().data).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  } finally {
    fs.closeSync(file);
  }
}

export function isVerifiedAsset(directory: string, asset: UpdateAsset, expected: string | undefined = asset.hash?.replace(/=+$/, '')): boolean {
  if (!asset.path || !asset.digest || (expected !== undefined && asset.digest !== expected) || !isAssetPath(directory, asset.path)) return false;

  try { return fs.lstatSync(asset.path).isFile() && hashFile(asset.path) === asset.digest; }
  catch (_) { return false; }
}

function verifyDomLayout(root: string, entries: DomAsset[]): boolean {
  try {
    if (!fs.lstatSync(root).isDirectory()) return false;

    const expected = new Map(entries.map(entry => [entry.filename, entry.hash]));
    const directories = [''];

    while (directories.length) {
      const directory = directories.pop()!;
      for (const name of fs.listFileSync(root + '/' + directory)) {
        const relative = directory + name;
        const path = root + '/' + relative;
        const info = fs.lstatSync(path);
        if (info.isDirectory()) directories.push(relative + '/');
        else if (info.isFile() && expected.has(relative) && expected.get(relative) === hashFile(path)) expected.delete(relative);
        else return false;
      }
    }

    return expected.size === 0;
  } catch (_) { return false; }
}

interface Database {
  store: relationalStore.RdbStore;
  holder: DatabaseHolder;
}

export class UpdatesStorage {
  readonly directory: string;
  readonly temporary: string;
  private readonly domDirectory: string;
  readonly logger: UpdatesLogger;
  private database?: Database;
  private opening?: Promise<void>;

  constructor(private readonly context: common.ApplicationContext) {
    this.directory = context.filesDir + '/expo-updates';
    this.temporary = this.directory + '/temporary';
    this.domDirectory = this.directory + '/dom';
    this.logger = new UpdatesLogger(context);
  }

  async open(): Promise<void> {
    if (this.opening !== undefined) return this.opening;
    if (this.database !== undefined) return;

    this.opening = this.openInternal();

    try { await this.opening; } finally { this.opening = undefined; }
  }

  private async openInternal(retry: boolean = true): Promise<void> {
    if (!exists(this.directory)) fs.mkdirSync(this.directory, true);
    if (!exists(this.temporary)) fs.mkdirSync(this.temporary, true);

    let db: relationalStore.RdbStore | undefined;

    try {
      db = await relationalStore.getRdbStore(this.context, { name: 'expo-updates.db', securityLevel: relationalStore.SecurityLevel.S1 });
      if (db.version > DATABASE_VERSION) throw new ExpoUpdatesError('ERR_UPDATES_DATABASE', `Unsupported Updates database version ${db.version}.`);

      db.executeSync('PRAGMA foreign_keys = ON');
      if (db.version < DATABASE_VERSION) await migrate(db, db.version);
      else assertIntegrity(db);

      const holder = new DatabaseHolder(db);
      this.database = { store: db, holder };
    } catch (error) {
      this.database = undefined;
      if (db !== undefined) {
        try { await db.close(); } catch (failure) { console.error(`Unable to close Updates database: ${String(failure)}`); }
      }

      const path = this.context.databaseDir + '/rdb/expo-updates.db';
      if (retry && isCorrupt(error) && exists(path)) {
        try {
          const archive = path + '.corrupt-' + Date.now();
          fs.renameSync(path, archive);
          for (const suffix of ['-wal', '-shm']) if (exists(path + suffix)) fs.renameSync(path + suffix, archive + suffix);
          console.warn(`[ExpoUpdates] Archived unusable database at ${archive}`);

          return this.openInternal(false);
        } catch (failure) { console.error(`[ExpoUpdates] Unable to archive unusable database: ${String(failure)}`); }
      }

      throw new ExpoUpdatesError('ERR_UPDATES_DATABASE', `Unable to open Updates database: ${String(error)}`, error instanceof Error ? error : undefined);
    }

    for (const file of fs.listFileSync(this.temporary)) {
      this.removeTree(this.temporary + '/' + file);
    }
  }

  private removeTree(path: string): void {
    try {
      if (fs.lstatSync(path).isDirectory()) fs.rmdirSync(path);
      else fs.unlinkSync(path);
    } catch (error) { this.logger.log(`Unable to remove an Updates file or directory: ${String(error)}`, 'Unknown', 'warn'); }
  }

  prepareDomAssets(update: UpdateRecord): void {
    const layout = parseDomAssetLayout(update.manifest);
    if (!layout.length) return;
    if (!isUpdateId(update.id)) throw new ExpoUpdatesError('ERR_UPDATES_ASSET', 'Invalid DOM update ID.');

    const sources = new Map(update.assets.map(asset => [asset.key, asset]));
    const entries = layout.map(entry => {
      const hash = entry.hash ?? sources.get(entry.key)?.digest;
      if (!hash) throw new ExpoUpdatesError('ERR_UPDATES_ASSET', `Missing verified DOM asset ${entry.key}.`);
      return { ...entry, hash };
    });
    if (!exists(this.domDirectory)) fs.mkdirSync(this.domDirectory);
    if (!fs.lstatSync(this.domDirectory).isDirectory()) throw new ExpoUpdatesError('ERR_UPDATES_ASSET', 'Invalid DOM storage directory.');

    const root = this.domDirectory + '/' + update.id;
    if (!verifyDomLayout(root, entries)) this.publishDomAssets(sources, root, entries);
    update.domAssets = {
      baseUrl: assetFileUrl(root + '/' + domBundleDirectory),
      files: new Map(entries.map(entry => [entry.key, root + '/' + entry.filename])),
    };
  }

  private publishDomAssets(sources: Map<string | null, UpdateAsset>, root: string, entries: DomAsset[]): void {
    const stage = this.temporary + '/' + util.generateRandomUUID();
    const previous = this.temporary + '/' + util.generateRandomUUID();
    let displaced = false;

    try {
      fs.mkdirSync(stage);

      for (const entry of entries) {
        const asset = sources.get(entry.key);
        if (!asset?.path || asset.digest !== entry.hash || !isAssetPath(this.directory, asset.path) || !fs.lstatSync(asset.path).isFile()) {
          throw new ExpoUpdatesError('ERR_UPDATES_ASSET', `Missing verified DOM asset ${entry.key}.`);
        }

        const destination = stage + '/' + entry.filename;
        const directory = destination.slice(0, destination.lastIndexOf('/'));
        if (!exists(directory)) fs.mkdirSync(directory, true);
        if (!linkAsset(asset.path, destination)) fs.copyFileSync(asset.path, destination);
      }

      if (!verifyDomLayout(stage, entries)) throw new ExpoUpdatesError('ERR_UPDATES_ASSET_HASH', 'DOM assets failed SHA-256 verification.');

      if (exists(root)) {
        fs.renameSync(root, previous);
        displaced = true;
      }

      try {
        fs.renameSync(stage, root);
      } catch (error) {
        if (displaced) fs.renameSync(previous, root);
        throw error;
      }

      if (displaced) this.removeTree(previous);
    } finally {
      if (exists(stage)) this.removeTree(stage);
    }
  }

  private get db(): Database {
    if (this.database === undefined) throw new ExpoUpdatesError('ERR_UPDATES_DATABASE', 'Updates database is not open.');
    return this.database;
  }

  private async read<T>(body: (assets: AssetsDao, updates: UpdatesDao, metadata: JSONDataDao) => T): Promise<T> {
    return this.db.holder.withDatabase(connection => {
      const assets = new AssetsDao(connection);
      return body(assets, new UpdatesDao(connection, assets), new JSONDataDao(connection));
    });
  }
  private async write<T>(body: (assets: AssetsDao, updates: UpdatesDao, metadata: JSONDataDao) => T): Promise<T> {
    return this.db.holder.transaction(connection => {
      const assets = new AssetsDao(connection);
      return body(assets, new UpdatesDao(connection, assets), new JSONDataDao(connection));
    });
  }

  updates(scope?: string): Promise<UpdateRecord[]> { return this.read((_a, updates) => updates.all(scope)); }
  update(id: string): Promise<UpdateRecord | undefined> { return this.read((_a, updates) => updates.get(id)); }
  failed(): Promise<UpdateRecord[]> { return this.read((_a, updates) => updates.failed()); }
  launchable(scope: string): Promise<UpdateRecord[]> { return this.write((_a, updates) => updates.launchable(scope)); }

  async insert(update: UpdateRecord): Promise<void> {
    if (update.assets.filter(asset => asset.launch).length !== 1) throw new ExpoUpdatesError('ERR_UPDATES_DATABASE', 'An update must have exactly one launch asset.');

    await this.write((_a, updates) => {
      const stored = updates.get(update.id);
      if (stored) {
        if (JSON.stringify(parseDomAssetLayout(stored.manifest)) !== JSON.stringify(parseDomAssetLayout(update.manifest))) {
          throw new ExpoUpdatesError('ERR_UPDATES_MANIFEST', 'A cached update ID cannot change its DOM asset layout.');
        }
        if (stored.status === 'embedded' || typeof stored.manifest.launchAsset?.packagerHash === 'string') {
          throw new ExpoUpdatesError('ERR_UPDATES_MANIFEST', 'A remote update cannot reuse the embedded update ID.');
        }

        const assets = parseRemoteAssets(new ExpoUpdatesManifest(stored.manifest), {});
        const received = new Map(update.assets.map(asset => [asset.key, asset]));
        if (update.runtime !== stored.runtime || received.size !== assets.length || assets.some(asset => {
          const replacement = received.get(asset.key);
          return replacement === undefined || replacement.launch !== asset.launch
            || replacement.hash?.replace(/=+$/, '') !== asset.hash?.replace(/=+$/, '')
            || (!asset.hash && replacement.url !== asset.url);
        })) {
          throw new ExpoUpdatesError('ERR_UPDATES_MANIFEST', 'A cached update ID cannot change its runtime or asset identities.');
        }
        if (stored.status === 'ready' && !stored.assets.some(asset => asset.launch)) updates.setStatus(update.id, 'pending');

        return;
      }

      updates.insert(update);
    });
  }

  async finish(update: UpdateRecord): Promise<void> {
    if (update.assets.filter(asset => asset.launch).length !== 1 || update.assets.some(asset => !asset.path || !asset.digest)) {
      throw new ExpoUpdatesError('ERR_UPDATES_DATABASE', 'Cannot finish an update without its downloaded assets and launch asset.');
    }

    this.prepareDomAssets(update);

    const ids = await this.write((_a, updates) => {
      const stored = updates.get(update.id);
      if (!stored) updates.insert(update);
      else if (stored.scope !== update.scope) updates.setScope(update.id, update.scope);

      const ids = update.assets.map((asset, ordinal) => updates.associate(update.id, asset, ordinal));
      updates.setStatus(update.id, update.status);

      return ids;
    });

    ids.forEach((id, index) => { update.assets[index].id = id; });
  }

  markFinished(id: string): Promise<void> { return this.write((_a, updates) => updates.markFinished(id)); }
  markAccessed(id: string, time: number = Date.now()): Promise<void> { return this.write((_a, updates) => updates.markAccessed(id, time)); }
  incrementSuccessful(id: string): Promise<void> { return this.write((_a, updates) => updates.incrementSuccessful(id)); }
  incrementFailed(id: string): Promise<void> { return this.write((_a, updates) => updates.incrementFailed(id)); }

  async setCommitTime(update: UpdateRecord, time: number): Promise<void> {
    await this.write((_a, updates) => updates.setCommitTime(update.id, time));
    update.time = time;
  }

  async asset(asset: UpdateAsset): Promise<UpdateAsset | undefined> {
    const stored = await this.read(assets => (asset.id === undefined ? undefined : assets.getById(asset.id)) ?? assets.get(asset.key));
    return stored === undefined ? undefined : { ...stored, launch: asset.launch };
  }

  async save(asset: UpdateAsset): Promise<void> {
    if (!asset.path || !asset.digest) throw new ExpoUpdatesError('ERR_UPDATES_ASSET', 'Cannot persist an incomplete asset.');
    asset.id = await this.write(assets => assets.save(asset));
  }

  async metadata(scope: string, key: string): Promise<ESObject> {
    return (await this.read((_a, _u, metadata) => metadata.get(scope, key)))?.value ?? null;
  }

  async setMetadata(scope: string, key: string, value: ESObject): Promise<void> {
    await this.write((_a, _u, metadata) => metadata.set(scope, key, value));
  }

  updateMetadata(scope: string, key: string, body: (value: ESObject) => ESObject): Promise<ESObject> {
    return this.write((_a, _u, metadata) => metadata.update(scope, key, body));
  }

  consumeMetadata(scope: string, key: string): Promise<ESObject> {
    return this.write((_a, _u, metadata) => metadata.consume(scope, key));
  }

  async setResponseMetadata(scope: string, headers?: Json, filters?: Json): Promise<void> {
    if (headers === undefined && filters === undefined) return;
    await this.write((_a, _u, metadata) => {
      if (headers !== undefined) metadata.set(scope, 'headers', headers);
      if (filters !== undefined) metadata.set(scope, 'filters', filters);
    });
  }

  integrity(embedded?: string): Promise<void> {
    return this.db.holder.transaction(db => new DatabaseIntegrityCheck(exists).run(db, embedded));
  }

  async delete(records: UpdateRecord[]): Promise<void> {
    await new Reaper(this.db.holder, path => {
      if (!isAssetPath(this.directory, path)) throw new ExpoUpdatesError('ERR_UPDATES_ASSET', `Refusing to delete asset at unsafe path ${path}.`);

      if (exists(path)) fs.unlinkSync(path);
    },
      (message, asset) => this.logger.log(message, 'Unknown', 'warn', undefined, asset)).run(records);
    if (!exists(this.domDirectory) || !fs.lstatSync(this.domDirectory).isDirectory()) return;

    const live = new Set((await this.updates()).map(update => update.id));
    for (const name of fs.listFileSync(this.domDirectory)) {
      if (isUpdateId(name) && !live.has(name)) this.removeTree(this.domDirectory + '/' + name);
    }
  }

}
