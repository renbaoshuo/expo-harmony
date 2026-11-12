/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import preferences from '@ohos.data.preferences';
import fileShare from '@ohos.fileshare';

interface SavedPermission {
  uri: string;
  directory: boolean;
  writable: boolean;
}

/** Stores system picker URIs, never a caller-supplied path allowlist. */
export class PickerPermissionStore {
  private static readonly pendingWrites: Map<string, Promise<void>> = new Map();
  private readonly context: ExpoModuleContext;

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

  private canPersist(): boolean {
    if (!canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) return false;
    try {
      return this.context.permissionStatus('ohos.permission.FILE_ACCESS_PERSIST') === ExpoPermissionStatus.GRANTED;
    } catch (_) {
      return false;
    }
  }

  private getStorage(name: string = this.context.preferenceName('expo_file_system_permissions')): preferences.Preferences {
    return preferences.getPreferencesSync(this.context.uiAbilityContext, { name });
  }

  private readEntries(storage: preferences.Preferences): SavedPermission[] {
    const entries: SavedPermission[] = [];
    const serialized = storage.getSync('pickerUris', []);
    if (!Array.isArray(serialized)) return entries;

    for (const value of serialized as string[]) {
      if (typeof value !== 'string') continue;
      try {
        const entry = JSON.parse(value) as SavedPermission;
        if (typeof entry.uri === 'string' && entry.uri.startsWith('file://') && typeof entry.directory === 'boolean') {
          // Existing stores used read/write policies without a mode field.
          entries.push({ uri: entry.uri, directory: entry.directory, writable: entry.writable !== false });
        }
      } catch (_) {
        // A malformed preference is not a grant. System permissions remain authoritative.
      }
    }

    return entries;
  }

  async remember(uri: string, directory: boolean, writable: boolean): Promise<void> {
    if (!this.canPersist()) return;

    const name = this.context.preferenceName('expo_file_system_permissions');
    const scope = `${this.context.uiAbilityContext.preferencesDir}/${name}`;
    const storage = this.getStorage(name);
    // RN Hosts share this ArkTS module but own separate store instances. Merge
    // the latest Preferences value while serializing writes through flush.
    const previous = PickerPermissionStore.pendingWrites.get(scope) ?? Promise.resolve();
    const next = previous
      .catch((_: Object): void => {})
      .then(async (): Promise<void> => {
        if (!this.canPersist()) return;

        const entries = this.readEntries(storage);
        const policy: fileShare.PolicyInfo = { uri, operationMode: operationMode(writable) };
        // The picker already granted access for this session. Activation is
        // only needed when reopening a persisted grant after a restart.
        try {
          await fileShare.persistPermission([policy]);
        } catch (_) {
          // Some providers allow temporary access only.
          return;
        }

        const existing = entries.find((entry: SavedPermission): boolean => entry.uri === uri && entry.directory === directory);
        if (existing === undefined) entries.push({ uri, directory, writable });
        else existing.writable = existing.writable || writable;

        storage.putSync(
          'pickerUris',
          entries.map((entry: SavedPermission): string => JSON.stringify(entry)),
        );
        await storage.flush();
      });
    PickerPermissionStore.pendingWrites.set(scope, next);
    try {
      await next;
    } finally {
      if (PickerPermissionStore.pendingWrites.get(scope) === next) {
        PickerPermissionStore.pendingWrites.delete(scope);
      }
    }
  }

  restoreActive(grant: (uri: string, directory: boolean, writable: boolean) => void): void {
    if (!this.canPersist()) return;

    let entries: SavedPermission[];

    try {
      entries = this.readEntries(this.getStorage());
    } catch (_) {
      // A preference failure must not disable the normal file system APIs.
      return;
    }

    for (const entry of entries) {
      try {
        // The callback must successfully open the original URI through the OS.
        // This covers already-active grants before the asynchronous activation pass.
        grant(entry.uri, entry.directory, entry.writable);
      } catch (_) {
        // Inactive or revoked grants are handled by restore's system policy query.
      }
    }
  }

  async restore(grant: (uri: string, directory: boolean, writable: boolean) => void): Promise<void> {
    if (!this.canPersist()) return;

    for (const entry of this.readEntries(this.getStorage())) {
      if (!this.context.isValid) return;
      const policies: fileShare.PolicyInfo[] = [
        {
          uri: entry.uri,
          operationMode: operationMode(entry.writable),
        },
      ];

      try {
        const allowed = await fileShare.checkPersistentPermission(policies);
        if (allowed[0] !== true || !this.context.isValid) continue;
        await fileShare.activatePermission(policies);
        if (this.context.isValid) grant(entry.uri, entry.directory, entry.writable);
      } catch (error) {
        if (this.context.isValid) this.context.logger.warn(`Could not restore a file picker permission: ${String(error)}`);
      }
    }
  }
}

function operationMode(writable: boolean): number {
  return writable ? fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE : fileShare.OperationMode.READ_MODE;
}
