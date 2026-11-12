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

const READ_CALENDAR: Permissions = 'ohos.permission.READ_CALENDAR';
const WRITE_CALENDAR: Permissions = 'ohos.permission.WRITE_CALENDAR';
const READ_WHOLE_CALENDAR: Permissions = 'ohos.permission.READ_WHOLE_CALENDAR';
const WRITE_WHOLE_CALENDAR: Permissions = 'ohos.permission.WRITE_WHOLE_CALENDAR';
const WHOLE_CALENDAR_API: number = 21;
const SELF_PERMISSION_STATUS_API: number = 20;
const PREFERENCES_NAME: string = 'ExpoCalendarPermissions';

enum RequestReason {
  Success = 0,
  InvalidPermission = 1,
  NotDeclared = 2,
  ConditionsNotMet = 3,
  CannotRequest = 5,
  ManualSettings = 6,
}

export class CalendarPermissionResponse {
  status: string;
  granted: boolean;
  canAskAgain: boolean;
  expires: string = 'never';

  constructor(status: string, canAskAgain: boolean) {
    this.status = status;
    this.granted = status === 'granted';
    this.canAskAgain = canAskAgain;
  }
}

export class CalendarPermissions {
  private context: ExpoModuleContext;
  private pending?: Promise<CalendarPermissionResponse>;

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

  ensureReadable(): void {
    if (!this.hasAccess(READ_CALENDAR, READ_WHOLE_CALENDAR)) {
      throw new ExpoModuleError('E_MISSING_PERMISSIONS', 'READ_CALENDAR permission is required to read calendars.');
    }
  }

  ensureWritable(): void {
    this.ensureReadable();
    if (!this.hasAccess(WRITE_CALENDAR, WRITE_WHOLE_CALENDAR)) {
      throw new ExpoModuleError('E_MISSING_PERMISSIONS', 'WRITE_CALENDAR permission is required to change calendars.');
    }
  }

  private hasAccess(ordinary: Permissions, whole: Permissions): boolean {
    return this.context.permissionStatus(ordinary) === ExpoPermissionStatus.GRANTED ||
      (deviceInfo.sdkApiVersion >= WHOLE_CALENDAR_API && this.context.permissionStatus(whole) === ExpoPermissionStatus.GRANTED);
  }

  private requestedPermissions(): Permissions[] {
    this.context.assertActive();
    if (deviceInfo.sdkApiVersion < WHOLE_CALENDAR_API) return [READ_CALENDAR, WRITE_CALENDAR];

    const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION;
    const details = bundleManager.getBundleInfoForSelfSync(flags).reqPermissionDetails;
    return [
      details?.some((permission: bundleManager.ReqPermissionDetail): boolean => permission.name === READ_WHOLE_CALENDAR)
        ? READ_WHOLE_CALENDAR : READ_CALENDAR,
      details?.some((permission: bundleManager.ReqPermissionDetail): boolean => permission.name === WRITE_WHOLE_CALENDAR)
        ? WRITE_WHOLE_CALENDAR : WRITE_CALENDAR,
    ];
  }

  async get(): Promise<CalendarPermissionResponse> {
    let undetermined: boolean = false;
    let denied: boolean = false;

    const permissions = this.requestedPermissions();
    const baseline = [READ_CALENDAR, WRITE_CALENDAR];
    for (let index = 0; index < permissions.length; index += 1) {
      const permission = permissions[index];
      const ordinary = baseline[index];
      if (permission !== ordinary && this.context.permissionStatus(ordinary) === ExpoPermissionStatus.GRANTED) continue;

      const system = this.context.systemPermissionStatus(permission) === ExpoPermissionStatus.GRANTED;
      if (system && deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API) await this.rememberDenial(permission, false);

      const history = deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API ? await this.wasDenied(permission) : undefined;
      const status = this.context.permissionStatus(permission, history);
      if (status === ExpoPermissionStatus.GRANTED) continue;

      const rejected = status !== ExpoPermissionStatus.NOT_DETERMINED;
      denied = denied || rejected;
      undetermined = undetermined || !rejected;
    }

    return new CalendarPermissionResponse(denied ? 'denied' : undetermined ? 'undetermined' : 'granted', !denied);
  }

  async request(): Promise<CalendarPermissionResponse> {
    if (this.pending !== undefined) return await this.pending;

    const pending = this.requestOnce();
    this.pending = pending;

    try {
      return await pending;
    } finally {
      if (this.pending === pending) this.pending = undefined;
    }
  }

  private async requestOnce(): Promise<CalendarPermissionResponse> {
    const permissions = this.requestedPermissions();
    const request = await this.context.requestPermissions(permissions);

    let blocked: boolean = false;

    for (const result of request.systemResults) {
      for (const permission of permissions) {
        const index = result.permissions.indexOf(permission);
        const reason = result.errorReasons?.[index] ?? RequestReason.Success;
        const granted = result.authResults[index] === ExpoPermissionStatus.GRANTED;

        if (
          index < 0 ||
          reason === RequestReason.InvalidPermission ||
          reason === RequestReason.NotDeclared ||
          (reason === RequestReason.Success && !granted && result.authResults[index] !== ExpoPermissionStatus.DENIED)
        ) {
          throw new ExpoModuleError(
            'ERR_CALENDAR_PERMISSION_REQUEST',
            `Invalid permission result for ${permission}. Check module.json5 declarations.`,
          );
        }

        const restricted = reason === RequestReason.ConditionsNotMet || reason === RequestReason.CannotRequest ||
          reason === RequestReason.ManualSettings;
        if (
          deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API &&
          ((reason === RequestReason.Success && (granted || result.dialogShownResults?.[index] === true)) ||
            restricted)
        ) {
          await this.rememberDenial(permission, !granted);
        }

        if (!granted && restricted) blocked = true;
      }
    }

    const response = await this.get();

    if (this.context.services.get(ExpoRuntimePermissionsKey) !== undefined)
      return blocked && !response.granted ? new CalendarPermissionResponse('denied', false) : response;
    return response.granted ? response : new CalendarPermissionResponse('denied', response.canAskAgain && !blocked);
  }

  private async wasDenied(permission: Permissions): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: this.context.preferenceName(PREFERENCES_NAME) });
      return (await store.get(permission, false)) === true;
    } catch (_) {
      return false;
    }
  }

  private async rememberDenial(permission: Permissions, denied: boolean): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: this.context.preferenceName(PREFERENCES_NAME) });
      if ((await store.get(permission, false)) === denied) return;

      await store.put(permission, denied);
      await store.flush();
    } catch (_) {
      // API 18–19 have no permission-history query. Persistence is best effort.
    }
  }
}
