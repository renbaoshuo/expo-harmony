/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAppLifecycleState, ExpoModuleContext, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { bundleManager, Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';

export const TRACKING_PERMISSION: Permissions = 'ohos.permission.APP_TRACKING_CONSENT';
const PREFERENCES_NAME: string = 'ExpoTrackingTransparencyPermissions';
const REQUEST_ERROR_REASONS_API: number = 18;
const FULL_PERMISSION_STATUS_API: number = 20;

enum RequestReason {
  Success = 0,
  InvalidPermission = 1,
  NotDeclared = 2,
  CannotRequest = 5,
  ManualSettings = 6,
}

export class TrackingPermissionResponse {
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

class InvalidTrackingPermissionError extends ExpoModuleError {
  constructor() {
    super(
      'ERR_TRACKING_TRANSPARENCY_PERMISSION',
      'Invalid tracking permission. Check APP_TRACKING_CONSENT in the application module.json5.',
    );
  }
}

export class TrackingPermissions {
  private context: ExpoModuleContext;
  private pending?: Promise<TrackingPermissionResponse>;
  private denied?: boolean;

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

  async get(): Promise<TrackingPermissionResponse> {
    let denied: boolean | undefined = undefined;

    if (deviceInfo.sdkApiVersion < FULL_PERMISSION_STATUS_API) {
      this.context.assertActive();

      const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION;
      const details = bundleManager.getBundleInfoForSelfSync(flags).reqPermissionDetails;
      if (!details?.some((permission: bundleManager.ReqPermissionDetail): boolean => permission.name === TRACKING_PERMISSION)) {
        throw new InvalidTrackingPermissionError();
      }

      if (this.context.systemPermissionStatus(TRACKING_PERMISSION) === ExpoPermissionStatus.GRANTED) {
        await this.rememberDenial(false);
      }

      denied = await this.wasDenied();
    }

    const status = this.context.permissionStatus(TRACKING_PERMISSION, denied);

    if (status === ExpoPermissionStatus.INVALID) throw new InvalidTrackingPermissionError();
    if (status === ExpoPermissionStatus.GRANTED) return new TrackingPermissionResponse('granted', true);
    if (status === ExpoPermissionStatus.NOT_DETERMINED) return new TrackingPermissionResponse('undetermined', true);

    return new TrackingPermissionResponse('denied', false);
  }

  async request(): Promise<TrackingPermissionResponse> {
    if (this.pending !== undefined) return await this.pending;

    const pending = this.requestOnce();
    this.pending = pending;

    try {
      return await pending;
    } finally {
      this.pending = undefined;
    }
  }

  private async requestOnce(): Promise<TrackingPermissionResponse> {
    const current = await this.get();

    if (current.granted) return current;

    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_TRACKING_TRANSPARENCY_BACKGROUND', 'Requesting tracking permission requires a foreground application.');
    }

    const request = await this.context.requestPermissions([TRACKING_PERMISSION]);
    let denied: boolean | undefined;
    let blocked: boolean = false;

    for (const result of request.systemResults) {
      const i = result.permissions.indexOf(TRACKING_PERMISSION);
      if (i < 0) throw new InvalidTrackingPermissionError();

      const reason = deviceInfo.sdkApiVersion >= REQUEST_ERROR_REASONS_API ? result.errorReasons?.[i] : undefined;
      if (reason === RequestReason.InvalidPermission || reason === RequestReason.NotDeclared) throw new InvalidTrackingPermissionError();

      blocked = reason === RequestReason.CannotRequest || reason === RequestReason.ManualSettings;
      if (!blocked && reason !== undefined && reason !== RequestReason.Success) {
        throw new ExpoModuleError('ERR_TRACKING_TRANSPARENCY_PERMISSION', `The system could not request tracking permission (reason ${reason}).`);
      }

      const auth = result.authResults[i];
      if (auth === ExpoPermissionStatus.GRANTED) {
        denied = false;
      } else if (blocked || (auth === ExpoPermissionStatus.DENIED && result.dialogShownResults?.[i] !== undefined)) {
        denied = true;
      } else if (auth !== ExpoPermissionStatus.DENIED) {
        throw new InvalidTrackingPermissionError();
      }
    }

    if (deviceInfo.sdkApiVersion < FULL_PERMISSION_STATUS_API && denied !== undefined) {
      await this.rememberDenial(denied);
    }

    const response = await this.get();
    if (blocked && !response.granted) return new TrackingPermissionResponse('denied', false);

    return response;
  }

  private async wasDenied(): Promise<boolean> {
    if (this.denied !== undefined) return this.denied;

    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });
      const denied = (await store.get(TRACKING_PERMISSION, false)) === true;

      return this.denied ?? denied;
    } catch {
      return this.denied ?? false;
    }
  }

  private async rememberDenial(denied: boolean): Promise<void> {
    if (this.denied === denied) return;
    this.denied = denied;

    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });

      if ((await store.get(TRACKING_PERMISSION, false)) === denied) return;

      await store.put(TRACKING_PERMISSION, denied);
      await store.flush();
    } catch {
      // Keep the known answer in memory when persistence fails.
    }
  }
}
