/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

declare module 'libexpo_sqlite.so' {
  export type BindValue = string | number | boolean | null;
  export interface DatabaseChangeEvent {
    databaseName: string;
    databaseFilePath: string;
    tableName: string;
    rowId: number;
    typeId: string;
  }
  export interface NativeResult {
    value: Object | null;
    errorCode: string;
    error: string;
  }
  export interface NativeOpenOptions {
    enableChangeListener: boolean;
    libSQLUrl: string | null;
    libSQLAuthToken: string | null;
    libSQLRemoteOnly: boolean;
  }
  declare const sqlite: {
    readonly bundledExtensions: Record<string, Object>;
    readonly useLibSQL: boolean;
    observe(database: Object, callback: (event: DatabaseChangeEvent) => void, listening: boolean): void;
    syncLibSQL(database: Object): Promise<NativeResult>;
    open(path: string, options: NativeOpenOptions, serialized: Uint8Array | null): NativeResult;
    dispose(database: Object): NativeResult;
    initSync(database: Object): NativeResult;
    initAsync(database: Object): Promise<NativeResult>;
    closeSync(database: Object, finalizeStatements: boolean): NativeResult;
    closeAsync(database: Object, finalizeStatements: boolean): Promise<NativeResult>;
    execSync(database: Object, source: string): NativeResult;
    execAsync(database: Object, source: string): Promise<NativeResult>;
    isInTransactionSync(database: Object): NativeResult;
    isInTransactionAsync(database: Object): Promise<NativeResult>;
    serializeSync(database: Object, schema: string): NativeResult;
    serializeAsync(database: Object, schema: string): Promise<NativeResult>;
    prepareSync(database: Object, source: string): NativeResult;
    prepareAsync(database: Object, source: string): Promise<NativeResult>;
    createSessionSync(database: Object, schema: string): NativeResult;
    createSessionAsync(database: Object, schema: string): Promise<NativeResult>;
    loadExtensionSync(database: Object, path: string, entry: string | null): NativeResult;
    loadExtensionAsync(database: Object, path: string, entry: string | null): Promise<NativeResult>;
    backupSync(destination: Object, destinationSchema: string, source: Object, sourceSchema: string): NativeResult;
    backupAsync(destination: Object, destinationSchema: string, source: Object, sourceSchema: string): Promise<NativeResult>;
    runSync(statement: Object, database: Object, params: Record<string, BindValue>, blobs: Record<string, ArrayBuffer>, array: boolean): NativeResult;
    runAsync(statement: Object, database: Object, params: Record<string, BindValue>, blobs: Record<string, ArrayBuffer>, array: boolean): Promise<NativeResult>;
    stepSync(statement: Object, database: Object): NativeResult;
    stepAsync(statement: Object, database: Object): Promise<NativeResult>;
    getAllSync(statement: Object, database: Object): NativeResult;
    getAllAsync(statement: Object, database: Object): Promise<NativeResult>;
    resetSync(statement: Object, database: Object): NativeResult;
    resetAsync(statement: Object, database: Object): Promise<NativeResult>;
    getColumnNamesSync(statement: Object): NativeResult;
    getColumnNamesAsync(statement: Object): Promise<NativeResult>;
    finalizeSync(statement: Object, database: Object): NativeResult;
    finalizeAsync(statement: Object, database: Object): Promise<NativeResult>;
    attachSync(session: Object, database: Object, table: string | null): NativeResult;
    attachAsync(session: Object, database: Object, table: string | null): Promise<NativeResult>;
    enableSync(session: Object, database: Object, enabled: boolean): NativeResult;
    enableAsync(session: Object, database: Object, enabled: boolean): Promise<NativeResult>;
    closeSessionSync(session: Object, database: Object): NativeResult;
    closeSessionAsync(session: Object, database: Object): Promise<NativeResult>;
    createChangesetSync(session: Object, database: Object): NativeResult;
    createChangesetAsync(session: Object, database: Object): Promise<NativeResult>;
    createInvertedChangesetSync(session: Object, database: Object): NativeResult;
    createInvertedChangesetAsync(session: Object, database: Object): Promise<NativeResult>;
    applyChangesetSync(session: Object, database: Object, changeset: ArrayBuffer): NativeResult;
    applyChangesetAsync(session: Object, database: Object, changeset: ArrayBuffer): Promise<NativeResult>;
    invertChangesetSync(session: Object, database: Object, changeset: ArrayBuffer): NativeResult;
    invertChangesetAsync(session: Object, database: Object, changeset: ArrayBuffer): Promise<NativeResult>;
  };
  export default sqlite;
}
