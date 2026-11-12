/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import relationalStore from '@ohos.data.relationalStore';
import { ExpoUpdatesError, Json, UpdateAsset, UpdateRecord } from '../UpdatesProtocol';
import type { AssetEntity, UpdateEntity, JSONDataEntity } from './Entities';

export interface DatabaseConnection {
  querySqlSync(sql: string, args?: relationalStore.ValueType[]): relationalStore.ResultSet;
  executeSync(sql: string, args?: relationalStore.ValueType[]): relationalStore.ValueType;
}

export function readRows<T>(db: DatabaseConnection, sql: string, args: relationalStore.ValueType[], read: (row: relationalStore.ResultSet) => T): T[] {
  const rows = db.querySqlSync(sql, args);
  try {
    const values: T[] = [];
    while (rows.goToNextRow()) values.push(read(rows));
    return values;
  } finally {
    rows.close();
  }
}

const assetColumns = 'a.asset_id,a.key,a.url,a.hash,a.type,a.extension,a.headers,a.embedded,a.path,a.digest,a.download_time,a.marked';
const updateColumns = 'id,scope,runtime,time,status,manifest,url,headers,keep,accessed,successful,failed,launch_asset_id';

function assetEntity(row: relationalStore.ResultSet): AssetEntity {
  return {
    id: row.getLong(0), key: row.isColumnNull(1) ? null : row.getString(1),
    url: row.isColumnNull(2) ? '' : row.getString(2), hash: row.isColumnNull(3) ? undefined : row.getString(3),
    type: row.isColumnNull(4) ? '' : row.getString(4), extension: row.isColumnNull(5) ? '' : row.getString(5),
    headers: row.isColumnNull(6) ? {} : JSON.parse(row.getString(6)), embedded: row.isColumnNull(7) ? undefined : row.getString(7),
    path: row.isColumnNull(8) ? undefined : row.getString(8), digest: row.isColumnNull(9) ? undefined : row.getString(9),
    downloadTime: row.isColumnNull(10) ? undefined : row.getLong(10), marked: row.getLong(11) !== 0,
  };
}

function updateEntity(row: relationalStore.ResultSet): UpdateEntity {
  return {
    id: row.getString(0), scope: row.getString(1), runtime: row.getString(2), time: row.getLong(3),
    status: row.getString(4) as UpdateRecord['status'], manifest: JSON.parse(row.getString(5)),
    url: row.isColumnNull(6) ? null : row.getString(6), headers: row.isColumnNull(7) ? null : JSON.parse(row.getString(7)),
    keep: row.getLong(8) !== 0, accessed: row.getLong(9), successful: row.getLong(10), failed: row.getLong(11),
    launchAssetId: row.isColumnNull(12) ? undefined : row.getLong(12),
  };
}

export class AssetsDao {
  constructor(private readonly db: DatabaseConnection) {}

  get(key: string | null): AssetEntity | undefined {
    if (key === null) return undefined;
    return readRows(this.db, `SELECT ${assetColumns} FROM asset_records a WHERE a.key=? LIMIT 1`, [key], assetEntity)[0];
  }

  getById(id: number): AssetEntity | undefined {
    return readRows(this.db, `SELECT ${assetColumns} FROM asset_records a WHERE a.asset_id=?`, [id], assetEntity)[0];
  }

  all(): AssetEntity[] { return readRows(this.db, `SELECT ${assetColumns} FROM asset_records a`, [], assetEntity); }

  forUpdate(id: string, launchId?: number): UpdateAsset[] {
    const assets = readRows(this.db, `SELECT ${assetColumns} FROM update_asset_records r JOIN asset_records a ON a.asset_id=r.asset_id WHERE r.update_id=? ORDER BY r.ordinal`, [id], assetEntity);
    if (launchId !== undefined && !assets.some(asset => asset.id === launchId)) {
      const launch = this.getById(launchId);
      if (launch) assets.unshift(launch);
    }

    return assets.map(asset => ({ ...asset, launch: asset.id === launchId }));
  }

