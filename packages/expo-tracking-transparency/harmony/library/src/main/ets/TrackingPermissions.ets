/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAppLifecycleState, ExpoModuleContext, ExpoModuleError, ExpoPermissionStatus } from '@expo-harmony/expo-modules-core';
import { Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';

export const TRACKING_PERMISSION: Permissions = 'ohos.permission.APP_TRACKING_CONSENT';
const OAID_CAPABILITY: string = 'SystemCapability.Advertising.OAID';
const PREFERENCES_NAME: string = 'ExpoTrackingTransparencyPermissions';
const FULL_PERMISSION_STATUS_API: number = 20;

enum RequestReason {
  Success = 0,
  InvalidPermission = 1,
  NotDeclared = 2,
  CannotRequest = 5,
  ManualSettings = 6,
}

export function isTrackingAvailable(): boolean {
  return canIUse(OAID_CAPABILITY);
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
  private readonly context: ExpoModuleContext;
  private pending?: Promise<TrackingPermissionResponse>;
  private legacyDenial?: Promise<boolean>;

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

  async get(): Promise<TrackingPermissionResponse> {
    if (!isTrackingAvailable()) return new TrackingPermissionResponse('denied', false);

    const response = this.context.getPermissionResponse(TRACKING_PERMISSION);
    const status = response.status;
    if (status === ExpoPermissionStatus.INVALID) throw new InvalidTrackingPermissionError();
    if (status === ExpoPermissionStatus.GRANTED) return new TrackingPermissionResponse('granted', true);

    if (status === ExpoPermissionStatus.NOT_DETERMINED && deviceInfo.sdkApiVersion < FULL_PERMISSION_STATUS_API) {
      this.legacyDenial ??= this.readLegacyDenial();
      if (await this.legacyDenial) return new TrackingPermissionResponse('denied', false);
    }

    return new TrackingPermissionResponse(status === ExpoPermissionStatus.NOT_DETERMINED ? 'undetermined' : 'denied', response.canAskAgain);
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

    if (current.granted || !isTrackingAvailable()) return current;

    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_TRACKING_TRANSPARENCY_BACKGROUND', 'Requesting tracking permission requires a foreground application.');
    }

    const request = await this.context.requestPermissions([TRACKING_PERMISSION]).catch((error: Error) => {
      throw new ExpoModuleError('ERR_TRACKING_TRANSPARENCY_PERMISSION', 'The system could not request tracking permission.', error);
    });

    let blocked = false;

    for (const result of request.systemResults) {
      const index = result.permissions.indexOf(TRACKING_PERMISSION);
      if (index < 0) throw new InvalidTrackingPermissionError();

      let reason: number = RequestReason.Success;
      if (deviceInfo.apiAvailable(18)) {
        reason = result.errorReasons?.[index] ?? RequestReason.Success;
      }

      if (reason === RequestReason.InvalidPermission || reason === RequestReason.NotDeclared) throw new InvalidTrackingPermissionError();

      const cannotRequest = reason === RequestReason.CannotRequest || reason === RequestReason.ManualSettings;
      if (!cannotRequest && reason !== RequestReason.Success) {
        throw new ExpoModuleError('ERR_TRACKING_TRANSPARENCY_PERMISSION', `The system could not request tracking permission (reason ${reason}).`);
      }

      const auth = result.authResults[index];
      if (!cannotRequest && auth !== ExpoPermissionStatus.GRANTED && auth !== ExpoPermissionStatus.DENIED) {
        throw new InvalidTrackingPermissionError();
      }

      blocked = blocked || cannotRequest;
    }

    const response = await this.get();
    if (blocked && !response.granted) return new TrackingPermissionResponse('denied', false);

    return response;
  }

  private async readLegacyDenial(): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(this.context.uiAbilityContext, { name: PREFERENCES_NAME });
      return (await store.get(TRACKING_PERMISSION, false)) === true;
    } catch {
      return false;
    }
  }
}
