/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoSharedObjectClassDefinition,
  ExpoValueTypes,
  filePathFromUri,
} from '@expo-harmony/expo-modules-core';
import fs from '@ohos.file.fs';
import { BusinessError } from '@kit.BasicServicesKit';
import sqlite, { BindValue, DatabaseChangeEvent, NativeResult } from 'libexpo_sqlite.so';
import { BIND_VALUE, OPEN_OPTIONS, OpenOptions } from './SQLiteOptions';
import { NativeDatabase, NativeSession, NativeStatement, SQLiteHost } from './SQLiteObjects';

const MEMORY_DATABASE = ':memory:';
const FILE_NOT_FOUND = 13900002;
const FILE_ALREADY_EXISTS = 13900015;

export class ExpoSQLiteModule extends ExpoModule implements SQLiteHost {
  private databases: NativeDatabase[] = [];
  private importing: Set<string> = new Set<string>();
  private destroyed: boolean = false;
  private hasListeners: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  complete(result: NativeResult): ESObject {
    if (result.error.length > 0) throw new ExpoModuleError(result.errorCode, result.error);

    return result.value;
  }

  removeDatabase(database: NativeDatabase): void {
    const index = this.databases.indexOf(database);
    if (index !== -1) this.databases.splice(index, 1);
  }

