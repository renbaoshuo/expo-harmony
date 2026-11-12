/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoRuntimePermissionsKey, ExpoModuleContext, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { bundleManager, Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ExpoContactsError } from './ContactsError';

const READ_CONTACTS: Permissions = 'ohos.permission.READ_CONTACTS';
const WRITE_CONTACTS: Permissions = 'ohos.permission.WRITE_CONTACTS';
const SELF_PERMISSION_STATUS_API: number = 20;
const REQUEST_ERROR_REASONS_API: number = 18;
const PREFERENCES_NAME: string = 'ExpoContactsPermissions';

enum RequestReason {
  Success = 0,
  InvalidPermission = 1,
  NotDeclared = 2,
  ConditionsNotMet = 3,
  CannotRequest = 5,
  ManualSettings = 6,
}

export class ContactsPermissionResponse {
  status: string;
  granted: boolean;
  canAskAgain: boolean;
  expires: string = 'never';
  accessPrivileges: string;

  constructor(granted: boolean, denied: boolean, read: boolean) {
    this.status = granted ? 'granted' : denied ? 'denied' : 'undetermined';
    this.granted = granted;
    this.canAskAgain = granted || !denied;
    this.accessPrivileges = read ? 'all' : 'none';
  }
}

export class ContactsPermissions {
  private readonly context: ExpoModuleContext;
  private pending?: Promise<ContactsPermissionResponse>;
  private readonly denials: Map<Permissions, boolean> = new Map<Permissions, boolean>();

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

  ensureRead(): void {
    this.ensure(READ_CONTACTS);
  }

  ensureWrite(): void {
    this.ensureRead();
    this.ensure(WRITE_CONTACTS);
  }

  private ensure(permission: Permissions): void {
    if (this.context.permissionStatus(permission) !== ExpoPermissionStatus.GRANTED) {
      throw new ExpoContactsError('ERR_CONTACTS_MISSING_PERMISSION', `Missing ${permission} permission.`);
    }
  }

  private declaredPermissions(): Permissions[] {
    this.context.assertActive();

    const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION;
    const details = bundleManager.getBundleInfoForSelfSync(flags).reqPermissionDetails;
    if (!details?.some((permission: bundleManager.ReqPermissionDetail): boolean => permission.name === READ_CONTACTS)) return [];

    return details.some((permission: bundleManager.ReqPermissionDetail): boolean => permission.name === WRITE_CONTACTS)
      ? [READ_CONTACTS, WRITE_CONTACTS]
      : [READ_CONTACTS];
  }

  async get(): Promise<ContactsPermissionResponse> {
    const permissions = this.declaredPermissions();
    if (permissions.length === 0) return new ContactsPermissionResponse(false, true, false);

    let granted = true;
    let denied = false;

    for (const permission of permissions) {
      const system = this.context.systemPermissionStatus(permission) === ExpoPermissionStatus.GRANTED;
      if (system && deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API) await this.setDenied(permission, false);

      const history = deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API ? await this.wasDenied(permission) : undefined;
      const status = this.context.permissionStatus(permission, history);
      if (status === ExpoPermissionStatus.GRANTED) continue;

      granted = false;
      denied = denied || status !== ExpoPermissionStatus.NOT_DETERMINED;
    }

    return new ContactsPermissionResponse(granted, denied, this.context.permissionStatus(READ_CONTACTS) === ExpoPermissionStatus.GRANTED);
  }

  async request(): Promise<ContactsPermissionResponse> {
    if (this.pending !== undefined) return await this.pending;

    const pending = this.requestOnce();
    this.pending = pending;

    try {
      return await pending;
    } finally {
      this.pending = undefined;
    }
  }

  private async requestOnce(): Promise<ContactsPermissionResponse> {
    const permissions = this.declaredPermissions();
    if (permissions.length === 0) throw new ExpoContactsError('ERR_CONTACTS_PERMISSION_REQUEST', `Check the module.json5 declaration for ${READ_CONTACTS}.`);

    const request = await this.context.requestPermissions(permissions);

    let restricted = false;
    for (const result of request.systemResults) {
      for (const permission of permissions) {
        const index = result.permissions.indexOf(permission);
        const reason = deviceInfo.sdkApiVersion >= REQUEST_ERROR_REASONS_API ? result.errorReasons?.[index] : undefined;

        if (
          index < 0 ||
          reason === RequestReason.InvalidPermission ||
          reason === RequestReason.NotDeclared ||
          ((reason === undefined || reason === RequestReason.Success) &&
            result.authResults[index] !== ExpoPermissionStatus.GRANTED &&
            result.authResults[index] !== ExpoPermissionStatus.DENIED)
        ) {
          throw new ExpoContactsError('ERR_CONTACTS_PERMISSION_REQUEST', `Check the module.json5 declaration for ${permission}.`);
        }

        const blocked = reason === RequestReason.ConditionsNotMet || reason === RequestReason.CannotRequest || reason === RequestReason.ManualSettings;
        restricted = restricted || blocked;

        if (
          deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API &&
          (((reason === undefined || reason === RequestReason.Success) &&
            (result.authResults[index] === ExpoPermissionStatus.GRANTED || result.dialogShownResults?.[index] === true)) ||
            blocked)
        ) {
          await this.setDenied(permission, result.authResults[index] !== ExpoPermissionStatus.GRANTED);
        }
      }
    }

    const response = await this.get();
    if (this.context.services.get(ExpoRuntimePermissionsKey) !== undefined) return response;

    if (!response.granted) {
      response.status = 'denied';
      response.canAskAgain = response.canAskAgain && !restricted;
    }

    return response;
  }

  private async wasDenied(permission: Permissions): Promise<boolean> {
    const known = this.denials.get(permission);
    if (known !== undefined) return known;

    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: this.context.preferenceName(PREFERENCES_NAME) });
      const value = (await store.get(permission, false)) === true;
      if (!this.denials.has(permission)) this.denials.set(permission, value);
    } catch (_) {
      // Missing history must never override an OS grant.
    }

    return this.denials.get(permission) ?? false;
  }

  private async setDenied(permission: Permissions, denied: boolean): Promise<void> {
    if (this.denials.get(permission) === denied) return;

    this.denials.set(permission, denied);

    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: this.context.preferenceName(PREFERENCES_NAME) });
      await store.put(permission, denied);
      await store.flush();
    } catch (_) {
      // Keep in-memory denial history when persistence fails.
    }
  }
}
