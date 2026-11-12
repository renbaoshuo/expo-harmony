/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoRuntimePermissionsKey, ExpoModuleContext, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { bundleManager, Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';

export const READ_PERMISSION: Permissions = 'ohos.permission.READ_IMAGEVIDEO';
export const WRITE_PERMISSION: Permissions = 'ohos.permission.WRITE_IMAGEVIDEO';
const LOCATION_PERMISSION: Permissions = 'ohos.permission.MEDIA_LOCATION';
const REQUEST_REASONS_API: number = 18;
const SELF_PERMISSION_STATUS_API: number = 20;
const PREFERENCES_NAME: string = 'ExpoMediaLibraryPermissions';
const BLOCKED_KEY_PREFIX: string = 'blocked:';

enum RequestReason {
  Success = 0,
  InvalidPermission = 1,
  NotDeclared = 2,
  CannotRequest = 5,
  ManualSettings = 6,
}

export class MediaLibraryPermissionResponse {
  status: string;
  granted: boolean;
  canAskAgain: boolean;
  expires: string = 'never';
  accessPrivileges: string;

  constructor(status: string, canAskAgain: boolean) {
    this.status = status;
    this.granted = status === 'granted';
    this.canAskAgain = canAskAgain;
    this.accessPrivileges = this.granted ? 'all' : 'none';
  }
}

export class MediaLibraryPermissions {
  private static queue: Promise<void> = Promise.resolve();
  private context: ExpoModuleContext;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

  destroy(): void {
    this.destroyed = true;
  }

  ensureGranted(permissions: Permissions[]): void {
    if (!permissions.every((permission: Permissions): boolean => this.context.permissionStatus(permission) === ExpoPermissionStatus.GRANTED)) {
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_PERMISSION', 'The required HarmonyOS media library permission has not been granted. The host app must obtain approval, use an authorized signing profile, and declare the permission before requesting it from the user.');
    }
  }

  canReadLocation(): boolean {
    return this.context.permissionStatus(LOCATION_PERMISSION) === ExpoPermissionStatus.GRANTED;
  }

  async get(write: boolean): Promise<MediaLibraryPermissionResponse> {
    const permissions = this.declaredPermissions(write);
    if (permissions.length === 0) return new MediaLibraryPermissionResponse('denied', false);
    return await this.readStatus(permissions);
  }

  private declaredPermissions(write: boolean): Permissions[] {
    const bundle = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION);
    const names = bundle.reqPermissionDetails.map((detail: bundleManager.ReqPermissionDetail): string => detail.name);
    if (write) return names.includes(WRITE_PERMISSION) ? [WRITE_PERMISSION] : [];
    if (!names.includes(READ_PERMISSION)) return [];
    return names.includes(WRITE_PERMISSION) ? [READ_PERMISSION, WRITE_PERMISSION] : [READ_PERMISSION];
  }

  private async readStatus(permissions: Permissions[]): Promise<MediaLibraryPermissionResponse> {
    let undetermined: boolean = false;
    let denied: boolean = false;
    let blocked: boolean = false;

    for (const permission of permissions) {
      const system = this.context.systemPermissionStatus(permission) === ExpoPermissionStatus.GRANTED;
      if (system && deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API) {
        // Keep a known decision after a grant too, so later revocation is denied,
        // rather than being mistaken for a permission that has never been asked.
        await this.writeFlag(permission, true);
        await this.writeFlag(`${BLOCKED_KEY_PREFIX}${permission}`, false);
      }

      const history = deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API ? await this.readFlag(permission) : undefined;
      const status = this.context.permissionStatus(permission, history);
      if (status === ExpoPermissionStatus.GRANTED) continue;

      const rejected = status !== ExpoPermissionStatus.NOT_DETERMINED;
      denied = denied || rejected;
      undetermined = undetermined || !rejected;
      if (status === ExpoPermissionStatus.INVALID || status === ExpoPermissionStatus.RESTRICTED) blocked = true;
      else if (status === ExpoPermissionStatus.DENIED) {
        // API 20+ DENIED explicitly means "change in settings". Older token checks
        // report DENIED for any refusal, so keep the requestability separately.
        blocked = blocked || (deviceInfo.sdkApiVersion >= SELF_PERMISSION_STATUS_API || await this.readFlag(`${BLOCKED_KEY_PREFIX}${permission}`));
      }
    }

    return new MediaLibraryPermissionResponse(denied ? 'denied' : undetermined ? 'undetermined' : 'granted', !blocked);
  }

  async request(write: boolean): Promise<MediaLibraryPermissionResponse> {
    const result = MediaLibraryPermissions.queue.then((): Promise<MediaLibraryPermissionResponse> => this.requestOnce(write));
    MediaLibraryPermissions.queue = result.then(
      (): void => {},
      (): void => {},
    );

    return await result;
  }

  private async requestOnce(write: boolean): Promise<MediaLibraryPermissionResponse> {
    if (this.destroyed) throw new ExpoModuleError('ERR_MEDIA_LIBRARY_DESTROYED', 'The media library module has been destroyed.');

    const permissions = this.declaredPermissions(write);
    if (permissions.length === 0) {
      const required = write ? WRITE_PERMISSION : READ_PERMISSION;
      throw new ExpoModuleError('ERR_MEDIA_LIBRARY_PERMISSION_REQUEST',
        `The host app must obtain approval and declare ${required} before requesting it from the user.`);
    }

    const request = await this.context.requestPermissions(permissions);

    let restricted: boolean = false;

    for (const result of request.systemResults) {
      for (const permission of permissions) {
        const index = result.permissions.indexOf(permission);
        const reason = deviceInfo.sdkApiVersion >= REQUEST_REASONS_API ? result.errorReasons?.[index] : undefined;
        const granted = result.authResults[index] === ExpoPermissionStatus.GRANTED;

        if (
          index < 0 ||
          reason === RequestReason.InvalidPermission ||
          reason === RequestReason.NotDeclared ||
          ((reason === undefined || reason === RequestReason.Success) && !granted && result.authResults[index] !== ExpoPermissionStatus.DENIED)
        ) {
          throw new ExpoModuleError(
            'ERR_MEDIA_LIBRARY_PERMISSION_REQUEST',
            `Invalid permission result for ${permission}. Check the host app's authorized signing profile and module.json5 declarations.`,
          );
        }

        const blocked = reason === RequestReason.CannotRequest || reason === RequestReason.ManualSettings ||
          (reason === undefined && !granted && result.dialogShownResults?.[index] === false);
        if (!granted && blocked) restricted = true;

        if (!blocked && reason !== undefined && reason !== RequestReason.Success) {
          throw new ExpoModuleError('ERR_MEDIA_LIBRARY_PERMISSION_REQUEST', `The system could not request ${permission} (reason ${reason}).`);
        }

        if (deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API) {
          await this.writeFlag(permission, true);
          await this.writeFlag(`${BLOCKED_KEY_PREFIX}${permission}`, !granted && blocked);
        }
      }
    }

    const response = await this.readStatus(permissions);

    if (this.context.services.get(ExpoRuntimePermissionsKey) !== undefined) {
      return restricted && !response.granted ? new MediaLibraryPermissionResponse('denied', false) : response;
    }

    return response.granted ? response : new MediaLibraryPermissionResponse('denied', response.canAskAgain && !restricted);
  }

  private async readFlag(key: string): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });
      return (await store.get(key, false)) === true;
    } catch (_) {
      return false;
    }
  }

  private async writeFlag(key: string, value: boolean): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });
      if ((await store.get(key, false)) === value) return;

      await store.put(key, value);
      await store.flush();
    } catch (_) {
      // API 13–19 have no permission-history or requestability query. When history
      // cannot be persisted, keep canAskAgain true until the system reports a block.
    }
  }
}