  definition(): ExpoModuleDefinition {
    const database = new ExpoSharedObjectClassDefinition<NativeDatabase>('NativeDatabase');
    const statement = new ExpoSharedObjectClassDefinition<NativeStatement>('NativeStatement');
    const session = new ExpoSharedObjectClassDefinition<NativeSession>('NativeSession');
    const dbType = database.valueType();
    const statementType = statement.valueType();
    const sessionType = session.valueType();
    const stringType = ExpoValueTypes.string();
    const bytesType = ExpoValueTypes.uint8Array();
    const bufferType = ExpoValueTypes.arrayBuffer();
    const boolType = ExpoValueTypes.boolean();

    database.construct(
      ExpoFunction.ownedTyped3(
        stringType,
        OPEN_OPTIONS.optional(),
        bytesType.nullable().optional(),
        (context: ExpoModuleContext, path: string, options?: OpenOptions, bytes?: Uint8Array | null): NativeDatabase =>
          this.openDatabase(context, path, options ?? new OpenOptions(), bytes),
      ),
    );
    statement.construct((context: ExpoModuleContext): NativeStatement => new NativeStatement(context));
    session.construct((context: ExpoModuleContext): NativeSession => new NativeSession(context));
    database.syncFunction(
      'initSync',
      ExpoFunction.ownedTyped0((db: NativeDatabase): void => {
        this.complete(sqlite.initSync(db.handle));
      }),
    );
    database.asyncFunction(
      'initAsync',
      ExpoFunction.ownedTyped0(async (db: NativeDatabase): Promise<void> => {
        this.complete(await sqlite.initAsync(db.handle));
      }),
    );
    database.syncFunction(
      'isInTransactionSync',
      ExpoFunction.ownedTyped0((db: NativeDatabase): ESObject => {
        return this.complete(sqlite.isInTransactionSync(db.handle));
      }),
    );
    database.asyncFunction(
      'isInTransactionAsync',
      ExpoFunction.ownedTyped0(async (db: NativeDatabase): Promise<ESObject> => {
        return this.complete(await sqlite.isInTransactionAsync(db.handle));
      }),
    );
    database.syncFunction(
      'execSync',
      ExpoFunction.ownedTyped1(stringType, (db: NativeDatabase, source: string): void => {
        this.complete(sqlite.execSync(db.handle, source));
      }),
    );
    database.asyncFunction(
      'execAsync',
      ExpoFunction.ownedTyped1(stringType, async (db: NativeDatabase, source: string): Promise<void> => {
        this.complete(await sqlite.execAsync(db.handle, source));
      }),
    );
    database.syncFunction(
      'serializeSync',
      ExpoFunction.ownedTyped1(stringType, (db: NativeDatabase, schema: string): ESObject => {
        return this.complete(sqlite.serializeSync(db.handle, schema));
      }),
    );
    database.asyncFunction(
      'serializeAsync',
      ExpoFunction.ownedTyped1(stringType, async (db: NativeDatabase, schema: string): Promise<ESObject> => {
        return this.complete(await sqlite.serializeAsync(db.handle, schema));
      }),
    );
    database.syncFunction(
      'loadExtensionSync',
      ExpoFunction.ownedTyped2(stringType, stringType.nullable().optional(), (db: NativeDatabase, path: string, entry?: string | null): void => {
        this.complete(sqlite.loadExtensionSync(db.handle, path, entry ?? null));
      }),
    );
    database.asyncFunction(
      'loadExtensionAsync',
      ExpoFunction.ownedTyped2(
        stringType,
        stringType.nullable().optional(),
        async (db: NativeDatabase, path: string, entry?: string | null): Promise<void> => {
          this.complete(await sqlite.loadExtensionAsync(db.handle, path, entry ?? null));
        },
      ),
    );
    database.syncFunction(
      'closeSync',
      ExpoFunction.ownedTyped0((db: NativeDatabase): void => {
        db.closeSync();
      }),
    );
    database.asyncFunction(
      'closeAsync',
      ExpoFunction.ownedTyped0(async (db: NativeDatabase): Promise<void> => {
        await db.closeAsync();
      }),
    );
    database.syncFunction(
      'prepareSync',
      ExpoFunction.ownedTyped2(statementType, stringType, (db: NativeDatabase, stmt: NativeStatement, source: string): void => {
        stmt.prepareSync(db, source);
      }),
    );
    database.asyncFunction(
      'prepareAsync',
      ExpoFunction.ownedTyped2(statementType, stringType, async (db: NativeDatabase, stmt: NativeStatement, source: string): Promise<void> => {
        await stmt.prepareAsync(db, source);
      }),
    );
    database.syncFunction(
      'createSessionSync',
      ExpoFunction.ownedTyped2(sessionType, stringType, (db: NativeDatabase, value: NativeSession, schema: string): void => {
        value.createSync(db, schema);
      }),
    );
    database.asyncFunction(
      'createSessionAsync',
      ExpoFunction.ownedTyped2(sessionType, stringType, async (db: NativeDatabase, value: NativeSession, schema: string): Promise<void> => {
        await value.createAsync(db, schema);
      }),
    );
    database.asyncFunction(
      'syncLibSQL',
      ExpoFunction.ownedTyped0(async (db: NativeDatabase): Promise<void> => {
        this.complete(await sqlite.syncLibSQL(db.handle));
      }),
    );
    statement.syncFunction(
      'runSync',
      ExpoFunction.ownedTyped4(
        dbType,
        ExpoValueTypes.record(BIND_VALUE),
        ExpoValueTypes.record(bufferType),
        boolType,
        (
          stmt: NativeStatement,
          db: NativeDatabase,
          params: Record<string, BindValue>,
          blobs: Record<string, ArrayBuffer>,
          array: boolean,
        ): ESObject => {
          return this.complete(sqlite.runSync(stmt.handle, db.handle, params, blobs, array));
        },
      ),
    );
    statement.asyncFunction(
      'runAsync',
      ExpoFunction.ownedTyped4(
        dbType,
        ExpoValueTypes.record(BIND_VALUE),
        ExpoValueTypes.record(bufferType),
        boolType,
        async (
          stmt: NativeStatement,
          db: NativeDatabase,
          params: Record<string, BindValue>,
          blobs: Record<string, ArrayBuffer>,
          array: boolean,
        ): Promise<ESObject> => {
          return this.complete(await sqlite.runAsync(stmt.handle, db.handle, params, blobs, array));
        },
      ),
    );
    statement.syncFunction(
      'stepSync',
      ExpoFunction.ownedTyped1(dbType, (stmt: NativeStatement, db: NativeDatabase): ESObject => {
        return this.complete(sqlite.stepSync(stmt.handle, db.handle));
      }),
    );
    statement.asyncFunction(
      'stepAsync',
      ExpoFunction.ownedTyped1(dbType, async (stmt: NativeStatement, db: NativeDatabase): Promise<ESObject> => {
        return this.complete(await sqlite.stepAsync(stmt.handle, db.handle));
      }),
    );
    statement.syncFunction(
      'getAllSync',
      ExpoFunction.ownedTyped1(dbType, (stmt: NativeStatement, db: NativeDatabase): ESObject => {
        return this.complete(sqlite.getAllSync(stmt.handle, db.handle));
      }),
    );
    statement.asyncFunction(
      'getAllAsync',
      ExpoFunction.ownedTyped1(dbType, async (stmt: NativeStatement, db: NativeDatabase): Promise<ESObject> => {
        return this.complete(await sqlite.getAllAsync(stmt.handle, db.handle));
      }),
    );
    statement.syncFunction(
      'resetSync',
      ExpoFunction.ownedTyped1(dbType, (stmt: NativeStatement, db: NativeDatabase): void => {
        this.complete(sqlite.resetSync(stmt.handle, db.handle));
      }),
    );
    statement.asyncFunction(
      'resetAsync',
      ExpoFunction.ownedTyped1(dbType, async (stmt: NativeStatement, db: NativeDatabase): Promise<void> => {
        this.complete(await sqlite.resetAsync(stmt.handle, db.handle));
      }),
    );
    statement.syncFunction(
      'finalizeSync',
      ExpoFunction.ownedTyped1(dbType, (stmt: NativeStatement, db: NativeDatabase): void => {
        this.complete(sqlite.finalizeSync(stmt.handle, db.handle));
      }),
    );
    statement.asyncFunction(
      'finalizeAsync',
      ExpoFunction.ownedTyped1(dbType, async (stmt: NativeStatement, db: NativeDatabase): Promise<void> => {
        this.complete(await sqlite.finalizeAsync(stmt.handle, db.handle));
      }),
    );
    statement.syncFunction(
      'getColumnNamesSync',
      ExpoFunction.ownedTyped0((stmt: NativeStatement): ESObject => {
        return this.complete(sqlite.getColumnNamesSync(stmt.handle));
      }),
    );
    statement.asyncFunction(
      'getColumnNamesAsync',
      ExpoFunction.ownedTyped0(async (stmt: NativeStatement): Promise<ESObject> => {
        return this.complete(await sqlite.getColumnNamesAsync(stmt.handle));
      }),
    );
    session.syncFunction(
      'attachSync',
      ExpoFunction.ownedTyped2(dbType, stringType.nullable(), (value: NativeSession, db: NativeDatabase, table: string | null): void => {
        this.complete(sqlite.attachSync(value.handle, db.handle, table));
      }),
    );
    session.asyncFunction(
      'attachAsync',
      ExpoFunction.ownedTyped2(
        dbType,
        stringType.nullable(),
        async (value: NativeSession, db: NativeDatabase, table: string | null): Promise<void> => {
          this.complete(await sqlite.attachAsync(value.handle, db.handle, table));
        },
      ),
    );
    session.syncFunction(
      'enableSync',
      ExpoFunction.ownedTyped2(dbType, boolType, (value: NativeSession, db: NativeDatabase, enabled: boolean): void => {
        this.complete(sqlite.enableSync(value.handle, db.handle, enabled));
      }),
    );
    session.asyncFunction(
      'enableAsync',
      ExpoFunction.ownedTyped2(dbType, boolType, async (value: NativeSession, db: NativeDatabase, enabled: boolean): Promise<void> => {
        this.complete(await sqlite.enableAsync(value.handle, db.handle, enabled));
      }),
    );
    session.syncFunction(
      'closeSync',
      ExpoFunction.ownedTyped1(dbType, (value: NativeSession, db: NativeDatabase): void => {
        this.complete(sqlite.closeSessionSync(value.handle, db.handle));
      }),
    );
    session.asyncFunction(
      'closeAsync',
      ExpoFunction.ownedTyped1(dbType, async (value: NativeSession, db: NativeDatabase): Promise<void> => {
        this.complete(await sqlite.closeSessionAsync(value.handle, db.handle));
      }),
    );
    session.syncFunction(
      'createChangesetSync',
      ExpoFunction.ownedTyped1(dbType, (value: NativeSession, db: NativeDatabase): ESObject => {
        return this.complete(sqlite.createChangesetSync(value.handle, db.handle));
      }),
    );
    session.asyncFunction(
      'createChangesetAsync',
      ExpoFunction.ownedTyped1(dbType, async (value: NativeSession, db: NativeDatabase): Promise<ESObject> => {
        return this.complete(await sqlite.createChangesetAsync(value.handle, db.handle));
      }),
    );
    session.syncFunction(
      'createInvertedChangesetSync',
      ExpoFunction.ownedTyped1(dbType, (value: NativeSession, db: NativeDatabase): ESObject => {
        return this.complete(sqlite.createInvertedChangesetSync(value.handle, db.handle));
      }),
    );
    session.asyncFunction(
      'createInvertedChangesetAsync',
      ExpoFunction.ownedTyped1(dbType, async (value: NativeSession, db: NativeDatabase): Promise<ESObject> => {
        return this.complete(await sqlite.createInvertedChangesetAsync(value.handle, db.handle));
      }),
    );
    session.syncFunction(
      'applyChangesetSync',
      ExpoFunction.ownedTyped2(dbType, bufferType, (value: NativeSession, db: NativeDatabase, changeset: ArrayBuffer): void => {
        this.complete(sqlite.applyChangesetSync(value.handle, db.handle, changeset));
      }),
    );
    session.asyncFunction(
      'applyChangesetAsync',
      ExpoFunction.ownedTyped2(dbType, bufferType, async (value: NativeSession, db: NativeDatabase, changeset: ArrayBuffer): Promise<void> => {
        this.complete(await sqlite.applyChangesetAsync(value.handle, db.handle, changeset));
      }),
    );
    session.syncFunction(
      'invertChangesetSync',
      ExpoFunction.ownedTyped2(dbType, bufferType, (value: NativeSession, db: NativeDatabase, changeset: ArrayBuffer): ESObject => {
        return this.complete(sqlite.invertChangesetSync(value.handle, db.handle, changeset));
      }),
    );
    session.asyncFunction(
      'invertChangesetAsync',
      ExpoFunction.ownedTyped2(dbType, bufferType, async (value: NativeSession, db: NativeDatabase, changeset: ArrayBuffer): Promise<ESObject> => {
        return this.complete(await sqlite.invertChangesetAsync(value.handle, db.handle, changeset));
      }),
    );

    const definition = new ExpoModuleDefinition()
      .name('ExpoSQLite')
      .constant('defaultDatabaseDirectory', (): string => `${filePathFromUri(this.context.persistentFilesDirectory).replace(/\/$/, '')}/SQLite`)
      .constant('bundledExtensions', (): Record<string, Object> => sqlite.bundledExtensions)
      .events(['onDatabaseChange'])
      .onStartObserving((): void => this.setObserving(true))
      .onStopObserving((): void => this.setObserving(false))
      .sharedObjectClass(database)
      .sharedObjectClass(statement)
      .sharedObjectClass(session)
      .onDestroy((): void => {
        this.setObserving(false);
        this.destroyed = true;
        for (const db of this.databases.slice()) db.destroy();
      });
    definition.syncFunction(
      'backupDatabaseSync',
      ExpoFunction.typed4(
        dbType,
        stringType,
        dbType,
        stringType,
        (destination: NativeDatabase, destinationSchema: string, source: NativeDatabase, sourceSchema: string): void => {
          this.complete(sqlite.backupSync(destination.handle, destinationSchema, source.handle, sourceSchema));
        },
      ),
    );
    definition.syncFunction(
      'ensureDatabasePathExistsSync',
      ExpoFunction.typed1(stringType, (path: string): void => {
        this.ensurePathSync(localPath(path));
      }),
    );
    definition.syncFunction(
      'deleteDatabaseSync',
      ExpoFunction.typed1(stringType, (path: string): void => {
        this.deleteDatabaseSync(path);
      }),
    );
    definition.asyncFunction(
      'backupDatabaseAsync',
      ExpoFunction.typed4(
        dbType,
        stringType,
        dbType,
        stringType,
        async (destination: NativeDatabase, destinationSchema: string, source: NativeDatabase, sourceSchema: string): Promise<void> => {
          this.complete(await sqlite.backupAsync(destination.handle, destinationSchema, source.handle, sourceSchema));
        },
      ),
    );
    definition.asyncFunction(
      'ensureDatabasePathExistsAsync',
      ExpoFunction.typed1(stringType, async (path: string): Promise<void> => {
        await this.ensurePathAsync(localPath(path));
      }),
    );
    definition.asyncFunction(
      'deleteDatabaseAsync',
      ExpoFunction.typed1(stringType, async (path: string): Promise<void> => {
        await this.deleteDatabaseAsync(path);
      }),
    );
    definition.asyncFunction(
      'importAssetDatabaseAsync',
      ExpoFunction.typed3(stringType, stringType, boolType, async (path: string, asset: string, overwrite: boolean): Promise<void> => {
        await this.importDatabase(localPath(path), localPath(asset), overwrite);
      }),
    );

    return definition;
  }

