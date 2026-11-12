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
  removeDatabase(db: NativeDatabase): void;
}

export class NativeDatabase extends ExpoSharedObject {
  readonly path: string;
  readonly localFile: string | null;
  readonly options: OpenOptions;
  readonly host: SQLiteHost;
  private readonly native: Object;
  private refs: number = 1;
  private closed: boolean = false;

  constructor(context: ExpoModuleContext, host: SQLiteHost, path: string, file: string, localFile: string | null, options: OpenOptions, data?: Uint8Array | null) {
    super(context);

    this.host = host;
    this.path = path;
    this.localFile = localFile;
    this.options = options;

    this.native = host.complete(sqlite.open(file, options, data ?? null)) as Object;
  }

  get handle(): Object {
    if (this.closed) throw new ExpoModuleError('ERR_ACCESS_CLOSED_RESOURCE', 'Access to closed resource');

    return this.native;
  }

  matches(path: string, options: OpenOptions): boolean {
    return (
      !this.closed &&
      this.refs > 0 &&
      !options.useNewConnection &&
      !this.options.useNewConnection &&
      this.path === path &&
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
    if (!this.closed) sqlite.observe(this.native, callback, listening);
  }

  closeSync(): void {
    const handle = this.handle;
    if (this.refs === 0 || --this.refs > 0) return;

    // A failed close must still consume the final cache reference, as on Android.
    this.host.complete(sqlite.closeSync(handle, this.options.finalizeUnusedStatementsBeforeClosing));
    this.didClose();
  }

  async closeAsync(): Promise<void> {
    const handle = this.handle;
    if (this.refs === 0 || --this.refs > 0) return;

    const result = await sqlite.closeAsync(handle, this.options.finalizeUnusedStatementsBeforeClosing);
    if (this.closed) return;

    this.host.complete(result);
    this.didClose();
  }

  destroy(): void {
    if (this.closed) return;

    this.host.complete(sqlite.dispose(this.native));
    this.didClose();
  }

  private didClose(): void {
    this.closed = true;
    this.refs = 0;
    this.host.removeDatabase(this);
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
