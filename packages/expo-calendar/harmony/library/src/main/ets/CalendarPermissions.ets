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
  ServiceUnavailable = 12,
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
  private readonly context: ExpoModuleContext;

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

    if (!this.hasWriteAccess()) {
      throw new ExpoModuleError('E_MISSING_PERMISSIONS', 'WRITE_CALENDAR permission is required to change calendars.');
    }
  }

  hasWriteAccess(): boolean {
    return this.hasAccess(WRITE_CALENDAR, WRITE_WHOLE_CALENDAR);
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
      this.permissionToRequest(READ_CALENDAR, READ_WHOLE_CALENDAR, details),
      this.permissionToRequest(WRITE_CALENDAR, WRITE_WHOLE_CALENDAR, details),
    ];
  }

  private permissionToRequest(ordinary: Permissions, whole: Permissions, details?: bundleManager.ReqPermissionDetail[]): Permissions {
    if (details?.some((permission: bundleManager.ReqPermissionDetail): boolean => permission.name === whole)) {
      const response = this.context.getPermissionResponse(whole);
      if (response.canAskAgain) return whole;
    }
    return ordinary;
  }

  private async groupStatus(ordinary: Permissions, whole: Permissions): Promise<ExpoPermissionStatus> {
    const status = this.context.getPermissionResponse(ordinary).status;

    if (deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API) {
      if (await this.wasDenied(ordinary)) {
        if (status === ExpoPermissionStatus.GRANTED) await this.clearLegacyDenial(ordinary);
        if (status === ExpoPermissionStatus.NOT_DETERMINED) return ExpoPermissionStatus.DENIED;
      }
      return status;
    }
    if (status === ExpoPermissionStatus.GRANTED || deviceInfo.sdkApiVersion < WHOLE_CALENDAR_API) return status;

    const alternative = this.context.getPermissionResponse(whole).status;
    if (alternative === ExpoPermissionStatus.GRANTED || alternative === ExpoPermissionStatus.NOT_DETERMINED) {
      return alternative;
    }

    return status;
  }

  async get(): Promise<CalendarPermissionResponse> {
    this.context.assertActive();

    if (!canIUse('SystemCapability.Applications.CalendarData')) {
      return new CalendarPermissionResponse('denied', false);
    }

    const read = await this.groupStatus(READ_CALENDAR, READ_WHOLE_CALENDAR);
    const write = await this.groupStatus(WRITE_CALENDAR, WRITE_WHOLE_CALENDAR);
    this.context.assertActive();

    if (read === ExpoPermissionStatus.GRANTED && write === ExpoPermissionStatus.GRANTED) {
      return new CalendarPermissionResponse('granted', true);
    }

    const denied = [read, write].some((status: ExpoPermissionStatus): boolean =>
      status !== ExpoPermissionStatus.GRANTED && status !== ExpoPermissionStatus.NOT_DETERMINED);

    return new CalendarPermissionResponse(denied ? 'denied' : 'undetermined', !denied);
  }

  async request(): Promise<CalendarPermissionResponse> {
    this.context.assertActive();

    if (!canIUse('SystemCapability.Applications.CalendarData')) return this.get();

    const permissions = this.requestedPermissions().filter((permission: Permissions): boolean =>
      this.context.permissionStatus(permission) !== ExpoPermissionStatus.GRANTED);
    if (permissions.length === 0) return this.get();

    const results = (await this.context.requestPermissions(permissions)).systemResults;

    let blocked = false;
    for (const result of results) {
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

        if (reason === RequestReason.ServiceUnavailable) {
          throw new ExpoModuleError('ERR_CALENDAR_PERMISSION_REQUEST', 'The system calendar permission request service is unavailable.');
        }

        const restricted = reason === RequestReason.ConditionsNotMet || reason === RequestReason.CannotRequest ||
          reason === RequestReason.ManualSettings;

        if (!granted && restricted && (permission === READ_CALENDAR || permission === WRITE_CALENDAR)) blocked = true;
      }
    }

    const response = await this.get();

    if (this.context.services.get(ExpoRuntimePermissionsKey) !== undefined && results.length === 0) return response;

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

  private async clearLegacyDenial(permission: Permissions): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: this.context.preferenceName(PREFERENCES_NAME) });

      await store.delete(permission);
      await store.flush();
    } catch (_) {
      // API 18–19 have no permission-history query. Persistence is best effort.
    }
  }
}