  private openDatabase(context: ExpoModuleContext, path: string, options: OpenOptions, bytes?: Uint8Array | null): NativeDatabase {
    const file = localPath(path);
    if (this.destroyed) {
      throw new ExpoModuleError('E_SQLITE_OPEN_DATABASE', 'Database module is destroyed.');
    }

    const localFile = bytes == null && file !== MEMORY_DATABASE && (!sqlite.useLibSQL || !options.libSQLRemoteOnly)
      ? fileIdentity(file)
      : null;
    if (localFile !== null && this.importing.has(localFile)) {
      throw new ExpoModuleError('E_SQLITE_OPEN_DATABASE', `Cannot open a database while importing it: ${path}`);
    }

    if (bytes == null) {
      for (const db of this.databases) {
        if (db.matches(path, options)) {
          db.retain();

          return db;
        }
      }

      if (!sqlite.useLibSQL || !options.libSQLRemoteOnly) this.ensurePathSync(file);
    }

    const db = new NativeDatabase(context, this, path, file, localFile, options, bytes);
    this.observeDatabase(db);
    this.databases.push(db);

    return db;
  }

  private ensurePathSync(path: string): void {
    if (path === MEMORY_DATABASE) return;

    const directory = parentDirectory(path);

    try {
      fs.mkdirSync(directory, true);
    } catch (error) {
      const failure = error as BusinessError;
      if (failure.code === FILE_ALREADY_EXISTS) {
        try {
          if (fs.statSync(directory).isDirectory()) return;
        } catch (_) {}
      }

      throw new ExpoModuleError('E_SQLITE_INVALID_PATH', failure.message);
    }
  }

