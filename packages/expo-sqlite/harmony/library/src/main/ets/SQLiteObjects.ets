/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoModuleError, ExpoSharedObject } from '@expo-harmony/expo-modules-core';
import sqlite, { DatabaseChangeEvent, NativeResult } from 'libexpo_sqlite.so';
import { OpenOptions } from './SQLiteOptions';

export interface SQLiteHost {
  complete(result: NativeResult): ESObject;
  removeConnection(connection: SQLiteConnection): void;
}

export class SQLiteConnection {
  private readonly cachePath: string | null;
  readonly localFile: string | null;
  private readonly options: OpenOptions;
  readonly host: SQLiteHost;
  readonly handle: Object;
  private refs: number = 0;
  private closed: boolean = false;

  constructor(host: SQLiteHost, path: string, file: string, localFile: string | null, options: OpenOptions, data?: Uint8Array | null) {
    this.host = host;
    this.cachePath = data == null ? path : null;
    this.localFile = localFile;
    this.options = options;

    this.handle = host.complete(sqlite.open(file, options, data ?? null)) as Object;
  }

  matches(path: string, options: OpenOptions): boolean {
    return (
      !this.closed &&
      this.refs > 0 &&
      !options.useNewConnection &&
      !this.options.useNewConnection &&
      this.cachePath === path &&
      this.options.enableChangeListener === options.enableChangeListener &&
      this.options.finalizeUnusedStatementsBeforeClosing === options.finalizeUnusedStatementsBeforeClosing &&
      this.options.libSQLUrl === options.libSQLUrl &&
      this.options.libSQLAuthToken === options.libSQLAuthToken &&
      this.options.libSQLRemoteOnly === options.libSQLRemoteOnly
    );
  }

  retain(): void {
    this.refs++;
  }

  observe(listening: boolean, callback: (event: DatabaseChangeEvent) => void): void {
    if (!this.closed) sqlite.observe(this.handle, callback, listening);
  }

  closeSync(): void {
    if (this.closed) return;

    if (this.refs > 1) {
      this.refs--;
      return;
    }

    this.host.complete(sqlite.closeSync(this.handle, this.options.finalizeUnusedStatementsBeforeClosing));
    this.didClose();
  }

  async closeAsync(): Promise<void> {
    if (this.closed) return;

    if (this.refs > 1) {
      this.refs--;
      return;
    }

    // A new open must not borrow a connection whose last close is in flight.
    this.refs = 0;

    try {
      const result = await sqlite.closeAsync(this.handle, this.options.finalizeUnusedStatementsBeforeClosing);
      if (this.closed) return;

      this.host.complete(result);
      this.didClose();
    } finally {
      if (!this.closed) this.refs = 1;
    }
  }

  release(): void {
    if (!this.closed && --this.refs === 0) this.destroy();
  }

  destroy(): void {
    if (this.closed) return;

    try {
      this.host.complete(sqlite.dispose(this.handle));
    } finally {
      this.didClose();
    }
  }

  private didClose(): void {
    this.closed = true;
    this.refs = 0;
    this.host.removeConnection(this);
  }
}

// Core requires each JS construction to have its own SharedObject identity.
export class NativeDatabase extends ExpoSharedObject {
  readonly host: SQLiteHost;
  private connection: SQLiteConnection | null;

  constructor(context: ExpoModuleContext, connection: SQLiteConnection) {
    super(context);
    this.connection = connection;
    this.host = connection.host;
    connection.retain();
  }

  get handle(): Object {
    return this.requireConnection().handle;
  }

  closeSync(): void {
    const connection = this.requireConnection();
    connection.closeSync();
    this.connection = null;
  }

  async closeAsync(): Promise<void> {
    const connection = this.requireConnection();
    this.connection = null;
    let closed = false;

    try {
      await connection.closeAsync();
      closed = true;
    } finally {
      if (!closed) this.connection = connection;
    }
  }

  override sharedObjectWillRelease(): void {
    const connection = this.connection;
    this.connection = null;
    connection?.release();
  }

  private requireConnection(): SQLiteConnection {
    if (this.connection === null) throw new ExpoModuleError('ERR_ACCESS_CLOSED_RESOURCE', 'Access to closed resource');

    return this.connection;
  }
}

export class NativeStatement extends ExpoSharedObject {
  private native: Object | null = null;
  private preparing: boolean = false;

  get handle(): Object {
    if (this.native === null) throw new ExpoModuleError('ERR_ACCESS_CLOSED_RESOURCE', 'Statement is not prepared.');

    return this.native;
  }

  prepareSync(db: NativeDatabase, source: string): void {
    this.beginPrepare();
    try {
      this.native = db.host.complete(sqlite.prepareSync(db.handle, source)) as Object;
    } finally {
      this.preparing = false;
    }
  }

  async prepareAsync(db: NativeDatabase, source: string): Promise<void> {
    this.beginPrepare();
    try {
      this.native = db.host.complete(await sqlite.prepareAsync(db.handle, source)) as Object;
    } finally {
      this.preparing = false;
    }
  }

  private beginPrepare(): void {
    if (this.preparing || this.native !== null) throw new ExpoModuleError('ERR_ACCESS_CLOSED_RESOURCE', 'Statement has already been prepared.');

    this.preparing = true;
  }

  override sharedObjectWillRelease(): void {
    // Node-API's finalizer owns sqlite3_finalize; pending tasks retain their handles.
    this.native = null;
  }
}

export class NativeSession extends ExpoSharedObject {
  private native: Object | null = null;
  private creating: boolean = false;

  get handle(): Object {
    if (this.native === null) throw new ExpoModuleError('ERR_ACCESS_CLOSED_RESOURCE', 'Session is not initialized.');

    return this.native;
  }

  createSync(db: NativeDatabase, schema: string): void {
    this.beginCreate();
    try {
      this.native = db.host.complete(sqlite.createSessionSync(db.handle, schema)) as Object;
    } finally {
      this.creating = false;
    }
  }

  async createAsync(db: NativeDatabase, schema: string): Promise<void> {
    this.beginCreate();
    try {
      this.native = db.host.complete(await sqlite.createSessionAsync(db.handle, schema)) as Object;
    } finally {
      this.creating = false;
    }
  }

  private beginCreate(): void {
    if (this.creating || this.native !== null) throw new ExpoModuleError('ERR_ACCESS_CLOSED_RESOURCE', 'Session has already been created.');

    this.creating = true;
  }

  override sharedObjectWillRelease(): void {
    this.native = null;
  }
}
