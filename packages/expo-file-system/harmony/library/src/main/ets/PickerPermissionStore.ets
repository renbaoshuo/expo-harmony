import { ExpoModuleContext } from '@expo-harmony/expo-modules-core';
import preferences from '@ohos.data.preferences';
import fileShare from '@ohos.fileshare';

interface SavedPermission {
  uri: string;
  directory: boolean;
}

/** Stores system picker URIs, never a caller-supplied path allowlist. */
export class PickerPermissionStore {
  private static readonly pendingWrites: Map<string, Promise<void>> = new Map();
  private readonly storage: preferences.Preferences;
  private readonly context: ExpoModuleContext;
  private readonly storageScope: string;

  constructor(context: ExpoModuleContext) {
    this.context = context;
    this.storageScope = context.uiAbilityContext.preferencesDir;
    this.storage = preferences.getPreferencesSync(context.uiAbilityContext, { name: 'expo_file_system_permissions' });
  }

  private readEntries(): SavedPermission[] {
    const entries: SavedPermission[] = [];
    const serialized = this.storage.getSync('pickerUris', []);
    if (!Array.isArray(serialized)) return entries;
    for (const value of serialized as string[]) {
      if (typeof value !== 'string') continue;
      try {
        const entry = JSON.parse(value) as SavedPermission;
        if (typeof entry.uri === 'string' && entry.uri.startsWith('file://') && typeof entry.directory === 'boolean') {
          entries.push({ uri: entry.uri, directory: entry.directory });
        }
      } catch (_) {
        // A malformed preference is not a grant. System permissions remain authoritative.
      }
    }
    return entries;
  }

  async remember(uri: string, directory: boolean): Promise<void> {
    // RN Hosts share this ArkTS module but own separate store instances. Merge
    // the latest Preferences value while serializing writes through flush.
    const previous = PickerPermissionStore.pendingWrites.get(this.storageScope) ?? Promise.resolve();
    const next = previous
      .catch((_: Object): void => {})
      .then(async (): Promise<void> => {
        const entries = this.readEntries();
        if (!entries.some((entry: SavedPermission): boolean => entry.uri === uri && entry.directory === directory)) {
          entries.push({ uri, directory });
        }
        this.storage.putSync(
          'pickerUris',
          entries.map((entry: SavedPermission): string => JSON.stringify(entry)),
        );
        await this.storage.flush();
      });
    PickerPermissionStore.pendingWrites.set(this.storageScope, next);
    try {
      await next;
    } finally {
      if (PickerPermissionStore.pendingWrites.get(this.storageScope) === next) {
        PickerPermissionStore.pendingWrites.delete(this.storageScope);
      }
    }
  }

  restoreActive(grant: (uri: string, directory: boolean) => void): void {
    for (const entry of this.readEntries()) {
      try {
        // The callback must successfully open the original URI through the OS.
        // This covers already-active grants before the asynchronous activation pass.
        grant(entry.uri, entry.directory);
      } catch (_) {
        // Inactive or revoked grants are handled by restore's system policy query.
      }
    }
  }

  async restore(grant: (uri: string, directory: boolean) => void): Promise<void> {
    for (const entry of this.readEntries()) {
      const policies: fileShare.PolicyInfo[] = [
        {
          uri: entry.uri,
          operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE,
        },
      ];
      try {
        const allowed = await fileShare.checkPersistentPermission(policies);
        if (allowed[0] !== true) continue;
        await fileShare.activatePermission(policies);
        // The caller reopens this original system URI and derives its current path.
        grant(entry.uri, entry.directory);
      } catch (error) {
        // An unavailable document must not prevent restoration of other grants.
        this.context.logger.warn(`Could not restore a file picker permission: ${String(error)}`);
      }
    }
  }
}