  private async ensurePathAsync(path: string): Promise<void> {
    if (path === MEMORY_DATABASE) return;

    const directory = parentDirectory(path);

    try {
      await fs.mkdir(directory, true);
    } catch (error) {
      const failure = error as BusinessError;
      if (failure.code === FILE_ALREADY_EXISTS) {
        try {
          if ((await fs.stat(directory)).isDirectory()) return;
        } catch (_) {}
      }

      throw new ExpoModuleError('E_SQLITE_INVALID_PATH', failure.message);
    }
  }

  private assertFileIdle(path: string, identity: string, errorCode: string): void {
    if (this.importing.has(identity)) {
      throw new ExpoModuleError(errorCode, `Database import is in progress: ${path}`);
    }
    // Connections remain here through an async close and after a failed close.
    if (this.databases.some((db: NativeDatabase): boolean => db.localFile === identity)) {
      throw new ExpoModuleError(errorCode, `Database is open: ${path}`);
    }
  }

  private deleteDatabaseSync(source: string): void {
    const path = localPath(source);
    if (path === MEMORY_DATABASE) return;

    this.ensurePathSync(path);
    this.unlinkDatabase(path);
  }

  private async deleteDatabaseAsync(source: string): Promise<void> {
    const path = localPath(source);
    if (path === MEMORY_DATABASE) return;

    await this.ensurePathAsync(path);
    this.unlinkDatabase(path);
  }

