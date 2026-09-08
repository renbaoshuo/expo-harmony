import { ExpoModuleContext, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';

const APPROXIMATE_PERMISSION: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION';
const PRECISE_PERMISSION: Permissions = 'ohos.permission.LOCATION';
const SELF_PERMISSION_STATUS_API: number = 20;
const REQUEST_ERROR_REASONS_API: number = 18;
const PERMISSION_CHANGE_API: number = 18;
const PERMISSION_REQUEST_SUCCESS: number = 0;
const PREFERENCES_NAME: string = 'ExpoLocation';
const DENIED_KEY: string = 'foregroundPermissionDenied';

export class PermissionResponse {
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

export class LocationPermissions {
  private context: ExpoModuleContext;
  private pending?: Promise<PermissionResponse>;
  private observer?: abilityAccessCtrl.AtManager;
  private callback?: (info: abilityAccessCtrl.PermissionStateChangeInfo) => void;

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

  startObserving(onChange: () => void): void {
    if (deviceInfo.sdkApiVersion < PERMISSION_CHANGE_API || this.callback !== undefined) return;

    const observer = abilityAccessCtrl.createAtManager();
    const callback = (_info: abilityAccessCtrl.PermissionStateChangeInfo): void => {
      if (this.callback === callback) onChange();
    };

    observer.on('selfPermissionStateChange', [APPROXIMATE_PERMISSION, PRECISE_PERMISSION], callback);
    this.observer = observer;
    this.callback = callback;
  }

  stopObserving(): void {
    if (deviceInfo.sdkApiVersion < PERMISSION_CHANGE_API || this.callback === undefined) return;

    this.observer?.off('selfPermissionStateChange', [APPROXIMATE_PERMISSION, PRECISE_PERMISSION], this.callback);
    this.callback = undefined;
    this.observer = undefined;
  }

  hasForeground(): boolean {
    // Location Kit requires APPROXIMATELY_LOCATION even for precise fixes.
    return this.context.permissionStatus(APPROXIMATE_PERMISSION) === ExpoPermissionStatus.GRANTED;
  }

  ensureForeground(): void {
    if (!this.hasForeground()) {
      throw new ExpoModuleError('ERR_LOCATION_UNAUTHORIZED', 'Not authorized to use location services.');
    }
  }

  async getForeground(): Promise<PermissionResponse> {
    const status = this.context.permissionStatus(APPROXIMATE_PERMISSION);
    if (status === ExpoPermissionStatus.GRANTED) return new PermissionResponse('granted', true);
    if (deviceInfo.sdkApiVersion >= SELF_PERMISSION_STATUS_API) {
      const canAsk = status === ExpoPermissionStatus.NOT_DETERMINED;
      return new PermissionResponse(canAsk ? 'undetermined' : 'denied', canAsk);
    }

    // Before API 20, persist explicit denials without treating expired temporary grants as denials.
    const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });
    const denied = await store.get(DENIED_KEY, false);

    return new PermissionResponse(denied === true ? 'denied' : 'undetermined', denied !== true);
  }

  async requestForeground(): Promise<PermissionResponse> {
    if (this.pending !== undefined) return await this.pending;

    const pending = this.requestOnce();
    this.pending = pending;

    try {
      return await pending;
    } finally {
      if (this.pending === pending) this.pending = undefined;
    }
  }

  private async requestOnce(): Promise<PermissionResponse> {
    const result = await this.context.requestPermissions([APPROXIMATE_PERMISSION, PRECISE_PERMISSION]);
    const index = result.permissions.indexOf(APPROXIMATE_PERMISSION);

    if (index < 0 || (result.authResults[index] !== ExpoPermissionStatus.GRANTED && result.authResults[index] !== ExpoPermissionStatus.DENIED)) {
      throw new ExpoModuleError(
        'ERR_LOCATION_PERMISSION_REQUEST',
        'Declare both HarmonyOS location permissions with a reason and usedScene in module.json5.',
      );
    }
    if (deviceInfo.sdkApiVersion >= REQUEST_ERROR_REASONS_API) {
      const reason = result.errorReasons?.[index];
      if (reason !== undefined && reason !== PERMISSION_REQUEST_SUCCESS) {
        throw new ExpoModuleError('ERR_LOCATION_PERMISSION_REQUEST', `HarmonyOS could not request location permission (reason ${reason}).`);
      }
    }

    // A completed API call without a dialog is not proof of a user decision.
    if (
      deviceInfo.sdkApiVersion < SELF_PERMISSION_STATUS_API &&
      (result.authResults[index] === ExpoPermissionStatus.GRANTED || result.dialogShownResults?.[index] === true)
    ) {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });
      await store.put(DENIED_KEY, result.authResults[index] === ExpoPermissionStatus.DENIED);
      await store.flush();
    }

    return await this.getForeground();
  }
}
