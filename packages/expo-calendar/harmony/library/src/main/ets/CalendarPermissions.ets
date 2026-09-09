import { ExpoModuleContext, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';

const CALENDAR_PERMISSIONS: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
const SELF_PERMISSION_STATUS_API: number = 20;
const PREFERENCES_NAME: string = 'ExpoCalendarPermissions';

enum RequestReason {
  Success = 0,
  InvalidPermission = 1,
  NotDeclared = 2,
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

  ensureGranted(): void {
    if (
      !CALENDAR_PERMISSIONS.every((permission: Permissions): boolean => this.context.permissionStatus(permission) === ExpoPermissionStatus.GRANTED)
    ) {
      throw new ExpoModuleError('E_MISSING_PERMISSIONS', 'CALENDAR permission is required to do this operation.');
    }
  }

  async get(): Promise<CalendarPermissionResponse> {
    let undetermined: boolean = false;
    let denied: boolean = false;

    for (const permission of CALENDAR_PERMISSIONS) {
      const status = this.context.permissionStatus(permission);
      if (status === ExpoPermissionStatus.GRANTED) {
        if (deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API) await this.rememberDenial(permission, false);
        continue;
      }

      const isDenied =
        deviceInfo.sdkApiVersion >= SELF_PERMISSION_STATUS_API ? status !== ExpoPermissionStatus.NOT_DETERMINED : await this.wasDenied(permission);
      denied = denied || isDenied;
      undetermined = undetermined || !isDenied;
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
    const result = await this.context.requestPermissions(CALENDAR_PERMISSIONS);
    let cannotAsk: boolean = false;

    for (const permission of CALENDAR_PERMISSIONS) {
      const index = result.permissions.indexOf(permission);
      const reason = result.errorReasons?.[index] ?? RequestReason.Success;
      const granted = result.authResults[index] === ExpoPermissionStatus.GRANTED;
      if (
        index < 0 ||
        reason === RequestReason.InvalidPermission ||
        reason === RequestReason.NotDeclared ||
        (reason === RequestReason.Success && !granted && result.authResults[index] !== ExpoPermissionStatus.DENIED)
      ) {
        throw new ExpoModuleError('ERR_CALENDAR_PERMISSION_REQUEST', `Invalid permission result for ${permission}. Check module.json5 declarations.`);
      }

      if (
        deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API &&
        reason === RequestReason.Success &&
        (granted || result.dialogShownResults?.[index] === true)
      ) {
        await this.rememberDenial(permission, !granted);
      }
      if (!granted && (reason === RequestReason.CannotRequest || reason === RequestReason.ManualSettings)) cannotAsk = true;
    }

    const response = await this.get();
    return response.granted ? response : new CalendarPermissionResponse('denied', response.canAskAgain && !cannotAsk);
  }

  private async wasDenied(permission: Permissions): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });
      return (await store.get(permission, false)) === true;
    } catch (_) {
      return false;
    }
  }

  private async rememberDenial(permission: Permissions, denied: boolean): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });
      if ((await store.get(permission, false)) === denied) return;

      await store.put(permission, denied);
      await store.flush();
    } catch (_) {
      // API 18–19 have no permission-history query. Persistence is best effort.
    }
  }
}