  save(asset: Omit<UpdateAsset, 'launch'>): number {
    const existing = (asset.id === undefined ? undefined : this.getById(asset.id)) ?? this.get(asset.key);
    if (existing) {
      this.db.executeSync(`UPDATE asset_records SET url=COALESCE(NULLIF(?,''),url),headers=?,hash=COALESCE(hash,?),
        embedded=COALESCE(?,embedded),path=COALESCE(?,path),digest=COALESCE(?,digest),
        download_time=CASE WHEN ? IS NOT NULL AND (?<>COALESCE(path,'') OR ?<>COALESCE(digest,'')) THEN ? ELSE download_time END,
        marked=0 WHERE asset_id=?`, [asset.url, JSON.stringify(asset.headers), asset.hash ?? null, asset.embedded ?? null,
        asset.path ?? null, asset.digest ?? null, asset.path ?? null, asset.path ?? null, asset.digest ?? null, Date.now(), existing.id]);
      return existing.id;
    }

    this.db.executeSync(`INSERT INTO asset_records(key,url,hash,type,extension,headers,embedded,path,digest,download_time,marked)
      VALUES (?,?,?,?,?,?,?,?,?,?,0)`, [asset.key, asset.url || null, asset.hash ?? null, asset.type || null,
      asset.extension, JSON.stringify(asset.headers), asset.embedded ?? null, asset.path ?? null,
      asset.digest ?? null, asset.path && asset.digest ? Date.now() : null]);
    const id = readRows(this.db, 'SELECT last_insert_rowid()', [], row => row.getLong(0))[0];
    if (id === undefined) throw new ExpoUpdatesError('ERR_UPDATES_DATABASE', 'Unable to read inserted asset ID.');

    return id;
  }

  associate(updateId: string, assetId: number, ordinal: number): void {
    this.db.executeSync('INSERT INTO update_asset_records(update_id,asset_id,ordinal) VALUES (?,?,?) ON CONFLICT(update_id,asset_id) DO UPDATE SET ordinal=excluded.ordinal', [updateId, assetId, ordinal]);
  }

  markUnused(): void {
    this.db.executeSync('UPDATE asset_records SET marked=1');
    this.db.executeSync(`UPDATE asset_records SET marked=0 WHERE asset_id IN (SELECT r.asset_id FROM update_asset_records r JOIN update_records u ON u.id=r.update_id WHERE u.keep=1)`);
    this.db.executeSync('UPDATE asset_records SET marked=0 WHERE asset_id IN (SELECT launch_asset_id FROM update_records WHERE keep=1 AND launch_asset_id IS NOT NULL)');
    this.db.executeSync('UPDATE asset_records SET marked=0 WHERE path IN (SELECT path FROM asset_records WHERE marked=0 AND path IS NOT NULL)');
  }

  marked(): AssetEntity[] {
    return readRows(this.db, `SELECT ${assetColumns} FROM asset_records a WHERE a.marked=1`, [], assetEntity);
  }

  deleteMarked(id: number): void {
    // RDB transaction connections do not inherit the store's foreign_keys pragma.
    this.db.executeSync(`DELETE FROM update_asset_records WHERE update_id IN
      (SELECT u.id FROM update_records u JOIN asset_records a ON a.asset_id=u.launch_asset_id WHERE a.asset_id=? AND a.marked=1)`, [id]);
    this.db.executeSync('DELETE FROM update_records WHERE launch_asset_id IN (SELECT asset_id FROM asset_records WHERE asset_id=? AND marked=1)', [id]);
    this.db.executeSync('DELETE FROM update_asset_records WHERE asset_id IN (SELECT asset_id FROM asset_records WHERE asset_id=? AND marked=1)', [id]);
    this.db.executeSync('DELETE FROM asset_records WHERE asset_id=? AND marked=1', [id]);
  }
}

export class UpdatesDao {
  constructor(private readonly db: DatabaseConnection, private readonly assets: AssetsDao) {}

  private load(where: string = '', args: relationalStore.ValueType[] = []): UpdateRecord[] {
    const rows = readRows(this.db, `SELECT ${updateColumns} FROM update_records ${where}`, args, updateEntity);
    return rows.map(row => ({ ...row, assets: this.assets.forUpdate(row.id, row.launchAssetId) }));
  }

  all(scope?: string): UpdateRecord[] { return this.load(scope === undefined ? '' : 'WHERE scope=?', scope === undefined ? [] : [scope]); }
  get(id: string): UpdateRecord | undefined { return this.load('WHERE id=?', [id])[0]; }
  failed(): UpdateRecord[] { return this.load('WHERE failed>0 ORDER BY time DESC LIMIT 5'); }