  private unlinkDatabase(path: string): void {
    // Keep the open check and unlink in the same JS turn.
    this.assertFileIdle(path, fileIdentity(path), 'E_SQLITE_DELETE_DATABASE');
    try {
      fs.unlinkSync(path);
    } catch (error) {
      if ((error as BusinessError).code === FILE_NOT_FOUND) {
        throw new ExpoModuleError('E_SQLITE_DELETE_DATABASE', `Database ${path} not found`);
      }
      throw new ExpoModuleError('E_SQLITE_DELETE_DATABASE', `Unable to delete the database file for ${path}`);
    }
  }

  private async importDatabase(path: string, asset: string, overwrite: boolean): Promise<void> {
    if (path === MEMORY_DATABASE || asset === MEMORY_DATABASE) {
      throw new ExpoModuleError('E_SQLITE_INVALID_PATH', 'Asset import requires file-backed database paths.');
    }

    if (!overwrite && databaseFileExists(path)) return;

    const identity = fileIdentity(path);
    this.assertFileIdle(path, identity, 'E_SQLITE_OPEN_DATABASE');

    this.importing.add(identity);

    let directory: string | null = null;
    let temp: string | null = null;

    try {
      await this.ensurePathAsync(path);

      let regular: boolean;
      try {
        regular = (await fs.stat(asset)).isFile();
      } catch (error) {
        throw new ExpoModuleError('E_SQLITE_OPEN_DATABASE', (error as BusinessError).message);
      }
      if (!regular) {
        throw new ExpoModuleError('E_SQLITE_OPEN_DATABASE', `Asset database is not a regular file: ${asset}`);
      }

      directory = await fs.mkdtemp(`${parentDirectory(path)}/.expo-sqlite-`);
      temp = `${directory}/database`;
      assertStandaloneDatabaseFile(asset);

      await fs.copyFile(asset, temp);

      // Publish only after a complete copy. Check again for files created
      // by another module while copying.
      if (overwrite || !databaseFileExists(path)) {
        assertStandaloneDatabaseFile(asset);
        assertStandaloneDatabaseFile(path);

        fs.renameSync(temp, path);
        temp = null;
      }
    } finally {
      if (temp !== null) {
        try { fs.unlinkSync(temp); } catch (_) {}
      }
      if (directory !== null) {
        try { fs.rmdirSync(directory); } catch (_) {}
      }
      this.importing.delete(identity);
    }
  }