  launchable(scope: string): UpdateRecord[] {
    // Upstream permits development updates without a database launch asset.
    this.db.executeSync(`UPDATE update_records SET status='pending' WHERE scope=?
      AND status IN ('ready','embedded') AND NOT EXISTS
      (SELECT 1 FROM asset_records WHERE asset_id=update_records.launch_asset_id)`, [scope]);

    return this.load("WHERE scope=? AND (successful>0 OR failed<1) AND status IN ('ready','embedded','development')", [scope]);
  }

  insert(update: UpdateRecord): void {
    this.db.executeSync(`INSERT INTO update_records(id,scope,runtime,time,status,manifest,url,headers,keep,accessed,successful,failed,launch_asset_id)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NULL)`, [update.id, update.scope, update.runtime, update.time, update.status,
      JSON.stringify(update.manifest), update.url, update.headers === null ? null : JSON.stringify(update.headers),
      update.status === 'pending' ? 0 : 1, update.accessed, update.successful, update.failed]);
  }

  setStatus(id: string, status: UpdateRecord['status']): void {
    this.db.executeSync("UPDATE update_records SET status=?,keep=CASE WHEN ?='pending' THEN keep ELSE 1 END WHERE id=?", [status, status, id]);
  }
  markFinished(id: string): void {
    this.db.executeSync('UPDATE update_records SET keep=1 WHERE id=?', [id]);
  }

  setScope(id: string, scope: string): void { this.db.executeSync('UPDATE update_records SET scope=? WHERE id=?', [scope, id]); }
  markAccessed(id: string, time: number): void { this.db.executeSync('UPDATE update_records SET accessed=? WHERE id=?', [time, id]); }
  incrementSuccessful(id: string): void { this.db.executeSync('UPDATE update_records SET successful=successful+1 WHERE id=?', [id]); }
  incrementFailed(id: string): void { this.db.executeSync('UPDATE update_records SET failed=failed+1 WHERE id=?', [id]); }

  associate(id: string, asset: UpdateAsset, ordinal: number): number {
    if (!readRows(this.db, 'SELECT 1 FROM update_records WHERE id=?', [id], () => true).length) {
      throw new ExpoUpdatesError('ERR_UPDATES_DATABASE', 'Cannot associate an asset with a missing update.');
    }

    const assetId = this.assets.save(asset);
    this.assets.associate(id, assetId, ordinal);
    if (asset.launch) this.db.executeSync('UPDATE update_records SET launch_asset_id=? WHERE id=?', [assetId, id]);

    return assetId;
  }

  markMissing(ids: number[]): void {
    if (!ids.length) return;
    const placeholders = ids.map(() => '?').join(',');
    this.db.executeSync(`UPDATE update_records SET status='pending' WHERE id IN
      (SELECT update_id FROM update_asset_records WHERE asset_id IN (${placeholders})) OR launch_asset_id IN (${placeholders})`, [...ids, ...ids]);
  }

  setCommitTime(id: string, time: number): void { this.db.executeSync('UPDATE update_records SET time=? WHERE id=?', [time, id]); }
  delete(id: string): void {
    this.db.executeSync('DELETE FROM update_asset_records WHERE update_id=?', [id]);
    this.db.executeSync('DELETE FROM update_records WHERE id=?', [id]);
  }
}

export class JSONDataDao {
  constructor(private readonly db: DatabaseConnection) {}

  get(scope: string, key: string): JSONDataEntity | undefined {
    return readRows(this.db, 'SELECT id,value,last_updated FROM json_data WHERE scope=? AND key=? ORDER BY last_updated DESC,id DESC LIMIT 1', [scope, key], row => ({
      id: row.getLong(0), scope, key, value: JSON.parse(row.getString(1)), lastUpdated: row.getLong(2),
    }))[0];
  }

  set(scope: string, key: string, value: ESObject, time: number = Date.now()): void {
    this.db.executeSync('DELETE FROM json_data WHERE scope=? AND key=?', [scope, key]);
    this.db.executeSync('INSERT INTO json_data(scope,key,value,last_updated) VALUES (?,?,?,?)', [scope, key, JSON.stringify(value), time]);
  }

  update(scope: string, key: string, body: (value: ESObject) => ESObject): ESObject {
    const value = body(this.get(scope, key)?.value ?? null);
    this.set(scope, key, value);
    return value;
  }

  consume(scope: string, key: string): ESObject {
    const value = this.get(scope, key)?.value ?? null;
    this.db.executeSync('DELETE FROM json_data WHERE scope=? AND key=?', [scope, key]);
    return value;
  }
}