  private observeDatabase(db: NativeDatabase): void {
    sqlite.observe(
      db.handle,
      (event: DatabaseChangeEvent): void => {
        if (!this.destroyed) this.sendEvent('onDatabaseChange', event);
      },
      this.hasListeners,
    );
  }

  private setObserving(observing: boolean): void {
    this.hasListeners = observing;

    for (const db of this.databases)
      db.observe(observing, (event: DatabaseChangeEvent): void => {
        if (!this.destroyed) this.sendEvent('onDatabaseChange', event);
      });
  }
}

function localPath(path: string): string {
  if (path === MEMORY_DATABASE) return path;

  try {
    const resolved = path.startsWith('file:') ? filePathFromUri(path) : path;
    if (resolved.length && !resolved.includes('\0') && !resolved.includes('://')) return resolved;
  } catch (_) {}

  throw new ExpoModuleError('E_SQLITE_INVALID_PATH', `Invalid database path: ${path}`);
}

function parentDirectory(path: string): string {
  const slash = path.lastIndexOf('/');
  return slash < 0 ? '.' : path.substring(0, slash) || '/';
}

function fileIdentity(path: string): string {
  const absolute = path.startsWith('/');
  const segments: string[] = [];
  for (const part of path.split('/')) {
    if (!part.length || part === '.') continue;
    if (part === '..' && segments.length && segments[segments.length - 1] !== '..') {
      segments.pop();
    } else if (part !== '..' || !absolute) {
      segments.push(part);
    }
  }

  return (absolute ? '/' : '') + segments.join('/');
}

function databaseFileExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (error) {
    const failure = error as BusinessError;
    if (failure.code === FILE_NOT_FOUND) return false;
    throw new ExpoModuleError('E_SQLITE_OPEN_DATABASE', failure.message);
  }
}

function assertStandaloneDatabaseFile(path: string): void {
  // A journal belongs to the original main file. Copying only the asset's
  // main file or leaving a destination journal in place can replay stale pages.
  for (const suffix of ['-journal', '-wal']) {
    if (databaseFileExists(path + suffix)) {
      throw new ExpoModuleError('E_SQLITE_OPEN_DATABASE', `Cannot import a database while its recovery file exists: ${path}${suffix}`);
    }
  }
}
